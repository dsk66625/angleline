class_name TrialLink
extends Node

signal state_changed(message: String)
signal peer_arrived
signal peer_departed
signal input_received(command: Dictionary)
signal snapshot_received(state: Dictionary)
signal shot_received(event: Dictionary)

const HOST_ID := 1
const INPUT_BYTES := 24
const INPUT_HISTORY := 4
const MAX_SEQUENCE := 2147483647
const MAX_SNAPSHOT_BYTES := 16384
const MAX_SHOT_BYTES := 2048
const BUTTONS := [&"jump", &"crouch", &"walk", &"fire", &"reload", &"fire_pressed", &"jump_held"]

var is_host := false
var active := false
var remote_ready := false
var _peer: ENetMultiplayerPeer
var _remote_id := 0
var _sent_inputs: Array[PackedByteArray] = []
var _last_sent := -1
var _last_received := -1
var _command_credit := 16.0
var _credit_time_us := 0


func _ready() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)


func start_host(port: int) -> int:
	if port < 1 or port > 65535:
		return ERR_INVALID_PARAMETER
	if active:
		return ERR_ALREADY_IN_USE
	var peer := ENetMultiplayerPeer.new()
	var result := peer.create_server(port, 1, 4)
	if result != OK:
		state_changed.emit("房间创建失败，请检查端口是否被占用。")
		return result
	_peer = peer
	active = true
	is_host = true
	multiplayer.multiplayer_peer = peer
	state_changed.emit("主机正在等待另一名玩家。")
	return OK


func join_host(address: String, port: int) -> int:
	address = address.strip_edges()
	if address.is_empty() or address.length() > 253 or port < 1 or port > 65535:
		return ERR_INVALID_PARAMETER
	if active:
		return ERR_ALREADY_IN_USE
	var peer := ENetMultiplayerPeer.new()
	var result := peer.create_client(address, port, 4)
	if result != OK:
		state_changed.emit("未能创建连接，请检查地址和端口。")
		return result
	_peer = peer
	active = true
	multiplayer.multiplayer_peer = peer
	state_changed.emit("正在连接房主……")
	return OK


func leave() -> void:
	if active:
		_close_session("已离开房间。")


func _close_session(message: String) -> void:
	var had_remote := remote_ready
	active = false
	is_host = false
	_reset_remote()
	if _peer != null:
		if multiplayer.multiplayer_peer == _peer:
			multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
		_peer.close()
		_peer = null
	if had_remote:
		peer_departed.emit()
	state_changed.emit(message)


func _reset_remote() -> void:
	remote_ready = false
	_remote_id = 0
	_sent_inputs.clear()
	_last_sent = -1
	_last_received = -1
	_command_credit = 16.0
	_credit_time_us = Time.get_ticks_usec()


func _on_peer_connected(id: int) -> void:
	if active and is_host and not remote_ready and id > HOST_ID:
		_remote_id = id
		remote_ready = true
		_credit_time_us = Time.get_ticks_usec()
		state_changed.emit("另一名玩家已加入。")
		peer_arrived.emit()


func _on_peer_disconnected(id: int) -> void:
	if active and is_host and remote_ready and id == _remote_id:
		_reset_remote()
		peer_departed.emit()
		state_changed.emit("对方已离开，房间继续等待玩家。")


func _on_connected() -> void:
	if active and not is_host and not remote_ready:
		_remote_id = HOST_ID
		remote_ready = true
		state_changed.emit("已连接房主。")
		peer_arrived.emit()


func _on_connection_failed() -> void:
	if active and not is_host:
		_close_session("连接失败，请检查房主地址和端口。")


func _on_server_disconnected() -> void:
	if active and not is_host:
		_close_session("与房主的连接已断开。")


# Each packet repeats up to three older commands, oldest first. Only input is
# accepted from a guest. Position, damage and hits travel from the host.
func send_input(command: Dictionary) -> void:
	if not remote_ready or is_host:
		return
	var seq: int = command.get("seq", -1)
	if seq <= _last_sent or seq > MAX_SEQUENCE:
		return
	var move: Vector2 = command.get("move", Vector2.ZERO)
	var yaw: float = command.get("yaw", 0.0)
	var pitch: float = command.get("pitch", 0.0)
	if not move.is_finite() or not is_finite(yaw) or not is_finite(pitch):
		return
	var encoded := PackedByteArray()
	encoded.resize(INPUT_BYTES)
	encoded.encode_u32(0, seq)
	encoded.encode_float(4, move.x)
	encoded.encode_float(8, move.y)
	encoded.encode_float(12, yaw)
	encoded.encode_float(16, pitch)
	var buttons := 0
	for i in BUTTONS.size():
		if command.get(BUTTONS[i], false):
			buttons |= 1 << i
	encoded.encode_u16(20, buttons)
	encoded.encode_s16(22, clampi(int(command.get("weapon", -1)), -1, TrialFighter.KNIFE))
	_last_sent = seq
	_sent_inputs.append(encoded)
	if _sent_inputs.size() > INPUT_HISTORY:
		_sent_inputs.pop_front()
	var batch := PackedByteArray()
	for entry in _sent_inputs:
		batch.append_array(entry)
	_receive_inputs.rpc_id(HOST_ID, batch)


@rpc("any_peer", "call_remote", "unreliable_ordered", 1)
func _receive_inputs(batch: PackedByteArray) -> void:
	if not is_host or not remote_ready or multiplayer.get_remote_sender_id() != _remote_id:
		return
	if batch.is_empty() or batch.size() > INPUT_BYTES * INPUT_HISTORY or batch.size() % INPUT_BYTES != 0:
		return
	var now := Time.get_ticks_usec()
	var elapsed := float(now - _credit_time_us) / 1000000.0
	_command_credit = minf(16.0, _command_credit + elapsed * float(Engine.physics_ticks_per_second) * 1.1)
	_credit_time_us = now
	for offset in range(0, batch.size(), INPUT_BYTES):
		var seq := batch.decode_u32(offset)
		if seq <= _last_received or seq > MAX_SEQUENCE or _command_credit < 1.0:
			continue
		var move := Vector2(batch.decode_float(offset + 4), batch.decode_float(offset + 8))
		var yaw := batch.decode_float(offset + 12)
		var pitch := batch.decode_float(offset + 16)
		var weapon := batch.decode_s16(offset + 22)
		if not move.is_finite() or absf(move.x) > 1.01 or absf(move.y) > 1.01:
			continue
		if not is_finite(yaw) or absf(yaw) > 100000.0 or not is_finite(pitch) or absf(pitch) > PI * 0.5 + 0.001:
			continue
		if weapon < -1 or weapon > TrialFighter.KNIFE:
			continue
		var command := {"seq": seq, "move": move.limit_length(1.0), "yaw": wrapf(yaw, -PI, PI), "pitch": pitch}
		if weapon >= 0:
			command["weapon"] = weapon
		var buttons := batch.decode_u16(offset + 20)
		for i in BUTTONS.size():
			command[BUTTONS[i]] = (buttons & (1 << i)) != 0
		_command_credit -= 1.0
		_last_received = seq
		input_received.emit(command)


func send_snapshot(state: Dictionary) -> void:
	if is_host and remote_ready:
		var payload := var_to_bytes(state)
		if payload.size() <= MAX_SNAPSHOT_BYTES:
			_receive_snapshot.rpc_id(_remote_id, payload)


@rpc("authority", "call_remote", "unreliable_ordered", 2)
func _receive_snapshot(payload: PackedByteArray) -> void:
	if not _accept_host_packet(payload, MAX_SNAPSHOT_BYTES):
		return
	var decoded: Variant = bytes_to_var(payload)
	if decoded is Dictionary:
		snapshot_received.emit(decoded)


func send_shot(event: Dictionary) -> void:
	if is_host and remote_ready:
		var payload := var_to_bytes(event)
		if payload.size() <= MAX_SHOT_BYTES:
			_receive_shot.rpc_id(_remote_id, payload)


@rpc("authority", "call_remote", "reliable", 3)
func _receive_shot(payload: PackedByteArray) -> void:
	if not _accept_host_packet(payload, MAX_SHOT_BYTES):
		return
	var decoded: Variant = bytes_to_var(payload)
	if decoded is Dictionary:
		shot_received.emit(decoded)


func _accept_host_packet(payload: PackedByteArray, limit: int) -> bool:
	return remote_ready and not is_host and multiplayer.get_remote_sender_id() == HOST_ID and not payload.is_empty() and payload.size() <= limit
