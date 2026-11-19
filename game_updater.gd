extends Node

signal changed

enum State { IDLE, CHECKING, DOWNLOADING, READY, INSTALLING }

const API := "https://api.github.com/repos/dsk66625/angleline"
const TOKEN_PAGE := "https://github.com/settings/personal-access-tokens/new?name=Angleline+Updates&target_name=dsk66625&contents=read"
const CACHE := "user://updates"
const CREDENTIAL := CACHE + "/github-token.dpapi"
const INSTALLER := "res://update_install.ps1"
const MAX_PACKAGE_BYTES := 256 * 1024 * 1024
const ALLOWED_DOWNLOADS := [
	"https://release-assets.githubusercontent.com/",
	"https://objects.githubusercontent.com/",
]
const SECRETS := """
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Security
$inputLine = [Console]::ReadLine()
$scope = [Security.Cryptography.DataProtectionScope]::CurrentUser
$entropy = [Text.Encoding]::UTF8.GetBytes('Angleline GitHub updates')
"""

var current_version := str(ProjectSettings.get_setting("application/config/version"))
var state := State.IDLE
var status := "首次使用需要授权读取 GitHub 私有仓库。"
var next_version := ""
var _token := ""
var _digest := ""
var _package := ""
var _request: HTTPRequest
var _hash_thread: Thread


func supported() -> bool:
	return OS.get_name() == "Windows" and OS.has_feature("template")


func busy() -> bool:
	return state in [State.CHECKING, State.DOWNLOADING, State.INSTALLING]


func has_token() -> bool:
	return not _token.is_empty() or FileAccess.file_exists(CREDENTIAL)


func download_progress() -> float:
	if state != State.DOWNLOADING or not is_instance_valid(_request) or _request.get_body_size() <= 0:
		return 0.0
	return float(_request.get_downloaded_bytes()) / _request.get_body_size()


func start() -> void:
	if not supported():
		_set_status(State.IDLE, "请在 Windows 发行版中使用游戏更新。")
		return
	var result_path := _result_path()
	if FileAccess.file_exists(result_path):
		var code := FileAccess.get_file_as_string(result_path).strip_edges()
		if code == "UPDATED":
			_set_status(State.IDLE, "已更新到 v%s。" % current_version)
		elif not code.is_empty() and code != "READY":
			_set_status(State.IDLE, _install_message(code))
		if not code.is_empty() and code != "READY":
			DirAccess.remove_absolute(result_path)
			# Show the outcome on the first start after installation.
			return
	if has_token():
		check()


func check(candidate := "") -> void:
	if not supported() or busy():
		return
	var credential := candidate.strip_edges()
	if not credential.is_empty() and not _is_token(credential):
		_set_status(State.IDLE, "请输入有效的 GitHub 细粒度访问令牌。")
		return
	_set_status(State.CHECKING, "正在检查 GitHub 最新版本…")
	if credential.is_empty():
		credential = _token
		if credential.is_empty() and FileAccess.file_exists(CREDENTIAL):
			credential = await _windows_secret(FileAccess.get_file_as_string(CREDENTIAL), false)
		if not _is_token(credential):
			_set_status(State.IDLE, "请在此设备上设置 GitHub 读取令牌。")
			return
	var response := await _http_get(API + "/releases/latest", _headers(credential, "application/vnd.github+json"))
	if response[1] in [401, 404]:
		_set_status(State.IDLE, "GitHub 无法读取发行版。请检查令牌是否过期，且对 angleline 有只读权限。")
		return
	if response[0] != HTTPRequest.RESULT_SUCCESS or response[1] != 200:
		_set_status(State.IDLE, "无法连接 GitHub 或访问受限。可稍后重试。")
		return
	var release: Variant = JSON.parse_string(response[3].get_string_from_utf8())
	if release is not Dictionary or release.get("draft", true) or release.get("prerelease", true):
		_set_status(State.IDLE, "GitHub 未返回有效的正式发行版。")
		return
	var tag := str(release.get("tag_name", ""))
	var version := _version_parts(tag.trim_prefix("v"))
	if not tag.begins_with("v") or version.is_empty():
		_set_status(State.IDLE, "无法识别 GitHub 发行版本号。")
		return
	var save_failed := false
	if not candidate.strip_edges().is_empty():
		var protected_token := await _windows_secret(credential, true)
		save_failed = not _write_credential(protected_token)
	_token = credential
	if not _is_newer(version, _version_parts(current_version)):
		var message := "当前已是最新版本 v%s。" % current_version
		if save_failed:
			message += " Windows 无法保存令牌，仅在本次运行有效。"
		_set_status(State.IDLE, message)
		return
	var asset := _windows_asset(release, tag)
	if asset.is_empty():
		_set_status(State.IDLE, "%s 缺少可校验的 Windows x64 发行包。" % tag)
		return
	next_version = tag
	_digest = asset["digest"]
	await _download(int(asset["id"]), int(asset["size"]))
	if save_failed:
		status += " Windows 无法保存令牌，仅在本次运行有效。"
		changed.emit()


func forget_token() -> void:
	if busy():
		return
	if FileAccess.file_exists(CREDENTIAL) and DirAccess.remove_absolute(CREDENTIAL) != OK:
		_set_status(state, "无法删除本机保存的令牌。")
		return
	_token = ""
	_set_status(State.IDLE, "已清除本机的 GitHub 授权。")


func install() -> void:
	if not supported() or state != State.READY:
		return
	_set_status(State.INSTALLING, "正在验证更新并准备重启…")
	var result_path := _result_path()
	if FileAccess.file_exists(result_path) and DirAccess.remove_absolute(result_path) != OK:
		_set_status(State.READY, "无法重置更新状态文件。")
		return
	var script := FileAccess.get_file_as_string(INSTALLER)
	if script.is_empty():
		_set_status(State.READY, "发行版缺少更新安装程序。")
		return
	var command := "& {\n%s\n} -PackagePath %s -TargetExe %s -OldPid %d -ExpectedSha256 %s -ResultPath %s" % [
		script, _powershell_string(ProjectSettings.globalize_path(_package)),
		_powershell_string(OS.get_executable_path()), OS.get_process_id(),
		_powershell_string(_digest), _powershell_string(result_path),
	]
	var installer_pid := OS.create_process(_powershell(), _powershell_arguments(command))
	if installer_pid < 0:
		_set_status(State.READY, "无法启动 Windows 更新安装程序。")
		return
	var deadline := Time.get_ticks_msec() + 90000
	while Time.get_ticks_msec() < deadline:
		await get_tree().create_timer(0.1).timeout
		var code := FileAccess.get_file_as_string(result_path).strip_edges() if FileAccess.file_exists(result_path) else ""
		if code == "READY" and OS.is_process_running(installer_pid):
			get_tree().quit()
			return
		if not OS.is_process_running(installer_pid):
			_set_status(State.READY, _install_message(code))
			return
	_set_status(State.READY, "安装程序准备超时，游戏仍可继续使用。")


func _download(id: int, size: int) -> void:
	_set_status(State.DOWNLOADING, "正在下载并校验 %s…" % next_version)
	if DirAccess.make_dir_recursive_absolute(CACHE) != OK:
		_set_status(State.IDLE, "无法创建本机更新缓存。")
		return
	_package = "%s/%s-%s.zip" % [CACHE, next_version, _digest]
	if FileAccess.file_exists(_package) and await _file_digest(_package) == _digest:
		_set_status(State.READY, "%s 已下载，重启即可更新。" % next_version)
		return
	var partial := "%s/download-%d.part" % [CACHE, OS.get_process_id()]
	var response := await _http_get(API + "/releases/assets/%d" % id,
		_headers(_token, "application/octet-stream"), partial, size)
	if response[1] == 302:
		var target := _redirect_target(response[2])
		if not target.is_empty():
			response = await _http_get(target, PackedStringArray(), partial, size)
	if response[0] != HTTPRequest.RESULT_SUCCESS or response[1] != 200:
		_remove_partial(partial)
		_set_status(State.IDLE, "更新包下载失败。请检查连接后重试。")
		return
	var file := FileAccess.open(partial, FileAccess.READ)
	var exact_size := file != null and file.get_length() == size
	if file != null:
		file.close()
	if not exact_size or await _file_digest(partial) != _digest:
		_remove_partial(partial)
		_set_status(State.IDLE, "更新包校验失败。请重新检查更新。")
		return
	if DirAccess.rename_absolute(partial, _package) != OK:
		_remove_partial(partial)
		_set_status(State.IDLE, "无法保存已下载的更新包。")
		return
	_set_status(State.READY, "%s 已校验，重启即可更新。" % next_version)


func _http_get(url: String, headers: PackedStringArray, path := "", limit := 1024 * 1024) -> Array:
	_request = HTTPRequest.new()
	_request.use_threads = true
	_request.max_redirects = 0
	_request.accept_gzip = path.is_empty()
	_request.timeout = 20.0 if path.is_empty() else 300.0
	_request.body_size_limit = limit
	_request.download_file = path
	add_child(_request)
	var response := [HTTPRequest.RESULT_REQUEST_FAILED, 0, PackedStringArray(), PackedByteArray()]
	if _request.request(url, headers) == OK:
		response = await _request.request_completed
	_request.queue_free()
	_request = null
	return response


func _headers(token: String, accept: String) -> PackedStringArray:
	return PackedStringArray([
		"Accept: " + accept, "Authorization: Bearer " + token,
		"X-GitHub-Api-Version: 2022-11-28", "User-Agent: Angleline/" + current_version,
	])


func _file_digest(path: String) -> String:
	_hash_thread = Thread.new()
	if _hash_thread.start(func() -> String: return FileAccess.get_sha256(path)) != OK:
		_hash_thread = null
		return ""
	while _hash_thread.is_alive():
		await get_tree().create_timer(0.05).timeout
	var digest: String = _hash_thread.wait_to_finish()
	_hash_thread = null
	return digest


func _exit_tree() -> void:
	if _hash_thread != null:
		_hash_thread.wait_to_finish()


func _windows_secret(input: String, encrypt: bool) -> String:
	if input.is_empty() or input.length() > 2048:
		return ""
	var operation := """
$bytes = [Text.Encoding]::UTF8.GetBytes($inputLine)
$bytes = [Security.Cryptography.ProtectedData]::Protect($bytes, $entropy, $scope)
[Console]::WriteLine([Convert]::ToBase64String($bytes))
""" if encrypt else """
$bytes = [Convert]::FromBase64String($inputLine)
$bytes = [Security.Cryptography.ProtectedData]::Unprotect($bytes, $entropy, $scope)
[Console]::WriteLine([Text.Encoding]::UTF8.GetString($bytes))
"""
	var process := OS.execute_with_pipe(_powershell(), _powershell_arguments(SECRETS + operation), false)
	if process.is_empty():
		return ""
	var pipe: FileAccess = process["stdio"]
	if not pipe.store_string(input + "\n"):
		OS.kill(process["pid"])
		return ""
	var output := ""
	var deadline := Time.get_ticks_msec() + 8000
	while Time.get_ticks_msec() < deadline:
		output += pipe.get_buffer(4096).get_string_from_utf8()
		if "\n" in output:
			return output.get_slice("\n", 0).strip_edges()
		if not OS.is_process_running(process["pid"]):
			return ""
		await get_tree().create_timer(0.05).timeout
	OS.kill(process["pid"])
	return ""


func _write_credential(ciphertext: String) -> bool:
	if ciphertext.is_empty() or DirAccess.make_dir_recursive_absolute(CACHE) != OK:
		return false
	var pending := "%s.%d" % [CREDENTIAL, OS.get_process_id()]
	var file := FileAccess.open(pending, FileAccess.WRITE)
	if file == null:
		return false
	var written := file.store_string(ciphertext)
	file.close()
	if written and DirAccess.rename_absolute(pending, CREDENTIAL) == OK:
		return true
	_remove_partial(pending)
	return false


func _result_path() -> String:
	var exe_key := OS.get_executable_path().replace("\\", "/").to_lower().sha256_text().left(16)
	return ProjectSettings.globalize_path("%s/result-%s.txt" % [CACHE, exe_key])


func _set_status(new_state: State, message: String) -> void:
	state = new_state
	status = message
	changed.emit()


static func _remove_partial(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)


static func _powershell() -> String:
	return OS.get_environment("SystemRoot").path_join("System32/WindowsPowerShell/v1.0/powershell.exe")


static func _powershell_arguments(script: String) -> PackedStringArray:
	return PackedStringArray(["-NoLogo", "-NoProfile", "-NonInteractive", "-WindowStyle", "Hidden",
		"-EncodedCommand", Marshalls.raw_to_base64(script.to_utf16_buffer())])


static func _powershell_string(value: String) -> String:
	return "([Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('%s')))" % Marshalls.utf8_to_base64(value)


static func _is_token(token: String) -> bool:
	return (token.length() >= 30 and token.length() <= 255 and token.begins_with("github_pat_")
		and _contains_only(token, "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_"))


static func _version_parts(version: String) -> PackedInt32Array:
	var values := PackedInt32Array()
	var segments := version.split(".")
	if segments.size() != 3:
		return values
	for segment in segments:
		if segment.is_empty() or segment.length() > 8 or not _contains_only(segment, "0123456789"):
			return PackedInt32Array()
		values.append(int(segment))
	return values


static func _is_newer(remote: PackedInt32Array, local: PackedInt32Array) -> bool:
	if remote.size() != 3 or local.size() != 3:
		return false
	for index in range(3):
		if remote[index] != local[index]:
			return remote[index] > local[index]
	return false


static func _windows_asset(release: Dictionary, tag: String) -> Dictionary:
	var assets: Variant = release.get("assets", [])
	if assets is not Array:
		return {}
	var expected := "Angleline-%s-Windows-x64.zip" % tag
	for item in assets:
		if item is not Dictionary or item.get("name") != expected or item.get("state") != "uploaded":
			continue
		var id: Variant = item.get("id")
		var size: Variant = item.get("size")
		var digest := str(item.get("digest", "")).to_lower()
		if not ((id is float or id is int) and id >= 1 and id < 9007199254740992 and int(id) == id):
			continue
		if not ((size is float or size is int) and size > 0 and size <= MAX_PACKAGE_BYTES and int(size) == size):
			continue
		if digest.begins_with("sha256:") and digest.length() == 71 and _contains_only(digest.substr(7), "0123456789abcdef"):
			return {"id": int(id), "size": int(size), "digest": digest.substr(7)}
	return {}


static func _contains_only(value: String, characters: String) -> bool:
	for character in value:
		if not characters.contains(character):
			return false
	return true


static func _redirect_target(headers: PackedStringArray) -> String:
	for header in headers:
		if header.to_lower().begins_with("location:"):
			var url := header.substr(9).strip_edges()
			for prefix in ALLOWED_DOWNLOADS:
				if url.begins_with(prefix) and not ("\r" in url or "\n" in url):
					return url
	return ""


static func _install_message(code: String) -> String:
	match code:
		"INVALID_PACKAGE":
			return "安装程序无法校验更新包，请重新下载。"
		"LAUNCH_FAILED":
			return "新版未能启动，已恢复旧版。"
		"GAME_RUNNING":
			return "游戏进程还在运行。请关闭其他实例后重试。"
		"RESTORE_FAILED":
			return "更新未完成。请检查游戏目录中的旧版备份。"
		_:
			return "无法安装更新。请检查游戏目录写入权限，并关闭其他游戏实例。"
