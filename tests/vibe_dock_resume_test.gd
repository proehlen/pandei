extends GdUnitTestSuite
## Startup resume behavior of the dock: with auto-resume off (the default) the
## dock must start a NEW session even when a last session is stored, and it
## must never session/load a session that was left mid-turn. Drives
## VibeAcpDock._decide_resume() with a fake-transport client; the dock UI is
## built without entering the tree so _ready() never spawns a real vibe-acp.

class FakeTransport extends AcpTransport:
	var written: Array = []
	var _open := true

	func open() -> Error:
		return OK

	func is_open() -> bool:
		return _open

	func close() -> void:
		_open = false

	func write_bytes(data: PackedByteArray) -> Error:
		for line in data.get_string_from_utf8().split("\n"):
			if line.strip_edges() != "":
				written.append(JSON.parse_string(line))
		return OK

	func read_available() -> PackedByteArray:
		return PackedByteArray()


func _make_dock() -> Dictionary:
	var dock := VibeAcpDock.new()
	dock._build_ui()  # controls exist, but _ready()/auto-connect never runs
	var t := FakeTransport.new()
	var client := AcpClient.new(AcpConnection.new(t), "/tmp/fake-project")
	dock.client = client
	return {"dock": dock, "transport": t, "client": client}


func test_decide_resume_starts_new_session_by_default() -> void:
	# stored session exists, idle, but auto-resume disabled (the default)
	var f := _make_dock()
	f["dock"]._decide_resume("abc123def456", false, false)
	var sent: Array = f["transport"].written
	assert_that(sent).has_size(1)
	assert_that(sent[0]["method"]).is_equal("session/new")  # NOT session/load
	f["dock"].free()

func test_decide_resume_never_loads_interrupted_session() -> void:
	# even with auto-resume explicitly enabled, a session left mid-turn
	# (editor quit while the agent was working) must not be auto-loaded
	var f := _make_dock()
	f["dock"]._decide_resume("abc123def456", true, true)
	var sent: Array = f["transport"].written
	assert_that(sent).has_size(1)
	assert_that(sent[0]["method"]).is_equal("session/new")
	f["dock"].free()

func test_decide_resume_loads_idle_session_only_when_enabled() -> void:
	var f := _make_dock()
	f["dock"]._decide_resume("abc123def456", false, true)
	var sent: Array = f["transport"].written
	assert_that(sent).has_size(1)
	assert_that(sent[0]["method"]).is_equal("session/load")
	assert_that(sent[0]["params"]["sessionId"]).is_equal("abc123def456")
	assert_that(sent[0]["params"]["mcpServers"]).is_equal([])
	f["dock"].free()

func test_decide_resume_without_stored_session_starts_new() -> void:
	var f := _make_dock()
	f["dock"]._decide_resume("", false, true)
	var sent: Array = f["transport"].written
	assert_that(sent).has_size(1)
	assert_that(sent[0]["method"]).is_equal("session/new")
	f["dock"].free()

func test_decide_resume_without_client_is_noop() -> void:
	var dock := VibeAcpDock.new()
	dock._build_ui()
	dock.client = null
	dock._decide_resume("abc123def456", false, true)  # must not throw
	assert_that(dock.client).is_null()
	dock.free()
