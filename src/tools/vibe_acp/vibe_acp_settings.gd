class_name VibeAcpSettings
extends RefCounted
## EditorSettings-backed configuration for the Vibe ACP plugin.
## EditorInterface is only touched inside _settings(); auto_detect_executable()
## is pure OS probing so tests can call it headless.

const KEY_EXECUTABLE := "vibe_acp/executable"
const KEY_AUTO_CONNECT := "vibe_acp/auto_connect"
const KEY_LAST_SESSION := "vibe_acp/last_session_id"
const KEY_MODE := "vibe_acp/approval_mode"

static func _settings() -> EditorSettings:
	return EditorInterface.get_editor_settings()

static func get_executable() -> String:
	var s := _settings()
	if s.has_setting(KEY_EXECUTABLE) and str(s.get_setting(KEY_EXECUTABLE)) != "":
		return str(s.get_setting(KEY_EXECUTABLE))
	return auto_detect_executable()

static func set_executable(value: String) -> void:
	_settings().set_setting(KEY_EXECUTABLE, value)

## Probe well-known locations for the vibe-acp binary. Returns "" if absent.
static func auto_detect_executable() -> String:
	var candidates: Array[String] = []
	var home := OS.get_environment("HOME")
	if home != "":
		candidates.append(home + "/.local/bin/vibe-acp")
	for dir in OS.get_environment("PATH").split(":"):
		if dir != "":
			candidates.append(dir + "/vibe-acp")
			candidates.append(dir + "/vibe-acp.exe")
	var userprofile := OS.get_environment("USERPROFILE")  # Windows
	if userprofile != "":
		candidates.append(userprofile + "/.local/bin/vibe-acp.exe")
	for c in candidates:
		if FileAccess.file_exists(c):
			return c
	return ""

static func is_auto_connect() -> bool:
	var s := _settings()
	if s.has_setting(KEY_AUTO_CONNECT):
		return bool(s.get_setting(KEY_AUTO_CONNECT))
	return true

static func set_auto_connect(value: bool) -> void:
	_settings().set_setting(KEY_AUTO_CONNECT, value)

static func get_last_session() -> String:
	var s := _settings()
	if s.has_setting(KEY_LAST_SESSION):
		return str(s.get_setting(KEY_LAST_SESSION))
	return ""

static func set_last_session(value: String) -> void:
	_settings().set_setting(KEY_LAST_SESSION, value)

static func get_mode() -> String:
	var s := _settings()
	if s.has_setting(KEY_MODE):
		return str(s.get_setting(KEY_MODE))
	return ""

static func set_mode(value: String) -> void:
	_settings().set_setting(KEY_MODE, value)
