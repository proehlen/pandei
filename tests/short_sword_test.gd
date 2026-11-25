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
	assert_that(directions.size() > steps / 2).is_true() # actually spinning, not static


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
	var hand := player.get_node("Hand") as Node3D
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
	var hand := player.get_node("Hand") as Node3D
	assert_that(sword.get_parent()).is_equal(hand)
	assert_that(sword.transform.is_equal_approx(Transform3D.IDENTITY)).is_true()
	assert_that(hand.basis.is_equal_approx(ShortSword.equipped_basis(sword.equipped_lean))).is_true()
	var pivot := sword.get_node("Placeholder_SwordPivot") as Node3D
	assert_that(pivot.basis.is_equal_approx(Basis.IDENTITY)).is_true() # the sword pivot no longer takes the grip pose
	# hilt (hand origin) at hand height beside the body, outside the 0.4 m capsule radius
	var grip := hand.position
	assert_that(grip.y > 0.8 and grip.y < 1.3).is_true()
	assert_that(Vector2(grip.x, grip.z).length() > 0.4).is_true()
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


func test_hand_pose_basis_is_identity_while_button_held_and_grip_pose_otherwise() -> void:
	assert_that(ShortSword.hand_pose_basis(true, 0.35).is_equal_approx(Basis.IDENTITY)).is_true()
	assert_that(ShortSword.hand_pose_basis(false, 0.35).is_equal_approx(ShortSword.equipped_basis(0.35))).is_true()


func test_held_attack_button_resets_hand_rotation_and_release_restores_grip_pose() -> void:
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
	var hand := player.get_node("Hand") as Node3D
	var blade_node := sword.get_node("Placeholder_SwordPivot/Placeholder_Blade") as Node3D
	# grip pose applied at equip
	assert_that(hand.basis.is_equal_approx(ShortSword.equipped_basis(sword.equipped_lean))).is_true()
	# while the button is held the hand's rotation is reset to zero
	sword._update_hand_pose(true)
	assert_that(hand.basis.is_equal_approx(Basis.IDENTITY)).is_true()
	assert_that(sword.transform.is_equal_approx(Transform3D.IDENTITY)).is_true() # the sword itself is untouched
	var blade_held := (blade_node.global_transform.basis * Vector3.RIGHT).normalized()
	assert_that(absf(blade_held.y) < 0.001).is_true() # blade lies flat along the holder's +X
	# on release the equipped grip pose comes back
	sword._update_hand_pose(false)
	assert_that(hand.basis.is_equal_approx(ShortSword.equipped_basis(sword.equipped_lean))).is_true()
	var blade := (blade_node.global_transform.basis * Vector3.RIGHT).normalized()
	assert_that(blade.y > 0.9).is_true() # blade up again


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
	assert_that(sword_body.get_parent()).is_equal(player.get_node("Hand")) # equipped on the hand
	var blade_node := sword_body.get_node("Placeholder_SwordPivot/Placeholder_Blade") as Node3D
	var blade := (blade_node.global_transform.basis * Vector3.RIGHT).normalized()
	assert_that(blade.y > 0.9).is_true() # equipped blade points up, ready for combat
	var thin_axis := (blade_node.global_transform.basis * Vector3.UP).normalized()
	assert_that(absf(thin_axis.y) < 0.01).is_true() # edge horizontal in the hand, not twisted
