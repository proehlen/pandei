class_name VibeAcpSettings
extends RefCounted
## EditorSettings-backed configuration for the Vibe ACP plugin.
## EditorInterface is only touched inside _settings(); auto_detect_executable()
## is pure OS probing so tests can call it headless.

const KEY_EXECUTABLE := "vibe_acp/executable"
const KEY_AUTO_CONNECT := "vibe_acp/auto_connect"
const KEY_AUTO_RESUME := "vibe_acp/auto_resume"
const KEY_LAST_SESSION := "vibe_acp/last_session_id"
const KEY_LAST_SESSION_BUSY := "vibe_acp/last_session_busy"
const KEY_MODE := "vibe_acp/approval_mode"

## Null outside the editor (e.g. headless GdUnit runs that instantiate the
## dock); every accessor handles that by returning its default.
static func _settings() -> EditorSettings:
	if not Engine.is_editor_hint():
		return null
	return EditorInterface.get_editor_settings()

static func get_executable() -> String:
	var s := _settings()
	if s != null and s.has_setting(KEY_EXECUTABLE) and str(s.get_setting(KEY_EXECUTABLE)) != "":
		return str(s.get_setting(KEY_EXECUTABLE))
	return auto_detect_executable()

static func set_executable(value: String) -> void:
	var s := _settings()
	if s != null:
		s.set_setting(KEY_EXECUTABLE, value)

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
	if s != null and s.has_setting(KEY_AUTO_CONNECT):
		return bool(s.get_setting(KEY_AUTO_CONNECT))
	return true

static func set_auto_connect(value: bool) -> void:
	var s := _settings()
	if s != null:
		s.set_setting(KEY_AUTO_CONNECT, value)

## Auto-resume of the last session on editor start is OFF by default: quitting
## the editor mid-turn used to make the agent silently "pick up where it left
## off" on the next start. Users who want it can set vibe_acp/auto_resume=true.
static func is_auto_resume() -> bool:
	var s := _settings()
	if s != null and s.has_setting(KEY_AUTO_RESUME):
		return bool(s.get_setting(KEY_AUTO_RESUME))
	return false

static func set_auto_resume(value: bool) -> void:
	var s := _settings()
	if s != null:
		s.set_setting(KEY_AUTO_RESUME, value)

static func get_last_session() -> String:
	var s := _settings()
	if s != null and s.has_setting(KEY_LAST_SESSION):
		return str(s.get_setting(KEY_LAST_SESSION))
	return ""

static func set_last_session(value: String) -> void:
	var s := _settings()
	if s != null:
		s.set_setting(KEY_LAST_SESSION, value)

## True while a prompt for the stored last session was sent but its
## prompt_finished never arrived (the editor or the agent process went away
## mid-turn). Persisted on purpose: if the editor is quit mid-turn, the flag
## is still true on the next start and the session counts as interrupted.
static func get_last_session_busy() -> bool:
	var s := _settings()
	if s != null and s.has_setting(KEY_LAST_SESSION_BUSY):
		return bool(s.get_setting(KEY_LAST_SESSION_BUSY))
	return false

static func set_last_session_busy(value: bool) -> void:
	var s := _settings()
	if s != null:
		s.set_setting(KEY_LAST_SESSION_BUSY, value)

## Whether the stored last session must NOT be auto-resumed. If the busy key
## does not exist yet (first editor start after this feature shipped) we cannot
## prove the session was idle, so we conservatively treat it as interrupted —
## one skipped auto-resume is safe, a wrongly resumed runaway session is not.
static func is_last_session_interrupted() -> bool:
	var s := _settings()
	if s == null:
		return false  # headless (tests): nothing is persisted
	if s.has_setting(KEY_LAST_SESSION_BUSY):
		return bool(s.get_setting(KEY_LAST_SESSION_BUSY))
	return get_last_session() != ""

## Pure resume decision used by the dock on startup; kept free of
## EditorSettings so tests can drive the whole matrix headless.
static func should_auto_resume(last_session: String, interrupted: bool, auto_resume_enabled: bool) -> bool:
	if last_session.is_empty() or not auto_resume_enabled:
		return false
	return not interrupted

static func get_mode() -> String:
	var s := _settings()
	if s != null and s.has_setting(KEY_MODE):
		return str(s.get_setting(KEY_MODE))
	return ""

static func set_mode(value: String) -> void:
	var s := _settings()
	if s != null:
		s.set_setting(KEY_MODE, value)
