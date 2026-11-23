extends GdUnitTestSuite


func test_zero_input_gives_zero_direction() -> void:
	assert_that(Player.input_to_direction(Vector2.ZERO)).is_equal(Vector3.ZERO)


func test_cardinal_inputs_map_to_world_xz_axes() -> void:
	assert_that(Player.input_to_direction(Vector2(0, -1))).is_equal(Vector3(0, 0, -1)) # W -> forward (-Z)
	assert_that(Player.input_to_direction(Vector2(0, 1))).is_equal(Vector3(0, 0, 1)) # S -> back (+Z)
	assert_that(Player.input_to_direction(Vector2(-1, 0))).is_equal(Vector3(-1, 0, 0)) # A -> left (-X)
	assert_that(Player.input_to_direction(Vector2(1, 0))).is_equal(Vector3(1, 0, 0)) # D -> right (+X)


func test_diagonal_input_is_normalized_on_the_xz_plane() -> void:
	var dir := Player.input_to_direction(Vector2(1, -1))
	assert_that(dir.y).is_equal(0.0)
	assert_that(absf(dir.length() - 1.0) < 0.0001).is_true()
	assert_that(dir.x > 0.0 and dir.z < 0.0).is_true()


func test_input_to_velocity_scales_by_speed() -> void:
	assert_that(Player.input_to_velocity(Vector2(1, 0), 6.0)).is_equal(Vector3(6.0, 0, 0))
	assert_that(Player.input_to_velocity(Vector2.ZERO, 6.0)).is_equal(Vector3.ZERO)
	var diagonal := Player.input_to_velocity(Vector2(1, 1), 6.0)
	assert_that(absf(diagonal.length() - 6.0) < 0.0001).is_true()


func test_wasd_input_actions_are_registered() -> void:
	var expected := {
		"move_left": KEY_A,
		"move_right": KEY_D,
		"move_up": KEY_W,
		"move_down": KEY_S,
	}
	for action: String in expected:
		assert_that(InputMap.has_action(action)).is_true()
		var keycodes: Array = []
		for event in InputMap.action_get_events(action):
			if event is InputEventKey:
				keycodes.append(event.physical_keycode)
		assert_that(keycodes.has(expected[action])).is_true()


func test_main_scene_scaffolds_ground_player_and_camera() -> void:
	var packed: PackedScene = load("res://src/core/main.tscn")
	assert_that(packed).is_not_null()
	var main: Node = auto_free(packed.instantiate())
	var ground: Node = main.get_node_or_null("Placeholder_Ground")
	assert_that(ground).is_not_null()
	assert_that(ground.is_in_group("ai_placeholder")).is_true()
	assert_that(main.get_node_or_null("Placeholder_Ground/Placeholder_GroundMesh")).is_not_null()
	var player: Node = main.get_node_or_null("Player")
	assert_that(player).is_not_null()
	var body: Node = player.get_node_or_null("Placeholder_Body")
	assert_that(body).is_not_null()
	assert_that(body.is_in_group("ai_placeholder")).is_true()
	var camera: Camera3D = player.get_node_or_null("Camera3D")
	assert_that(camera).is_not_null()
	assert_that(camera.current).is_true()
