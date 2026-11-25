extends GdUnitTestSuite


func test_chase_velocity_moves_toward_target_at_full_speed_on_xz_plane() -> void:
	var velocity := Enemy.chase_velocity(Vector3(20, 0, 15), Vector3.ZERO, 6.0)
	assert_that(velocity.y).is_equal(0.0)
	assert_that(absf(velocity.length() - 6.0) < 0.0001).is_true()
	assert_that(velocity.x < 0.0 and velocity.z < 0.0).is_true() # toward the origin


func test_chase_velocity_is_zero_at_target() -> void:
	assert_that(Enemy.chase_velocity(Vector3(1, 0, 1), Vector3(1, 0, 1), 6.0)).is_equal(Vector3.ZERO)


func test_detection_radius_boundary() -> void:
	var enemy_pos := Vector3(20, 0, 15)
	assert_that(Enemy.is_within_detection(enemy_pos, Vector3.ZERO, 15.0)).is_false() # 25 m away
	assert_that(Enemy.is_within_detection(enemy_pos, Vector3(20, 0, 0), 15.0)).is_true() # exactly 15 m
	assert_that(Enemy.is_within_detection(enemy_pos, Vector3(20, 0, -0.1), 15.0)).is_false() # just over 15 m
	assert_that(Enemy.is_within_detection(enemy_pos, enemy_pos, 15.0)).is_true()


func test_enemy_scene_has_red_placeholder_body() -> void:
	var packed: PackedScene = load("res://src/entities/enemy/enemy.tscn")
	assert_that(packed).is_not_null()
	var enemy: Enemy = auto_free(packed.instantiate())
	var collision: Node = enemy.get_node_or_null("CollisionShape3D")
	assert_that(collision).is_not_null()
	assert_that((collision as CollisionShape3D).shape is CapsuleShape3D).is_true()
	var body: Node = enemy.get_node_or_null("Placeholder_Body")
	assert_that(body).is_not_null()
	assert_that(body.is_in_group("ai_placeholder")).is_true()
	assert_that((body as MeshInstance3D).mesh is CapsuleMesh).is_true()
	var material := (body as MeshInstance3D).get_active_material(0) as StandardMaterial3D
	assert_that(material).is_not_null()
	assert_that(material.albedo_color.r > 0.7).is_true()
	assert_that(material.albedo_color.g < 0.3).is_true()
	assert_that(material.albedo_color.b < 0.3).is_true()


func test_main_scene_places_enemy_25_units_from_player_and_syncs_speed() -> void:
	var packed: PackedScene = load("res://src/core/main.tscn")
	var main: Node = auto_free(packed.instantiate())
	add_child(main) # triggers _ready, which syncs the enemy speed to the player's
	await get_tree().physics_frame # lets the enemy acquire its target from the "player" group
	var player: Node = main.get_node_or_null("Player")
	var enemy: Node = main.get_node_or_null("Enemy")
	assert_that(player).is_not_null()
	assert_that(enemy).is_not_null()
	assert_that(player.is_in_group("player")).is_true()
	assert_that(absf(player.global_position.distance_to(enemy.global_position) - 25.0) < 0.001).is_true()
	var enemy_body := enemy as Enemy
	assert_that(enemy_body.detection_radius).is_equal(15.0)
	assert_that(enemy_body.move_speed).is_equal((player as Player).move_speed)
	assert_that(enemy_body.target).is_equal(player)


func test_enemy_acquires_player_from_group() -> void:
	var player: Player = auto_free(Player.new())
	player.add_to_group("player")
	add_child(player)
	var enemy: Enemy = auto_free(Enemy.new())
	enemy.set_physics_process(false) # tests step _physics_process manually
	add_child(enemy) # _ready acquires the target
	assert_that(enemy.target).is_equal(player)


func test_compute_chase_velocity_matches_detection_radius() -> void:
	var enemy: Enemy = auto_free(Enemy.new())
	enemy.set_physics_process(false) # tests step _physics_process manually
	add_child(enemy)
	var target: Node3D = auto_free(Node3D.new())
	add_child(target)
	enemy.target = target
	enemy.global_position = Vector3(20, 0, 15)
	target.global_position = Vector3.ZERO
	assert_that(enemy.compute_chase_velocity()).is_equal(Vector3.ZERO) # 25 m > 15 m radius
	target.global_position = Vector3(20, 0, 5) # 10 m away
	var chase: Vector3 = enemy.compute_chase_velocity()
	assert_that(absf(chase.length() - enemy.move_speed) < 0.0001).is_true()
	assert_that(chase.z < 0.0 and absf(chase.x) < 0.0001).is_true() # straight toward the target


func test_enemy_stays_idle_outside_radius_and_chases_inside_it_at_player_speed() -> void:
	var player: Player = auto_free(Player.new())
	add_child(player)
	player.global_position = Vector3.ZERO
	var enemy: Enemy = auto_free(Enemy.new())
	enemy.set_physics_process(false) # tests step _physics_process manually
	enemy.target = player
	enemy.move_speed = player.move_speed
	add_child(enemy)
	enemy.global_position = Vector3(20, 0, 15) # 25 m away: outside the 15 m radius
	enemy._physics_process(1.0 / 60.0)
	assert_that(Vector3(enemy.velocity.x, 0.0, enemy.velocity.z)).is_equal(Vector3.ZERO)
	player.global_position = Vector3(18, 0, 15) # 2 m away: inside the radius
	enemy._physics_process(1.0 / 60.0)
	var horizontal := Vector3(enemy.velocity.x, 0.0, enemy.velocity.z)
	assert_that(absf(horizontal.length() - player.move_speed) < 0.001).is_true()
	assert_that(horizontal.x < 0.0 and absf(horizontal.z) < 0.0001).is_true() # straight toward the player
