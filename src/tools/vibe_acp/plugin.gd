@tool
extends EditorPlugin
## Editor entry point for the Vibe ACP plugin.
## All logic lives in src/tools/vibe_acp/; this file only registers the dock.

var _dock: VibeAcpDock = null

func _enter_tree() -> void:
	_dock = VibeAcpDock.new()
	add_control_to_bottom_panel(_dock, "Vibe")

func _exit_tree() -> void:
	if _dock != null:
		_dock.shutdown()
		remove_control_from_bottom_panel(_dock)
		_dock.queue_free()
		_dock = null

func get_plugin_name() -> String:
	return "Vibe ACP"
