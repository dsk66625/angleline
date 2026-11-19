extends SceneTree
## godot --headless --fixed-fps 128 --path . --script res://duel_check.gd
## Validates D/01 geometry: rotational symmetry, spawn clearance, intended
## sightlines and blocks, and real fighter movement over the jump features.

const Fighter = preload("res://fighter.gd")
const Duel = preload("res://duel_world.gd")

var world: Duel
var actor: Fighter
var dt: float
var errors: Array[String] = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	dt = 1.0 / Engine.physics_ticks_per_second
	world = Duel.new()
	root.add_child(world)
	await physics_frame
	await physics_frame
	_check_symmetry()
	_check_spawns()
	_check_sightlines()
	await _check_movement()
	for problem in errors:
		push_error(problem)
	print("DUEL_CHECK errors=", errors.size())
	quit(0 if errors.is_empty() else 1)


func _expect(ok: bool, problem: String) -> void:
	if not ok:
		errors.append(problem)


func _check_symmetry() -> void:
	var bodies: Array[StaticBody3D] = []
	for child in world.get_children():
		if child is StaticBody3D:
			bodies.append(child)
	var mirror := Basis(Vector3.UP, PI)
	var unmatched := 0
	for body in bodies:
		var twin_pos := Vector3(-body.position.x, body.position.y, -body.position.z)
		if body.position.distance_to(twin_pos) < 0.001:
			continue
		var matched := false
		for other in bodies:
			if other == body or other.position.distance_to(twin_pos) > 0.001:
				continue
			var shape_a: BoxShape3D = body.find_children("*", "CollisionShape3D", false, false)[0].shape
			var shape_b: BoxShape3D = other.find_children("*", "CollisionShape3D", false, false)[0].shape
			var basis_ok := (mirror * body.transform.basis * mirror).is_equal_approx(other.transform.basis)
			if shape_a.size.is_equal_approx(shape_b.size) and basis_ok:
				matched = true
				break
		if not matched:
			unmatched += 1
			print("DUEL symmetry unmatched body at ", body.position)
	_expect(unmatched == 0, "%d solid bodies lack a rotational twin" % unmatched)
	print("DUEL symmetry solids=", bodies.size(), " unmatched=", unmatched)


func _hull_clear(at: Vector3, height: float) -> bool:
	var shape := BoxShape3D.new()
	shape.size = Vector3(Fighter.HULL_WIDTH, height, Fighter.HULL_WIDTH)
	var params := PhysicsShapeQueryParameters3D.new()
	params.shape = shape
	params.transform = Transform3D(Basis.IDENTITY, at + Vector3.UP * height * 0.5)
	params.collision_mask = 1
	return world.get_world_3d().direct_space_state.intersect_shape(params, 8).is_empty()


func _check_spawns() -> void:
	for slot in Duel.SPAWNS.size():
		var at: Vector3 = Duel.SPAWNS[slot]
		_expect(_hull_clear(at, Fighter.STAND_HEIGHT), "Spawn %d standing hull collides" % slot)
		_expect(_hull_clear(at, Fighter.DUCK_HEIGHT), "Spawn %d crouched hull collides" % slot)
		for offset in [Vector3(0.4, 0, 0), Vector3(-0.4, 0, 0), Vector3(0, 0, 0.4), Vector3(0, 0, -0.4)]:
			_expect(_hull_clear(at + offset, Fighter.STAND_HEIGHT), "Spawn %d hull collides at offset %s" % [slot, offset])
	print("DUEL spawns clearance checked")


func _ray(from: Vector3, to: Vector3) -> Dictionary:
	var query := PhysicsRayQueryParameters3D.create(from, to, 1)
	return world.get_world_3d().direct_space_state.intersect_ray(query)


func _check_sightlines() -> void:
	var eye_a: Vector3 = Duel.SPAWNS[0] + Vector3.UP * Fighter.STAND_EYE
	var eye_b: Vector3 = Duel.SPAWNS[1] + Vector3.UP * Fighter.STAND_EYE
	_expect(not _ray(eye_a, eye_b).is_empty(), "Spawn-to-spawn sightline should be blocked by the mid screen")
	# Standing on the north deck shoots over the parapet into mid.
	var deck_eye := Vector3(10.85, 1.05 + Fighter.STAND_EYE, 2.4)
	_expect(_ray(deck_eye, Vector3(0, 1.0, 0)).is_empty(), "High-line standing overlook into mid should be open")
	# Crouching behind the same parapet hides from mid.
	var deck_duck := Vector3(10.85, 1.05 + Fighter.DUCK_EYE, 1.2)
	_expect(not _ray(Vector3(0, 1.2, 2.0), deck_duck).is_empty(), "High-line crouch behind parapet should be hidden")
	# The duct blocks standing eyes but passes crouched eyes.
	var duct_stand := Vector3(-10.85, 0.02 + Fighter.STAND_EYE, 8.2)
	var duct_duck := Vector3(-10.85, 0.02 + Fighter.DUCK_EYE, 8.2)
	_expect(not _ray(duct_stand, Vector3(-10.85, duct_stand.y, 5.6)).is_empty(), "Duct should block standing eye line")
	_expect(_ray(duct_duck, Vector3(-10.85, duct_duck.y, 5.6)).is_empty(), "Duct should pass crouched eye line")
	# Doorway links corridor and mid at standing height.
	_expect(_ray(Vector3(-8.0, 1.0, 7.0), Vector3(-4.0, 1.0, 7.0)).is_empty(), "Doorway at z 7 should be open")
	# Table cover hides a crouched player on the table from the enemy spawn side.
	var table_duck := Vector3(1.35, 0.7 + Fighter.DUCK_EYE, 1.35)
	_expect(not _ray(Vector3(0, 1.2, 6.5), table_duck).is_empty(), "Table cover should hide a crouched player")
	print("DUEL sightlines checked")


func _spawn_actor(at: Vector3, yaw: float) -> void:
	if is_instance_valid(actor):
		actor.free()
	actor = Fighter.new()
	actor.position = at
	actor.yaw = yaw
	world.add_child(actor)
	for _i in 64:
		await _tick({})
		if actor.grounded:
			return
	_expect(false, "Actor did not settle at %s" % at)


func _tick(command: Dictionary) -> void:
	await physics_frame
	actor.step(command, dt)


func _run_ticks(count: int, command: Dictionary) -> void:
	for _i in count:
		await _tick(command)


func _check_movement() -> void:
	var forward := {"move": Vector2(0, -1)}
	# Standing jump from the floor onto the 0.70 m table.
	await _spawn_actor(Vector3(0, 0.02, 3.8), 0.0)
	await _run_ticks(30, forward)
	await _tick({"move": Vector2(0, -1), "jump": true})
	await _run_ticks(50, forward)
	await _run_ticks(60, {})
	_expect(actor.grounded and absf(actor.position.y - 0.7) < 0.06 and absf(actor.position.x) < 2.3 and absf(actor.position.z) < 2.3,
		"Table jump landed at %s grounded=%s" % [actor.position, actor.grounded])
	print("DUEL table jump y=", snappedf(actor.position.y, 0.001), " z=", snappedf(actor.position.z, 0.001))
	# Side jump through the 1.2 m parapet gap onto the 1.05 m deck. Take off
	# ~0.9 m before the deck edge so the arc clears the slab side.
	await _spawn_actor(Vector3(7.35, 0.02, 2.6), -PI * 0.5)
	await _run_ticks(25, forward)
	await _tick({"move": Vector2(0, -1), "jump": true})
	await _run_ticks(80, forward)
	await _run_ticks(40, {})
	_expect(actor.grounded and absf(actor.position.y - 1.05) < 0.06 and actor.position.x > 9.3,
		"Deck side jump landed at %s grounded=%s" % [actor.position, actor.grounded])
	print("DUEL deck jump y=", snappedf(actor.position.y, 0.001), " x=", snappedf(actor.position.x, 0.001))
	# Running jump across the 1.8 m deck gap.
	await _spawn_actor(Vector3(10.85, 1.07, 7.6), 0.0)
	await _run_ticks(20, forward)
	await _tick({"move": Vector2(0, -1), "jump": true})
	await _run_ticks(60, forward)
	await _run_ticks(60, {})
	_expect(actor.grounded and absf(actor.position.y - 1.05) < 0.06 and actor.position.z < 4.8,
		"Gap jump landed at %s grounded=%s" % [actor.position, actor.grounded])
	print("DUEL gap jump y=", snappedf(actor.position.y, 0.001), " z=", snappedf(actor.position.z, 0.001))
	# Walk up the ramp without jumping.
	await _spawn_actor(Vector3(11.2, 0.02, 16.2), 0.0)
	await _run_ticks(160, forward)
	_expect(actor.grounded and absf(actor.position.y - 1.05) < 0.06 and actor.position.z < 12.4,
		"Ramp walk ended at %s grounded=%s" % [actor.position, actor.grounded])
	print("DUEL ramp walk y=", snappedf(actor.position.y, 0.001), " z=", snappedf(actor.position.z, 0.001))
	# Crouch passes the duct; standing is stopped by it.
	await _spawn_actor(Vector3(-10.85, 0.02, 8.6), 0.0)
	await _run_ticks(200, {"move": Vector2(0, -1), "crouch": true})
	_expect(actor.grounded and actor.position.z < 6.0, "Crouch should pass the duct, ended z=%.3f" % actor.position.z)
	print("DUEL duct crouch z=", snappedf(actor.position.z, 0.001))
	await _spawn_actor(Vector3(-10.85, 0.02, 8.6), 0.0)
	await _run_ticks(200, forward)
	_expect(actor.position.z > 7.5, "Standing should be stopped by the duct, ended z=%.3f" % actor.position.z)
	print("DUEL duct stand z=", snappedf(actor.position.z, 0.001))
	# Walk through the doorway from corridor into mid.
	await _spawn_actor(Vector3(-8.0, 0.02, 7.0), -PI * 0.5)
	await _run_ticks(120, forward)
	_expect(actor.grounded and actor.position.x > -5.0, "Doorway walk ended at %s" % actor.position)
	print("DUEL doorway x=", snappedf(actor.position.x, 0.001))