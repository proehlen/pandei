extends GdUnitTestSuite


func test_zero_input_gives_zero_direction() -> void:
	assert_that(Player.input_to_direction(Vector2.ZERO)).is_equal(Vector3.ZERO)
	assert_that(Player.input_to_direction(Vector2.ZERO, PI)).is_equal(Vector3.ZERO)


func test_cardinal_inputs_map_to_world_xz_axes_at_zero_camera_yaw() -> void:
	assert_that(Player.input_to_direction(Vector2(0, -1), 0.0)).is_equal(Vector3(0, 0, -1)) # raw input forward (-Z)
	assert_that(Player.input_to_direction(Vector2(0, 1), 0.0)).is_equal(Vector3(0, 0, 1))
	assert_that(Player.input_to_direction(Vector2(-1, 0), 0.0)).is_equal(Vector3(-1, 0, 0))
	assert_that(Player.input_to_direction(Vector2(1, 0), 0.0)).is_equal(Vector3(1, 0, 0))


func test_cardinal_inputs_are_camera_relative_at_pi_yaw() -> void:
	# The game camera sits behind the player looking along +Z (yaw PI), so W
	# moves further in the camera's view direction and A to the camera's left.
	# Rotating by PI leaves float residue, so compare with a tolerance.
	assert_direction(Player.input_to_direction(Vector2(0, -1), PI), Vector3(0, 0, 1)) # W -> camera forward (+Z)
	assert_direction(Player.input_to_direction(Vector2(0, 1), PI), Vector3(0, 0, -1)) # S -> back toward the camera (-Z)
	assert_direction(Player.input_to_direction(Vector2(-1, 0), PI), Vector3(1, 0, 0)) # A -> camera left (+X)
	assert_direction(Player.input_to_direction(Vector2(1, 0), PI), Vector3(-1, 0, 0)) # D -> camera right (-X)


func assert_direction(actual: Vector3, expected: Vector3) -> void:
	assert_that(absf(actual.x - expected.x) < 0.0001).is_true()
	assert_that(absf(actual.y - expected.y) < 0.0001).is_true()
	assert_that(absf(actual.z - expected.z) < 0.0001).is_true()


func test_player_reads_camera_yaw_from_the_viewport_camera() -> void:
	var packed: PackedScene = load("res://src/core/main.tscn")
	var main: Node = auto_free(packed.instantiate())
	add_child(main)
	main.call("follow_player") # applies the fixed camera rotation now instead of on the next frame
	var player: Player = main.get_node("Player")
	assert_that(absf(absf(player._camera_yaw()) - PI) < 0.001).is_true() # yaw +/-PI: camera behind the player


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
	var camera: Camera3D = main.get_node_or_null("Camera3D")
	assert_that(camera).is_not_null()
	assert_that(camera.current).is_true()


func test_player_scene_has_a_hand_node_with_a_tracked_placeholder_sphere() -> void:
	var packed: PackedScene = load("res://src/entities/player/player.tscn")
	assert_that(packed).is_not_null()
	var player: Player = auto_free(packed.instantiate())
	var hand := player.get_node_or_null("SwingPivot/Hand") as Node3D
	assert_that(hand).is_not_null()
	var pivot := player.get_node_or_null("SwingPivot") as Node3D
	assert_that(pivot).is_not_null()
	assert_that(pivot.position.is_zero_approx()).is_true() # pivot origin at the player's center
	assert_that(hand.get_parent()).is_equal(pivot) # the hand hangs off the pivot
	assert_that(absf(hand.position.y - 0.8) < 0.001).is_true() # half the 1.6 m body height
	assert_that(Vector2(hand.position.x, hand.position.z).length() > 0.4).is_true() # beside the body, outside the 0.4 m capsule radius
	var sphere := hand.get_node_or_null("Placeholder_Hand") as MeshInstance3D
	assert_that(sphere).is_not_null()
	assert_that(sphere.is_in_group("ai_placeholder")).is_true()
	assert_that(sphere.mesh is SphereMesh).is_true() # built-in primitive only
	var material := sphere.get_active_material(0) as StandardMaterial3D
	assert_that(material).is_not_null()


func test_camera_follows_player_position_with_fixed_orientation() -> void:
	var packed: PackedScene = load("res://src/core/main.tscn")
	var main: Node = auto_free(packed.instantiate())
	add_child(main)
	var player: Node = main.get_node("Player")
	var camera: Camera3D = main.get_node("Camera3D")
	player.position = Vector3(3, 0, -2)
	player.rotation.y = 2.0 # facing sideways must not swing the camera
	main.call("follow_player")
	var camera_rotation: Vector3 = main.get("camera_rotation")
	assert_that(camera.global_position).is_equal(Vector3(3, 10.5, -8))
	assert_that(camera.rotation).is_equal(camera_rotation)
	assert_that(camera.rotation.y).is_equal(camera_rotation.y) # fixed yaw, unaffected by player facing


func test_sun_lights_the_camera_facing_side_from_behind_the_camera() -> void:
	var packed: PackedScene = load("res://src/core/main.tscn")
	var main: Node = auto_free(packed.instantiate())
	add_child(main)
	var sun: DirectionalLight3D = main.get_node("Sun")
	var camera: Camera3D = main.get_node("Camera3D")
	var light_dir := sun.global_basis * Vector3(0, 0, -1) # direction the light travels
	var cam_forward := camera.global_basis * Vector3(0, 0, -1)
	assert_that(light_dir.y < 0.0).is_true() # still shines downward
	# Horizontally the light must travel the way the camera looks, so it comes
	# from behind the camera and lights the side of the character the camera sees.
	var light_xz := Vector2(light_dir.x, light_dir.z)
	var cam_xz := Vector2(cam_forward.x, cam_forward.z)
	assert_that(light_xz.dot(cam_xz) > 0.0).is_true()
	var from := -light_dir # direction the light comes from
	assert_that(from.y > 0.0).is_true() # from above
	assert_that(from.z < 0.0).is_true() # from the camera's side (-Z), opposite the player's +Z front


func test_ground_grid_overlays_tracked_checkerboard_placeholder_tiles() -> void:
	var packed: PackedScene = load("res://src/core/main.tscn")
	var main: Node = auto_free(packed.instantiate())
	add_child(main)
	var grid: Node = main.get_node_or_null("Placeholder_GroundGrid")
	assert_that(grid).is_not_null()
	assert_that(grid.is_in_group("ai_placeholder")).is_true()
	var tiles: Array = grid.get_children()
	assert_that(tiles.size()).is_equal(625) # 50x50 ground covered by 2x2 tiles
	var colors := {}
	for tile in tiles:
		var mesh_instance := tile as MeshInstance3D
		assert_that(mesh_instance).is_not_null()
		assert_that(tile.name.begins_with("Placeholder_")).is_true()
		assert_that(tile.is_in_group("ai_placeholder")).is_true()
		assert_that(mesh_instance.mesh is PlaneMesh).is_true()
		assert_that(mesh_instance.position.y > 0.0).is_true() # lifted off the ground plane
		var material := mesh_instance.material_override as StandardMaterial3D
		assert_that(material).is_not_null()
		colors[material.albedo_color] = true
	assert_that(colors.size()).is_equal(2) # checkerboard uses exactly two flat colors
