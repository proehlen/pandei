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


func test_ease_velocity_moves_toward_target_by_at_most_acceleration_times_delta() -> void:
	var eased := Player.ease_velocity(Vector3.ZERO, Vector3(0, 0, 6), 30.0, 1.0 / 60.0)
	assert_that(absf(eased.z - 0.5) < 0.0001 and absf(eased.x) < 0.0001).is_true() # 30 * 1/60, not full speed
	# a step larger than the remaining distance lands exactly on the target
	assert_that(Player.ease_velocity(Vector3(0, 0, 5.9), Vector3(0, 0, 6), 30.0, 1.0 / 60.0)).is_equal(Vector3(0, 0, 6))
	# easing out uses the same rate back toward zero
	var slowed := Player.ease_velocity(Vector3(0, 0, 6), Vector3.ZERO, 30.0, 1.0 / 60.0)
	assert_that(absf(slowed.z - 5.5) < 0.0001).is_true()


func test_player_eases_in_and_out_of_movement_instead_of_snapping() -> void:
	var player: Player = auto_free(Player.new())
	player.set_physics_process(false) # tests step _physics_process manually
	add_child(player)
	Input.action_press("move_right")
	player._physics_process(1.0 / 60.0)
	var first := Vector3(player.velocity.x, 0.0, player.velocity.z)
	for i in 13:
		player._physics_process(1.0 / 60.0)
	var top := Vector3(player.velocity.x, 0.0, player.velocity.z)
	Input.action_release("move_right")
	player._physics_process(1.0 / 60.0)
	var slowed := Vector3(player.velocity.x, 0.0, player.velocity.z)
	assert_that(absf(first.length() - player.acceleration / 60.0) < 0.0001).is_true() # ease in, not instantly at max
	assert_that(first.length() < player.move_speed).is_true()
	assert_that(absf(top.length() - player.move_speed) < 0.001).is_true() # top speed reached
	assert_that(absf(slowed.length() - (player.move_speed - player.acceleration / 60.0)) < 0.0001).is_true() # ease out, not instantly zero


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


func test_player_scene_has_a_right_hand_node_with_a_tracked_placeholder_sphere() -> void:
	var packed: PackedScene = load("res://src/entities/player/player.tscn")
	assert_that(packed).is_not_null()
	var player: Player = auto_free(packed.instantiate())
	var hand := player.get_node_or_null("SwingPivot/RightHand") as Node3D
	assert_that(hand).is_not_null()
	var pivot := player.get_node_or_null("SwingPivot") as Node3D
	assert_that(pivot).is_not_null()
	assert_that(pivot.position.is_zero_approx()).is_true() # pivot origin at the player's center
	assert_that(hand.get_parent()).is_equal(pivot) # the hand hangs off the pivot
	assert_that(absf(hand.position.y - 0.8) < 0.001).is_true() # half the 1.6 m body height
	var body_shape := player.get_node("CollisionShape3D").shape as CapsuleShape3D
	assert_that(absf(Vector2(hand.position.x, hand.position.z).length() - body_shape.radius) < 0.05).is_true() # collision reaches out to where the hands are
	assert_that(hand.position.x < 0.0).is_true() # on the holder's right: -X when facing +Z
	var sphere := hand.get_node_or_null("Placeholder_RightHand") as MeshInstance3D
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


func test_yaw_toward_matches_the_facing_convention() -> void:
	assert_that(absf(Player.yaw_toward(Vector3.ZERO, Vector3(0, 0, 1)) - 0.0) < 0.0001).is_true() # +Z: yaw 0
	assert_that(absf(Player.yaw_toward(Vector3.ZERO, Vector3(1, 0, 0)) - PI / 2.0) < 0.0001).is_true() # +X: yaw PI/2
	assert_that(absf(absf(Player.yaw_toward(Vector3.ZERO, Vector3(0, 0, -1))) - PI) < 0.0001).is_true() # -Z: +/-PI
	assert_that(absf(Player.yaw_toward(Vector3.ZERO, Vector3(-1, 0, 0)) + PI / 2.0) < 0.0001).is_true() # -X: yaw -PI/2
	# a height difference must not matter: facing is yaw-only on the XZ plane
	assert_that(absf(Player.yaw_toward(Vector3(1, 0, 1), Vector3(1, 5, 4)) - 0.0) < 0.0001).is_true()


func test_yaw_toward_is_nan_when_points_share_xz_position() -> void:
	assert_that(is_nan(Player.yaw_toward(Vector3(2, 0, 3), Vector3(2, 0, 3)))).is_true()
	assert_that(is_nan(Player.yaw_toward(Vector3(2, 0, 3), Vector3(2, 9, 3)))).is_true() # same XZ, different height


func test_ray_crosses_plane_ahead_only_for_rays_that_hit_the_plane_in_front() -> void:
	var origin := Vector3(0, 10, -8)
	assert_that(Player.ray_crosses_plane_ahead(origin, Vector3(0, -1, 0.5), 0.0)).is_true()
	assert_that(Player.ray_crosses_plane_ahead(origin, Vector3(1, 0, 0), 0.0)).is_false() # parallel to the plane
	assert_that(Player.ray_crosses_plane_ahead(origin, Vector3(0, 1, 0), 0.0)).is_false() # pointing away from the plane
	assert_that(Player.ray_crosses_plane_ahead(Vector3(0, -5, 0), Vector3(0, -1, 0), 0.0)).is_false() # plane behind the origin


func test_ray_plane_intersection_lands_on_the_plane() -> void:
	var origin := Vector3(0, 10, -8)
	var point := Player.ray_plane_intersection(origin, Vector3(0, -1, 0.5), 0.0)
	assert_that(absf(point.y - 0.0) < 0.0001).is_true()
	assert_that(absf(point.x - 0.0) < 0.0001).is_true()
	assert_that(absf(point.z - (-3.0)) < 0.0001).is_true() # t = 10: origin.z + 0.5 * 10
	var raised := Player.ray_plane_intersection(origin, Vector3(0.25, -1, 0.0), 2.0)
	assert_that(absf(raised.y - 2.0) < 0.0001).is_true()
	assert_that(absf(raised.x - 2.0) < 0.0001).is_true() # t = 8: 0.25 * 8


func test_face_toward_screen_position_locks_yaw_toward_the_clicked_world_point() -> void:
	var packed: PackedScene = load("res://src/core/main.tscn")
	var main: Node = auto_free(packed.instantiate())
	add_child(main)
	main.call("follow_player") # pins the fixed camera transform now instead of on the next frame
	var player: Player = main.get_node("Player")
	var camera: Camera3D = main.get_node("Camera3D")
	# clicking a world point in front of the player (+Z, its facing at yaw 0)
	var front := player.global_position + Vector3(0, 0, 5)
	player.face_toward_screen_position(camera.unproject_position(front))
	assert_that(absf(player._attack_facing_yaw - 0.0) < 0.001).is_true()
	# clicking behind the player (-Z) locks a 180-degree turn
	var behind := player.global_position + Vector3(0, 0, -5)
	player.face_toward_screen_position(camera.unproject_position(behind))
	assert_that(absf(absf(player._attack_facing_yaw) - PI) < 0.001).is_true()
	# clicking to the player's right (+X) locks yaw PI/2
	var right := player.global_position + Vector3(5, 0, 0)
	player.face_toward_screen_position(camera.unproject_position(right))
	assert_that(absf(player._attack_facing_yaw - PI / 2.0) < 0.001).is_true()


func test_face_toward_screen_position_does_nothing_without_a_camera() -> void:
	var player: Player = auto_free(Player.new())
	add_child(player) # no camera in this viewport
	player._attack_facing_yaw = 0.7
	player.face_toward_screen_position(Vector2(100, 100))
	assert_that(absf(player._attack_facing_yaw - 0.7) < 0.0001).is_true() # lock unchanged


func test_attack_facing_lock_turns_toward_the_click_while_movement_continues() -> void:
	var player: Player = auto_free(Player.new())
	player.set_physics_process(false) # tests step _physics_process manually
	add_child(player)
	Input.action_press("move_right") # travel +X at zero camera yaw; travel facing yaw PI/2
	player._attack_facing_yaw = PI # as if the player clicked behind itself (-Z)
	player._physics_process(1.0 / 60.0)
	var turn := clampf(player.turn_speed / 60.0, 0.0, 1.0)
	assert_that(absf(player.rotation.y - lerp_angle(0.0, PI, turn)) < 0.001).is_true() # turned toward the click...
	assert_that(absf(player.rotation.y - PI / 2.0) > 0.3).is_true() # ...not toward the travel direction
	assert_that(player.velocity.x > 0.0).is_true() # travel unaffected by the lock
	for i in 60:
		player._physics_process(1.0 / 60.0)
	assert_that(absf(angle_difference(player.rotation.y, PI)) < 0.05).is_true() # settled facing the click: a 180-degree turn
	assert_that(absf(player.velocity.x - player.move_speed) < 0.01).is_true() # still moving at full speed
	player.release_attack_facing()
	player._physics_process(1.0 / 60.0)
	assert_that(absf(angle_difference(player.rotation.y, PI / 2.0)) < absf(angle_difference(PI, PI / 2.0))).is_true() # lock released: facing tracks travel again
	Input.action_release("move_right")


func test_attack_facing_lock_applies_while_idle_and_facing_holds_still_after_release() -> void:
	var player: Player = auto_free(Player.new())
	player.set_physics_process(false) # tests step _physics_process manually
	add_child(player)
	player._attack_facing_yaw = PI / 2.0
	player._physics_process(1.0 / 60.0)
	assert_that(player.rotation.y > 0.0).is_true() # turned toward the lock without any movement input
	for i in 60:
		player._physics_process(1.0 / 60.0)
	assert_that(absf(angle_difference(player.rotation.y, PI / 2.0)) < 0.05).is_true()
	player.release_attack_facing()
	var before := player.rotation.y
	player._physics_process(1.0 / 60.0)
	assert_that(player.rotation.y).is_equal(before) # idle without a lock: facing holds still


func test_player_settles_exactly_on_the_facing_target_once_within_one_turn_step() -> void:
	var player: Player = auto_free(Player.new())
	player.set_physics_process(false) # tests step _physics_process manually
	add_child(player)
	player._attack_facing_yaw = 1.0
	for i in 60:
		player._physics_process(1.0 / 60.0)
	assert_that(player.rotation.y).is_equal(1.0) # snapped exactly onto the lock, not just close
	assert_that(player.is_turning_to_attack_target()).is_false()
	Input.action_press("move_right")
	player.release_attack_facing()
	for i in 60:
		player._physics_process(1.0 / 60.0)
	Input.action_release("move_right")
	assert_that(absf(player.rotation.y - PI / 2.0) < 0.0001).is_true() # travel facing settles exactly too


func test_is_turning_to_attack_target_reflects_whether_the_lock_is_set_and_reached() -> void:
	var player: Player = auto_free(Player.new())
	player.set_physics_process(false) # tests step _physics_process manually
	add_child(player)
	assert_that(player.is_turning_to_attack_target()).is_false() # no lock
	player._attack_facing_yaw = PI / 2.0
	assert_that(player.is_turning_to_attack_target()).is_true() # locked, not yet faced
	for i in 60:
		player._physics_process(1.0 / 60.0)
	assert_that(player.is_turning_to_attack_target()).is_false() # turned to face the click
