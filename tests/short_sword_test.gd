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


func test_short_sword_scene_has_tracked_placeholder_parts_with_primitive_meshes() -> void:
	var packed: PackedScene = load("res://src/entities/weapon/short_sword.tscn")
	assert_that(packed).is_not_null()
	var sword: ShortSword = auto_free(packed.instantiate())
	for part_name in ["Placeholder_Blade", "Placeholder_Guard", "Placeholder_Handle"]:
		var part: Node = sword.get_node_or_null(part_name)
		assert_that(part).is_not_null()
		assert_that(part.is_in_group("ai_placeholder")).is_true()
		assert_that(part is MeshInstance3D).is_true()
		var mesh := (part as MeshInstance3D).mesh
		assert_that(mesh is BoxMesh or mesh is CylinderMesh).is_true() # built-in primitives only
		var material := (part as MeshInstance3D).get_active_material(0) as StandardMaterial3D
		assert_that(material).is_not_null()
	var handle: Node3D = sword.get_node("Placeholder_Handle")
	assert_that(absf(handle.rotation.z - PI / 2.0) < 0.001).is_true() # handle lies along the blade


func test_ready_pins_sword_to_hover_height() -> void:
	var sword: ShortSword = auto_free(ShortSword.new())
	add_child(sword) # triggers _ready
	assert_that(absf(sword.position.y - sword.hover_height) < 0.0001).is_true()
	assert_that(sword.position.y > 0.5).is_true() # floating above the ground, not resting on it


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
