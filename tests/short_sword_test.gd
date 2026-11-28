extends GdUnitTestSuite


func test_bob_offset_is_zero_at_time_zero() -> void:
	assert_that(ShortSword.bob_offset(0.0, 0.25, 2.0)).is_equal(0.0)


func test_bob_offset_reaches_amplitude_at_quarter_period() -> void:
	var amplitude := 0.25
	var speed := 2.0
	assert_that(absf(ShortSword.bob_offset(PI / (2.0 * speed), amplitude, speed) - amplitude) < 0.0001).is_true()
	assert_that(absf(ShortSword.bob_offset(-PI / (2.0 * speed), amplitude, speed) + amplitude) < 0.0001).is_true()


func test_bob_offset_never_exceeds_amplitude() -> void:
	var amplitude := 0.25
	var speed := 2.0
	for t in [0.1, 0.7, 1.3, 2.9, 5.0, 11.0]:
		assert_that(absf(ShortSword.bob_offset(t, amplitude, speed)) <= amplitude + 0.0001).is_true()


func test_short_sword_scene_has_tracked_placeholder_parts_under_a_pivot() -> void:
	var packed: PackedScene = load("res://src/entities/weapon/short_sword.tscn")
	assert_that(packed).is_not_null()
	var sword: ShortSword = auto_free(packed.instantiate())
	var pivot: Node = sword.get_node_or_null("Placeholder_SwordPivot")
	assert_that(pivot).is_not_null()
	assert_that(pivot.is_in_group("ai_placeholder")).is_true()
	for part_name in ["Placeholder_Blade", "Placeholder_Guard", "Placeholder_Handle"]:
		var part: Node = pivot.get_node_or_null(part_name)
		assert_that(part).is_not_null()
		assert_that(part.is_in_group("ai_placeholder")).is_true()
		assert_that(part is MeshInstance3D).is_true()
		var mesh := (part as MeshInstance3D).mesh
		assert_that(mesh is BoxMesh or mesh is CylinderMesh).is_true() # built-in primitives only
		var material := (part as MeshInstance3D).get_active_material(0) as StandardMaterial3D
		assert_that(material).is_not_null()
	# the blade's own rotation stays identity; pose changes live in code, not the scene
	var blade := pivot.get_node("Placeholder_Blade") as Node3D
	assert_that(blade.rotation.is_zero_approx()).is_true()
	var handle := pivot.get_node("Placeholder_Handle") as Node3D
	assert_that(absf(handle.rotation.z - PI / 2.0) < 0.001).is_true() # handle lies along the blade


func test_loot_basis_stands_blade_upright_with_slight_diagonal_lean() -> void:
	var blade_dir := (ShortSword.loot_basis(0.4) * Vector3.RIGHT).normalized()
	assert_that(blade_dir.y > 0.9).is_true() # blade points mostly straight up
	assert_that(absf(blade_dir.y - cos(0.4)) < 0.001).is_true()
	assert_that(absf(Vector2(blade_dir.x, blade_dir.z).length() - sin(0.4)) < 0.001).is_true() # leaning by exactly the tilt


func test_loot_basis_rolls_blade_so_its_edge_runs_horizontally() -> void:
	var thin_axis := (ShortSword.loot_basis(0.4) * Vector3.UP).normalized() # blade's thin dimension
	assert_that(absf(thin_axis.y) < 0.001).is_true() # no vertical component: edge horizontal


func test_equipped_basis_points_blade_up_and_forward_without_roll() -> void:
	var basis := ShortSword.equipped_basis(0.35)
	var blade_dir := (basis * Vector3.RIGHT).normalized()
	assert_that(blade_dir.y > 0.9).is_true() # blade up in the hand
	assert_that(blade_dir.z > 0.0).is_true() # leaning toward the holder's facing direction
	var thin_axis := (basis * Vector3.UP).normalized()
	assert_that(absf(thin_axis.y) < 0.001).is_true() # edge horizontal, blade not twisted


func test_spin_around_vertical_keeps_constant_lean() -> void:
	for spin in [0.0, 1.0, 2.5, 4.0, 5.9]:
		var blade_dir := (Basis(Vector3.UP, spin) * ShortSword.loot_basis(0.4) * Vector3.RIGHT).normalized()
		assert_that(absf(blade_dir.y - cos(0.4)) < 0.001).is_true()
		assert_that(absf(Vector2(blade_dir.x, blade_dir.z).length() - sin(0.4)) < 0.001).is_true()


func test_ready_pins_sword_to_hover_height() -> void:
	var sword: ShortSword = auto_free(ShortSword.new())
	add_child(sword) # triggers _ready
	assert_that(absf(sword.position.y - sword.hover_height) < 0.0001).is_true()
	assert_that(sword.position.y > 0.5).is_true() # floating above the ground, not resting on it


func test_ready_applies_loot_pose_to_pivot() -> void:
	var packed: PackedScene = load("res://src/entities/weapon/short_sword.tscn")
	var sword: ShortSword = auto_free(packed.instantiate())
	add_child(sword) # triggers _ready
	var pivot := sword.get_node("Placeholder_SwordPivot") as Node3D
	var blade_dir := (pivot.transform.basis * Vector3.RIGHT).normalized()
	assert_that(blade_dir.y > 0.9).is_true() # standing upright, not lying flat
	assert_that(absf(blade_dir.y - cos(sword.tilt_angle)) < 0.001).is_true()


func test_process_advances_bob_phase_consistently() -> void:
	var sword: ShortSword = auto_free(ShortSword.new())
	sword.set_process(false) # tests step _process manually
	add_child(sword)
	sword._process(0.5)
	var expected := sword.hover_height + ShortSword.bob_offset(0.5, sword.bob_amplitude, sword.bob_speed)
	assert_that(absf(sword.position.y - expected) < 0.0001).is_true()
	sword._process(0.25)
	expected = sword.hover_height + ShortSword.bob_offset(0.75, sword.bob_amplitude, sword.bob_speed)
	assert_that(absf(sword.position.y - expected) < 0.0001).is_true()


func test_sword_bobs_up_and_down_within_amplitude_over_a_full_period() -> void:
	var sword: ShortSword = auto_free(ShortSword.new())
	sword.set_process(false) # tests step _process manually
	add_child(sword)
	var min_y := sword.position.y
	var max_y := sword.position.y
	var period := TAU / sword.bob_speed
	var steps := 240
	for i in steps: # a bit more than one full bobbing period
		sword._process(period / steps)
		min_y = minf(min_y, sword.position.y)
		max_y = maxf(max_y, sword.position.y)
	assert_that(max_y > sword.hover_height).is_true() # bobs above the hover height...
	assert_that(min_y < sword.hover_height).is_true() # ...and below it
	assert_that(max_y - sword.hover_height <= sword.bob_amplitude + 0.0001).is_true()
	assert_that(sword.hover_height - min_y <= sword.bob_amplitude + 0.0001).is_true()


func test_process_spins_sword_slowly_around_vertical_keeping_lean() -> void:
	var sword: ShortSword = auto_free(ShortSword.new())
	sword.set_process(false) # tests step _process manually
	add_child(sword)
	var directions := {}
	var period := TAU / sword.spin_speed
	var steps := 120
	for i in steps: # one full revolution
		sword._process(period / steps)
		assert_that(absf(sword.rotation.y - sword._spin_time * sword.spin_speed) < 0.0001).is_true()
		var blade := (sword.transform.basis * ShortSword.loot_basis(sword.tilt_angle) * Vector3.RIGHT).normalized()
		assert_that(absf(blade.y - cos(sword.tilt_angle)) < 0.001).is_true() # constant lean off vertical
		directions[blade] = true
	assert_that(directions.size() > steps / 2.0).is_true() # actually spinning, not static


func test_is_within_pickup_boundary() -> void:
	var sword_pos := Vector3(3, 1.2, 2)
	assert_that(ShortSword.is_within_pickup(sword_pos, sword_pos, 0.0)).is_true()
	assert_that(ShortSword.is_within_pickup(sword_pos, Vector3(3, 0, 2), 1.5)).is_true() # 1.2 m directly below
	assert_that(ShortSword.is_within_pickup(sword_pos, Vector3(3, 0, 2), 1.1)).is_false()
	assert_that(ShortSword.is_within_pickup(sword_pos, Vector3(4, 1.2, 2), 1.0)).is_true() # exactly at radius
	assert_that(ShortSword.is_within_pickup(sword_pos, Vector3(4.1, 1.2, 2), 1.0)).is_false()


func test_player_walking_over_sword_picks_it_up_and_equips_it() -> void:
	var player_packed: PackedScene = load("res://src/entities/player/player.tscn")
	var player: Player = auto_free(player_packed.instantiate())
	player.add_to_group("player")
	add_child(player)
	var packed: PackedScene = load("res://src/entities/weapon/short_sword.tscn")
	var sword: ShortSword = auto_free(packed.instantiate())
	sword.set_physics_process(false) # tests step _physics_process manually
	sword.set_process(false)
	add_child(sword)
	sword.global_position = Vector3(3, 1.2, 2)
	player.global_position = Vector3(20, 0, 15) # far away: no pickup
	sword._physics_process(1.0 / 60.0)
	assert_that(sword.equipped).is_false()
	assert_that(sword.get_parent()).is_not_equal(player)
	player.global_position = Vector3(3, 0, 2.5) # walked over the sword: 1.3 m away, within the 1.5 m radius
	sword._physics_process(1.0 / 60.0)
	var hand := player.get_node("SwingPivot/RightHand") as Node3D
	assert_that(sword.equipped).is_true()
	assert_that(sword.holder).is_equal(player)
	assert_that(sword.get_parent()).is_equal(hand) # attached to the hand, not the body
	assert_that(sword.transform.is_equal_approx(Transform3D.IDENTITY)).is_true() # hilt sits at the hand origin


func test_equipped_sword_sits_at_hand_height_beside_holder_with_blade_up_and_forward() -> void:
	var player_packed: PackedScene = load("res://src/entities/player/player.tscn")
	var player: Player = auto_free(player_packed.instantiate())
	player.add_to_group("player")
	add_child(player)
	var packed: PackedScene = load("res://src/entities/weapon/short_sword.tscn")
	var sword: ShortSword = auto_free(packed.instantiate())
	sword.set_process(false)
	sword.set_physics_process(false)
	add_child(sword)
	sword.equip(player)
	# the hand carries the attach point and the grip pose; the sword hangs off it untouched
	var hand := player.get_node("SwingPivot/RightHand") as Node3D
	assert_that(sword.get_parent()).is_equal(hand)
	assert_that(sword.transform.is_equal_approx(Transform3D.IDENTITY)).is_true()
	assert_that(hand.basis.is_equal_approx(ShortSword.equipped_basis(sword.equipped_lean))).is_true()
	var pivot := sword.get_node("Placeholder_SwordPivot") as Node3D
	assert_that(pivot.basis.is_equal_approx(Basis.IDENTITY)).is_true() # the sword pivot no longer takes the grip pose
	# hilt (hand origin) at hand height beside the body, at the edge of the collision capsule
	var grip := hand.position
	assert_that(absf(grip.y - 0.8) < 0.001).is_true() # hand at half the body height
	var body_shape := player.get_node("CollisionShape3D").shape as CapsuleShape3D
	assert_that(Vector2(grip.x, grip.z).length() >= body_shape.radius - 0.05).is_true() # at the collision edge, where the hands are
	# blade points up and leans toward the holder's facing direction (+Z), edge horizontal
	var blade_node := sword.get_node("Placeholder_SwordPivot/Placeholder_Blade") as Node3D
	var blade := (blade_node.global_transform.basis * Vector3.RIGHT).normalized()
	assert_that(blade.y > 0.9).is_true()
	assert_that(blade.z > 0.0).is_true()
	var thin_axis := (blade_node.global_transform.basis * Vector3.UP).normalized()
	assert_that(absf(thin_axis.y) < 0.001).is_true() # no roll about the blade's long axis in the hand
	# bobbing and spinning stop once equipped
	var pos_before := sword.position
	var basis_before := sword.transform.basis
	sword._process(0.5)
	assert_that(sword.position).is_equal(pos_before)
	assert_that(sword.transform.basis).is_equal(basis_before)


func test_main_scene_places_short_sword_a_short_distance_from_floating_player() -> void:
	var packed: PackedScene = load("res://src/core/main.tscn")
	var main: Node = auto_free(packed.instantiate())
	add_child(main) # triggers _ready on the sword, pinning its hover height
	var player: Node = main.get_node_or_null("Player")
	var sword: Node = main.get_node_or_null("ShortSword")
	assert_that(player).is_not_null()
	assert_that(sword).is_not_null()
	assert_that(sword is ShortSword).is_true()
	var distance := (player as Node3D).global_position.distance_to((sword as Node3D).global_position)
	assert_that(distance > 1.0 and distance < 8.0).is_true() # a short distance away, not on top of the player
	assert_that(absf(sword.position.y - (sword as ShortSword).hover_height) < 0.0001).is_true() # floating in the air
	var blade_node := sword.get_node("Placeholder_SwordPivot/Placeholder_Blade") as Node3D
	var blade_dir := (blade_node.global_transform.basis * Vector3.RIGHT).normalized()
	assert_that(blade_dir.y > 0.9).is_true() # standing upright with a slight diagonal lean


func test_hand_pose_basis_yaws_180_while_swinging_and_grip_pose_otherwise() -> void:
	# while swinging the blade must lie flat and point outward from the right
	# hand (-X), i.e. the design-time pose yawed 180 degrees about vertical
	assert_that(ShortSword.hand_pose_basis(true, 0.35).is_equal_approx(Basis(Vector3.UP, PI))).is_true()
	assert_that(ShortSword.hand_pose_basis(false, 0.35).is_equal_approx(ShortSword.equipped_basis(0.35))).is_true()


func test_ease_smoothstep_is_s_shaped_and_clamped() -> void:
	assert_that(ShortSword.ease_smoothstep(0.0)).is_equal(0.0)
	assert_that(ShortSword.ease_smoothstep(1.0)).is_equal(1.0)
	assert_that(ShortSword.ease_smoothstep(-0.5)).is_equal(0.0) # clamped below
	assert_that(ShortSword.ease_smoothstep(1.5)).is_equal(1.0) # clamped above
	assert_that(ShortSword.ease_smoothstep(0.5)).is_equal(0.5) # symmetric midpoint
	assert_that(ShortSword.ease_smoothstep(0.25) < 0.25).is_true() # eases in: below linear early on
	assert_that(ShortSword.ease_smoothstep(0.75) > 0.75).is_true() # eases out: above linear late


func test_swing_angle_at_eases_in_and_out_and_clamps_to_full_angle() -> void:
	var total := deg_to_rad(160.0)
	var duration := 0.35 / 1.2
	assert_that(ShortSword.swing_angle_at(0.0, duration, total)).is_equal(0.0)
	assert_that(absf(ShortSword.swing_angle_at(duration / 2.0, duration, total) - total / 2.0) < 0.0001).is_true() # midpoint unchanged by easing
	assert_that(ShortSword.swing_angle_at(duration / 4.0, duration, total) < total / 4.0).is_true() # eases in
	assert_that(ShortSword.swing_angle_at(3.0 * duration / 4.0, duration, total) > 3.0 * total / 4.0).is_true() # eases out
	assert_that(absf(ShortSword.swing_angle_at(duration, duration, total) - total) < 0.0001).is_true()
	assert_that(absf(ShortSword.swing_angle_at(2.0, duration, total) - total) < 0.0001).is_true() # clamped once the swing is over
	assert_that(ShortSword.swing_angle_at(0.1, 0.0, total)).is_equal(total) # zero duration: instant


func test_left_click_press_starts_a_swing_only_when_equipped() -> void:
	var packed: PackedScene = load("res://src/entities/weapon/short_sword.tscn")
	var sword: ShortSword = auto_free(packed.instantiate())
	sword.set_process(false)
	sword.set_physics_process(false)
	add_child(sword)
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	sword._unhandled_input(click)
	assert_that(sword._swing_time < 0.0).is_true() # not equipped: no swing
	var player_packed: PackedScene = load("res://src/entities/player/player.tscn")
	var player: Player = auto_free(player_packed.instantiate())
	player.add_to_group("player")
	add_child(player)
	sword.equip(player)
	sword._unhandled_input(click)
	assert_that(sword._swing_time >= 0.0).is_true() # equipped: press starts the swing
	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_LEFT
	release.pressed = false
	sword._swing_time = 0.2
	sword._unhandled_input(release)
	assert_that(sword._swing_time).is_equal(0.2) # a release neither starts nor stops a swing


func test_swing_resets_hand_and_orbits_it_around_the_player_then_returns_to_rest() -> void:
	var player_packed: PackedScene = load("res://src/entities/player/player.tscn")
	var player: Player = auto_free(player_packed.instantiate())
	player.add_to_group("player")
	add_child(player)
	var packed: PackedScene = load("res://src/entities/weapon/short_sword.tscn")
	var sword: ShortSword = auto_free(packed.instantiate())
	sword.set_process(false)
	sword.set_physics_process(false)
	add_child(sword)
	sword.equip(player)
	var hand := player.get_node("SwingPivot/RightHand") as Node3D
	var pivot := player.get_node("SwingPivot") as Node3D
	var blade_node := sword.get_node("Placeholder_SwordPivot/Placeholder_Blade") as Node3D
	assert_that(hand.basis.is_equal_approx(ShortSword.equipped_basis(sword.equipped_lean))).is_true()
	sword.start_swing()
	assert_that(sword._swing_time).is_equal(0.0)
	sword._process(0.0) # swing start: hand yawed 180 (blade outward), pivot still at zero
	assert_that(hand.basis.is_equal_approx(Basis(Vector3.UP, PI))).is_true()
	assert_that(pivot.rotation.y).is_equal(0.0)
	var distance := hand.global_position.distance_to(player.global_position)
	var pos_start := hand.global_position
	sword._process(sword.swing_duration / 2.0) # halfway through the swing
	assert_that(absf(pivot.rotation.y - sword.swing_angle / 2.0) < 0.0001).is_true() # pivot swept half the angle, positive sign sweeps the right hand (-X) to the front
	assert_that(hand.global_position.z > 0.0).is_true() # halfway the hand is in front of the holder's facing direction (+Z at rest)
	assert_that(hand.basis.is_equal_approx(Basis(Vector3.UP, PI))).is_true() # hand stays yawed 180 for the whole swing
	assert_that(sword.transform.is_equal_approx(Transform3D.IDENTITY)).is_true() # the sword itself is untouched
	assert_that(absf(hand.global_position.distance_to(player.global_position) - distance) < 0.0001).is_true() # constant distance from the player's center
	assert_that(hand.global_position.is_equal_approx(pos_start)).is_false() # but it did move around the player
	var blade_held := (blade_node.global_transform.basis * Vector3.RIGHT).normalized()
	assert_that(absf(blade_held.y) < 0.001).is_true() # blade lies flat during the swing
	assert_that(blade_held.z > 0.5).is_true() # and points forward, not backward: the slash reads as an arc in front
	sword._process(sword.swing_duration / 2.0 + 0.01) # finish the swing
	assert_that(sword._swing_time < 0.0).is_true()
	assert_that(pivot.rotation.is_zero_approx()).is_true() # pivot back to rest
	assert_that(hand.basis.is_equal_approx(ShortSword.equipped_basis(sword.equipped_lean))).is_true() # grip pose restored
	var blade := (blade_node.global_transform.basis * Vector3.RIGHT).normalized()
	assert_that(blade.y > 0.9).is_true() # blade up again at rest


func test_update_hand_pose_does_nothing_before_equip() -> void:
	var sword: ShortSword = auto_free(ShortSword.new())
	sword.set_process(false)
	add_child(sword)
	sword._update_hand_pose(true) # no holder yet: must not crash
	assert_that(sword.equipped).is_false()


func test_main_scene_player_walks_over_sword_and_equips_it() -> void:
	var packed: PackedScene = load("res://src/core/main.tscn")
	var main: Node = auto_free(packed.instantiate())
	add_child(main)
	var player: Node = main.get_node("Player")
	var sword: Node = main.get_node("ShortSword")
	await get_tree().physics_frame
	assert_that((sword as ShortSword).equipped).is_false() # starts on the map, out of reach
	player.global_position = (sword as Node3D).global_position # walk onto the sword
	await get_tree().physics_frame
	await get_tree().physics_frame
	var sword_body := sword as ShortSword
	assert_that(sword_body.equipped).is_true()
	assert_that(sword_body.get_parent()).is_equal(player.get_node("SwingPivot/RightHand")) # equipped on the hand
	var blade_node := sword_body.get_node("Placeholder_SwordPivot/Placeholder_Blade") as Node3D
	var blade := (blade_node.global_transform.basis * Vector3.RIGHT).normalized()
	assert_that(blade.y > 0.9).is_true() # equipped blade points up, ready for combat
	var thin_axis := (blade_node.global_transform.basis * Vector3.UP).normalized()
	assert_that(absf(thin_axis.y) < 0.01).is_true() # edge horizontal in the hand, not twisted


func test_start_swing_returns_whether_a_swing_started() -> void:
	var sword: ShortSword = auto_free(ShortSword.new())
	add_child(sword)
	assert_that(sword.start_swing()).is_false() # not equipped: no swing
	var player_packed: PackedScene = load("res://src/entities/player/player.tscn")
	var player: Player = auto_free(player_packed.instantiate())
	player.add_to_group("player")
	add_child(player)
	sword.equip(player)
	assert_that(sword.start_swing()).is_true() # equipped with a SwingPivot: swing starts
	assert_that(sword._swing_time).is_equal(0.0)


func test_start_swing_alone_leaves_the_holders_facing_free() -> void:
	# only a click aims; a programmatic swing must not change facing
	var player_packed: PackedScene = load("res://src/entities/player/player.tscn")
	var player: Player = auto_free(player_packed.instantiate())
	player.add_to_group("player")
	add_child(player)
	var packed: PackedScene = load("res://src/entities/weapon/short_sword.tscn")
	var sword: ShortSword = auto_free(packed.instantiate())
	sword.set_process(false)
	sword.set_physics_process(false)
	add_child(sword)
	sword.equip(player)
	sword.start_swing()
	assert_that(sword._swing_time >= 0.0).is_true()
	assert_that(is_nan(player._attack_facing_yaw)).is_true() # no click: no facing lock


func test_left_click_without_an_equipped_sword_neither_swings_nor_changes_facing() -> void:
	var player_packed: PackedScene = load("res://src/entities/player/player.tscn")
	var player: Player = auto_free(player_packed.instantiate())
	player.add_to_group("player")
	add_child(player)
	var packed: PackedScene = load("res://src/entities/weapon/short_sword.tscn")
	var sword: ShortSword = auto_free(packed.instantiate())
	sword.set_process(false)
	sword.set_physics_process(false)
	add_child(sword)
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	click.position = Vector2(100, 100)
	sword._unhandled_input(click)
	assert_that(sword._swing_time < 0.0).is_true() # not equipped: no swing
	assert_that(is_nan(player._attack_facing_yaw)).is_true() # and no facing lock


func test_left_click_aims_then_defers_the_swing_until_the_holder_faces_the_click_and_releases_the_lock_at_swing_end() -> void:
	var packed: PackedScene = load("res://src/core/main.tscn")
	var main: Node = auto_free(packed.instantiate())
	add_child(main)
	main.call("follow_player") # pins the fixed camera transform now
	var player: Player = main.get_node("Player")
	player.set_physics_process(false) # tests step the turn manually
	var camera: Camera3D = main.get_node("Camera3D")
	var sword: ShortSword = main.get_node("ShortSword")
	sword.set_process(false) # tests step _process manually
	sword.set_physics_process(false)
	sword.equip(player)
	# click a world point behind the player (-Z): a 180-degree turn
	var behind := player.global_position + Vector3(0, 0, -5)
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	click.position = camera.unproject_position(behind)
	sword._unhandled_input(click)
	assert_that(absf(absf(player._attack_facing_yaw) - PI) < 0.001).is_true() # locks facing onto the clicked point
	assert_that(sword._swing_pending).is_true() # but the swing waits for the turn...
	assert_that(sword._swing_time < 0.0).is_true() # ...it has not started yet
	sword._process(0.1)
	assert_that(sword._swing_time < 0.0).is_true() # still turning: still no swing
	for i in 60:
		player._physics_process(1.0 / 60.0) # finish the 180-degree turn
	assert_that(player.is_turning_to_attack_target()).is_false()
	sword._process(0.0)
	assert_that(sword._swing_pending).is_false()
	assert_that(sword._swing_time).is_equal(0.0) # the swing starts in the settled facing
	sword._process(sword.swing_duration / 2.0)
	assert_that(is_nan(player._attack_facing_yaw)).is_false() # the lock is held mid-swing
	sword._process(sword.swing_duration / 2.0 + 0.01)
	assert_that(sword._swing_time < 0.0).is_true() # swing over
	assert_that(is_nan(player._attack_facing_yaw)).is_true() # lock released once the swing is over


func test_swing_arc_in_world_space_is_the_full_arc_whether_the_click_is_behind_left_or_behind_right() -> void:
	var packed: PackedScene = load("res://src/core/main.tscn")
	var main: Node = auto_free(packed.instantiate())
	add_child(main)
	main.call("follow_player")
	var player: Player = main.get_node("Player")
	player.set_physics_process(false) # tests step the turn manually
	var sword: ShortSword = main.get_node("ShortSword")
	sword.set_process(false) # tests step _process manually
	sword.set_physics_process(false)
	sword.equip(player)
	var hand := player.get_node("SwingPivot/RightHand") as Node3D
	var pivot := player.get_node("SwingPivot") as Node3D
	var dt := 1.0 / 60.0
	for lock_yaw in [3.0 * PI / 4.0, -3.0 * PI / 4.0]: # behind-left and behind-right of the +Z travel facing
		player.rotation.y = 0.0
		player._attack_facing_yaw = lock_yaw
		sword._swing_pending = false
		sword._swing_time = -1.0
		pivot.rotation = Vector3.ZERO
		assert_that(sword.start_swing()).is_true()
		assert_that(sword._swing_pending).is_true() # the swing waits for the turn
		# interleave physics (turn) and process (swing) like the real frame loop
		var samples: Array = []
		for i in 120: # 2 s: enough for the turn plus the swing
			player._physics_process(dt)
			sword._process(dt)
			if sword._swing_time >= 0.0:
				samples.append(Player.yaw_toward(player.global_position, hand.global_position))
		assert_that(samples.size() > 5).is_true() # the swing did play
		var swept := absf(angle_difference(samples[0], samples[samples.size() - 1]))
		assert_that(absf(swept - sword.swing_angle) < 0.1).is_true() # the full arc plays out in world space on both sides
		assert_that(is_nan(player._attack_facing_yaw)).is_true() # lock released at swing end


func test_short_sword_scene_root_is_in_the_weapon_group_so_enemies_can_detect_it() -> void:
	var packed: PackedScene = load("res://src/entities/weapon/short_sword.tscn")
	var sword: ShortSword = auto_free(packed.instantiate())
	assert_that(sword.is_in_group("weapon")).is_true()


func test_enemy_walking_over_sword_picks_it_up_and_equips_it_in_its_right_hand() -> void:
	var enemy_packed: PackedScene = load("res://src/entities/enemy/enemy.tscn")
	var enemy: Enemy = auto_free(enemy_packed.instantiate())
	enemy.set_physics_process(false) # stationary test double
	add_child(enemy) # the scene root is in the "enemy" group
	assert_that(enemy.is_in_group("enemy")).is_true()
	var packed: PackedScene = load("res://src/entities/weapon/short_sword.tscn")
	var sword: ShortSword = auto_free(packed.instantiate())
	sword.set_physics_process(false) # tests step _physics_process manually
	sword.set_process(false)
	add_child(sword)
	sword.global_position = Vector3(5, 1.2, 4)
	enemy.global_position = Vector3(20, 0, 15) # far away: no pickup
	sword._physics_process(1.0 / 60.0)
	assert_that(sword.equipped).is_false()
	assert_that(sword.get_parent()).is_not_equal(enemy.get_node("SwingPivot/RightHand"))
	enemy.global_position = Vector3(5, 0, 4.5) # walked over the sword: 1.3 m away, within the 1.5 m radius
	sword._physics_process(1.0 / 60.0)
	var hand := enemy.get_node("SwingPivot/RightHand") as Node3D
	assert_that(sword.equipped).is_true()
	assert_that(sword.holder).is_equal(enemy)
	assert_that(sword.get_parent()).is_equal(hand) # attached to the enemy's hand, like the player's
	assert_that(sword.transform.is_equal_approx(Transform3D.IDENTITY)).is_true() # hilt sits exactly at the hand
	assert_that(hand.basis.is_equal_approx(ShortSword.equipped_basis(sword.equipped_lean))).is_true() # grip pose carried by the hand


func test_nearest_holder_picks_up_the_sword_when_player_and_enemy_are_both_near() -> void:
	var player_packed: PackedScene = load("res://src/entities/player/player.tscn")
	var player: Player = auto_free(player_packed.instantiate())
	player.add_to_group("player")
	player.set_physics_process(false)
	add_child(player)
	var enemy_packed: PackedScene = load("res://src/entities/enemy/enemy.tscn")
	var enemy: Enemy = auto_free(enemy_packed.instantiate())
	enemy.set_physics_process(false)
	add_child(enemy)
	var packed: PackedScene = load("res://src/entities/weapon/short_sword.tscn")
	var sword: ShortSword = auto_free(packed.instantiate())
	sword.set_physics_process(false) # tests step _physics_process manually
	sword.set_process(false)
	add_child(sword)
	sword.global_position = Vector3(0, 1.2, 0)
	player.global_position = Vector3(0.5, 0, 0) # 1.3 m from the sword: within pickup radius
	enemy.global_position = Vector3.ZERO # 1.2 m: nearer than the player
	assert_that(sword.find_nearest_holder()).is_equal(enemy)
	sword._physics_process(1.0 / 60.0)
	assert_that(sword.equipped).is_true()
	assert_that(sword.holder).is_equal(enemy) # the nearer enemy wins
	# and the other way around: with the player nearer, the player picks it up
	var sword2: ShortSword = auto_free(packed.instantiate())
	sword2.set_physics_process(false)
	sword2.set_process(false)
	add_child(sword2)
	sword2.global_position = Vector3(10, 1.2, 0)
	player.global_position = Vector3(10, 0, 0) # 1.2 m from sword2
	enemy.global_position = Vector3(10.5, 0, 0) # 1.3 m from sword2
	assert_that(sword2.find_nearest_holder()).is_equal(player)
	sword2._physics_process(1.0 / 60.0)
	assert_that(sword2.equipped).is_true()
	assert_that(sword2.holder).is_equal(player)


func test_left_click_does_not_swing_an_enemy_held_sword() -> void:
	var enemy_packed: PackedScene = load("res://src/entities/enemy/enemy.tscn")
	var enemy: Enemy = auto_free(enemy_packed.instantiate())
	enemy.set_physics_process(false)
	add_child(enemy)
	var packed: PackedScene = load("res://src/entities/weapon/short_sword.tscn")
	var sword: ShortSword = auto_free(packed.instantiate())
	sword.set_process(false)
	sword.set_physics_process(false)
	add_child(sword)
	sword.equip(enemy)
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	click.position = Vector2(100, 100)
	sword._unhandled_input(click)
	assert_that(sword._swing_time < 0.0).is_true() # enemy-held: clicks do not swing it


func test_main_scene_places_a_second_sword_near_but_off_the_enemys_path_to_the_player() -> void:
	var packed: PackedScene = load("res://src/core/main.tscn")
	var main: Node = auto_free(packed.instantiate())
	add_child(main) # triggers _ready on the swords, pinning their hover height
	var player: Node = main.get_node_or_null("Player")
	var enemy: Node = main.get_node_or_null("Enemy")
	var sword: Node = main.get_node_or_null("ShortSword")
	var sword2: Node = main.get_node_or_null("ShortSword2")
	assert_that(player).is_not_null()
	assert_that(enemy).is_not_null()
	assert_that(sword).is_not_null()
	assert_that(sword2).is_not_null()
	assert_that(sword.is_in_group("weapon")).is_true()
	assert_that(sword2.is_in_group("weapon")).is_true()
	var enemy_pos := (enemy as Node3D).global_position
	var player_pos := (player as Node3D).global_position
	var dist_first := (sword as Node3D).global_position.distance_to(enemy_pos)
	var dist_second := (sword2 as Node3D).global_position.distance_to(enemy_pos)
	assert_that(dist_second < dist_first).is_true() # the second sword is the enemy's closest weapon
	assert_that(dist_second <= (enemy as Enemy).detection_radius).is_true() # close enough for the enemy to detect it
	assert_that(dist_second > (sword2 as ShortSword).pickup_radius).is_true() # but not grabbed instantly at spawn
	var to_second := (sword2 as Node3D).global_position - enemy_pos
	var to_player := player_pos - enemy_pos
	var cos_angle := to_second.dot(to_player) / (to_second.length() * to_player.length())
	assert_that(absf(cos_angle) < 0.3).is_true() # off the enemy->player line: at spawn the enemy first moves sideways, visibly
	assert_that((sword2 as Node3D).global_position.distance_to(player_pos) > (enemy as Enemy).detection_radius).is_true() # arming there does not trigger a player chase at spawn
	assert_that((sword as Node3D).global_position.distance_to(player_pos) > (sword as ShortSword).pickup_radius).is_true()
	assert_that((sword2 as Node3D).global_position.distance_to(player_pos) > (sword2 as ShortSword).pickup_radius).is_true() # neither is grabbed at spawn


func test_main_scene_enemy_walks_sideways_to_the_second_sword_equips_it_and_leaves_the_first_on_the_map() -> void:
	var packed: PackedScene = load("res://src/core/main.tscn")
	var main: Node = auto_free(packed.instantiate())
	add_child(main)
	var enemy: Enemy = main.get_node("Enemy")
	var player: Player = main.get_node("Player")
	var sword: ShortSword = main.get_node("ShortSword")
	var sword2: ShortSword = main.get_node("ShortSword2")
	var player_pos := player.global_position
	var min_player_dist := INF
	var frames := 0
	while not enemy.has_weapon() and frames < 240: # up to 4 s: enough to cover the ~5 m at up to 6 m/s
		await get_tree().physics_frame
		frames += 1
		min_player_dist = minf(min_player_dist, enemy.global_position.distance_to(player_pos))
	assert_that(enemy.has_weapon()).is_true() # it reached and equipped the second sword
	assert_that(sword2.equipped).is_true()
	assert_that(sword2.get_parent()).is_equal(enemy.get_node("SwingPivot/RightHand")) # in its right hand
	assert_that(min_player_dist > enemy.detection_radius).is_true() # on the way it never entered the player's detection range
	assert_that(sword.equipped).is_false() # the first sword stays on the map
	assert_that(sword.get_parent()).is_equal(main)
	var pos_after_equip := enemy.global_position
	for i in 60:
		await get_tree().physics_frame
	# armed and with the player out of range: only the ease-out slide remains (v^2 / 2a = 0.6 m at full speed), no continued chase
	assert_that(enemy.global_position.distance_to(pos_after_equip) < 1.0).is_true()
	assert_that(Vector3(enemy.velocity.x, 0.0, enemy.velocity.z).length() < 0.001).is_true() # stopped, not chasing


func test_armed_enemy_walking_over_a_second_sword_does_not_pick_it_up() -> void:
	var enemy_packed: PackedScene = load("res://src/entities/enemy/enemy.tscn")
	var enemy: Enemy = auto_free(enemy_packed.instantiate())
	enemy.set_physics_process(false) # stationary test double
	add_child(enemy)
	var packed: PackedScene = load("res://src/entities/weapon/short_sword.tscn")
	var first_sword: ShortSword = auto_free(packed.instantiate())
	first_sword.set_process(false)
	first_sword.set_physics_process(false)
	add_child(first_sword)
	first_sword.equip(enemy) # the enemy is already armed
	assert_that(enemy.has_weapon()).is_true()
	var second_sword: ShortSword = auto_free(packed.instantiate())
	second_sword.set_physics_process(false) # tests step _physics_process manually
	second_sword.set_process(false)
	add_child(second_sword)
	second_sword.global_position = Vector3(4, 1.2, 3)
	enemy.global_position = Vector3(4, 0, 3.5) # walked right over it: ~1.3 m, within the 1.5 m pickup radius
	assert_that(second_sword.find_nearest_holder()).is_null() # the armed enemy is skipped as a holder
	second_sword._physics_process(1.0 / 60.0)
	assert_that(second_sword.equipped).is_false() # the sword stays on the map
	assert_that(second_sword.get_parent()).is_not_equal(enemy.get_node("SwingPivot/RightHand"))


func test_sword_goes_to_the_player_when_the_nearest_holder_is_an_armed_enemy() -> void:
	var player_packed: PackedScene = load("res://src/entities/player/player.tscn")
	var player: Player = auto_free(player_packed.instantiate())
	player.add_to_group("player")
	player.set_physics_process(false)
	add_child(player)
	var enemy_packed: PackedScene = load("res://src/entities/enemy/enemy.tscn")
	var enemy: Enemy = auto_free(enemy_packed.instantiate())
	enemy.set_physics_process(false)
	add_child(enemy)
	var packed: PackedScene = load("res://src/entities/weapon/short_sword.tscn")
	var first_sword: ShortSword = auto_free(packed.instantiate())
	first_sword.set_process(false)
	first_sword.set_physics_process(false)
	add_child(first_sword)
	first_sword.equip(enemy) # armed enemy
	var sword: ShortSword = auto_free(packed.instantiate())
	sword.set_physics_process(false) # tests step _physics_process manually
	sword.set_process(false)
	add_child(sword)
	sword.global_position = Vector3(0, 1.2, 0)
	enemy.global_position = Vector3.ZERO # 1.2 m from the sword: nearest, but armed and skipped
	player.global_position = Vector3(0.5, 0, 0) # 1.3 m: within pickup radius
	assert_that(sword.find_nearest_holder()).is_equal(player)
	sword._physics_process(1.0 / 60.0)
	assert_that(sword.equipped).is_true()
	assert_that(sword.holder).is_equal(player) # the player gets it, not the armed enemy


func test_player_can_evade_while_swinging_at_a_clicked_point_behind_it() -> void:
	var packed: PackedScene = load("res://src/core/main.tscn")
	var main: Node = auto_free(packed.instantiate())
	add_child(main)
	main.call("follow_player")
	var player: Player = main.get_node("Player")
	var camera: Camera3D = main.get_node("Camera3D")
	var sword: ShortSword = main.get_node("ShortSword")
	sword.set_physics_process(false)
	sword.equip(player)
	var behind := player.global_position + Vector3(0, 0, -5)
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	click.position = camera.unproject_position(behind)
	sword._unhandled_input(click)
	assert_that(sword._swing_pending).is_true() # the swing waits for the holder to turn first
	Input.action_press("move_right") # camera yaw PI: D walks -X
	var frames := 0
	while sword._swing_time < 0.0 and frames < 120:
		await get_tree().physics_frame # the player turns toward the click while walking
		frames += 1
	Input.action_release("move_right")
	assert_that(sword._swing_time >= 0.0).is_true() # the swing started once the click was faced
	assert_that(player.velocity.x < -5.0).is_true() # still evading at full speed, unaffected by the turn
	assert_that(absf(angle_difference(player.rotation.y, PI)) < 0.05).is_true() # turned 180 degrees to face the click


func test_is_hit_checks_distance_within_radius() -> void:
	assert_that(ShortSword.is_hit(Vector3.ZERO, Vector3(1.5, 0, 0), 1.5)).is_true()
	assert_that(ShortSword.is_hit(Vector3.ZERO, Vector3(1.51, 0, 0), 1.5)).is_false()
	assert_that(ShortSword.is_hit(Vector3(0, 0.8, 0), Vector3(0, 0.8, 0), 0.0)).is_true()


func test_swinging_sword_damages_a_nearby_enemy_exactly_once_per_swing_and_pushes_it_away() -> void:
	var player_packed: PackedScene = load("res://src/entities/player/player.tscn")
	var player: Player = auto_free(player_packed.instantiate())
	player.add_to_group("player")
	player.set_physics_process(false)
	add_child(player)
	var enemy: Enemy = auto_free((load("res://src/entities/enemy/enemy.tscn") as PackedScene).instantiate())
	enemy.set_physics_process(false) # stationary: the knockback velocity is inspected, not integrated
	add_child(enemy)
	enemy.global_position = Vector3(1.2, 0, 0) # adjacent: the swing arc sweeps past it
	var packed: PackedScene = load("res://src/entities/weapon/short_sword.tscn")
	var sword: ShortSword = auto_free(packed.instantiate())
	sword.set_process(false) # tests step _process manually
	sword.set_physics_process(false)
	add_child(sword)
	sword.equip(player)
	assert_that(sword.start_swing()).is_true()
	var dt := 1.0 / 60.0
	for i in 30: # longer than swing_duration: the whole arc plays out
		sword._process(dt)
	assert_that(enemy.health).is_equal(enemy.max_health - sword.damage) # one hit per swing, not per frame
	assert_that(enemy.alive).is_true()
	assert_that(enemy.velocity.x > 0.0).is_true() # pushed away from the player at the origin
	assert_that(sword.start_swing()).is_true() # a second swing hits again
	for i in 30:
		sword._process(dt)
	assert_that(enemy.health).is_equal(enemy.max_health - 2.0 * sword.damage)


func test_swinging_sword_does_not_hit_an_enemy_out_of_range() -> void:
	var player_packed: PackedScene = load("res://src/entities/player/player.tscn")
	var player: Player = auto_free(player_packed.instantiate())
	player.set_physics_process(false)
	add_child(player)
	var enemy: Enemy = auto_free((load("res://src/entities/enemy/enemy.tscn") as PackedScene).instantiate())
	enemy.set_physics_process(false)
	add_child(enemy)
	enemy.global_position = Vector3(5, 0, 0) # well beyond the swing reach
	var packed: PackedScene = load("res://src/entities/weapon/short_sword.tscn")
	var sword: ShortSword = auto_free(packed.instantiate())
	sword.set_process(false)
	sword.set_physics_process(false)
	add_child(sword)
	sword.equip(player)
	assert_that(sword.start_swing()).is_true()
	for i in 30:
		sword._process(1.0 / 60.0)
	assert_that(enemy.health).is_equal(enemy.max_health)
	assert_that(sword._hit_enemies.is_empty()).is_true()


func test_swinging_sword_ignores_a_dead_enemy() -> void:
	var player_packed: PackedScene = load("res://src/entities/player/player.tscn")
	var player: Player = auto_free(player_packed.instantiate())
	player.set_physics_process(false)
	add_child(player)
	var enemy: Enemy = auto_free((load("res://src/entities/enemy/enemy.tscn") as PackedScene).instantiate())
	enemy.set_physics_process(false)
	add_child(enemy)
	enemy.global_position = Vector3(1.2, 0, 0)
	enemy.take_damage(1000.0, Vector3.ZERO) # already dead
	var packed: PackedScene = load("res://src/entities/weapon/short_sword.tscn")
	var sword: ShortSword = auto_free(packed.instantiate())
	sword.set_process(false)
	sword.set_physics_process(false)
	add_child(sword)
	sword.equip(player)
	assert_that(sword.start_swing()).is_true()
	for i in 30:
		sword._process(1.0 / 60.0)
	assert_that(enemy.health).is_equal(0.0)
	assert_that(sword._hit_enemies.is_empty()).is_true()


func test_repeated_player_swings_kill_the_enemy_and_it_falls_onto_its_side() -> void:
	var player_packed: PackedScene = load("res://src/entities/player/player.tscn")
	var player: Player = auto_free(player_packed.instantiate()) # not in the "player" group: the enemy holds still
	player.set_physics_process(false)
	add_child(player)
	var enemy: Enemy = auto_free((load("res://src/entities/enemy/enemy.tscn") as PackedScene).instantiate())
	enemy.set_physics_process(false) # tests step _physics_process manually
	enemy.gravity = 0.0 # no floor in the test scene: the fall pose is checked without settling
	add_child(enemy)
	var packed: PackedScene = load("res://src/entities/weapon/short_sword.tscn")
	var sword: ShortSword = auto_free(packed.instantiate())
	sword.set_process(false)
	sword.set_physics_process(false)
	add_child(sword)
	sword.equip(player)
	var swings := int(ceil(enemy.max_health / sword.damage))
	for s in swings:
		enemy.global_position = Vector3(1.2, 0, 0) # back in the swing arc for each hit
		enemy.velocity = Vector3.ZERO
		assert_that(sword.start_swing()).is_true()
		for i in 30:
			sword._process(1.0 / 60.0)
	assert_that(enemy.alive).is_false()
	assert_that(enemy.health).is_equal(0.0)
	for i in 60: # let the death fall play out (twice death_fall_duration)
		enemy._physics_process(1.0 / 60.0)
	var up := enemy.basis * Vector3.UP
	assert_that(absf(up.y) < 0.01).is_true() # lying on its side
	assert_that(up.x > 0.9).is_true() # fallen away from the player at the origin
