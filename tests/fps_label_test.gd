extends GdUnitTestSuite


func test_format_fps_renders_discrete_integer() -> void:
	assert_that(Main.format_fps(59.6)).is_equal("60 FPS")
	assert_that(Main.format_fps(144.4)).is_equal("144 FPS")
	assert_that(Main.format_fps(0.0)).is_equal("0 FPS")


func test_main_scene_has_visible_fps_label_on_canvas_layer() -> void:
	var packed: PackedScene = load("res://src/core/main.tscn")
	assert_that(packed).is_not_null()
	var main: Node = auto_free(packed.instantiate())
	var label: Label = main.get_node_or_null("UI/FPSLabel")
	assert_that(label).is_not_null()
	assert_that(label.get_parent()).is_instanceof(CanvasLayer)
	assert_that(label.visible).is_true()
	assert_that(label.mouse_filter).is_equal(Control.MOUSE_FILTER_IGNORE)


func test_set_fps_display_updates_label_text() -> void:
	var packed: PackedScene = load("res://src/core/main.tscn")
	var main: Node = auto_free(packed.instantiate())
	add_child(main)
	main.call("set_fps_display", 59.6)
	var label: Label = main.get_node("UI/FPSLabel")
	assert_that(label.text).is_equal("60 FPS")


func test_set_fps_display_hides_label_when_disabled() -> void:
	var packed: PackedScene = load("res://src/core/main.tscn")
	var main: Node = auto_free(packed.instantiate())
	add_child(main)
	main.set("show_fps", false)
	main.call("set_fps_display", 60.0)
	var label: Label = main.get_node("UI/FPSLabel")
	assert_that(label.visible).is_false()
