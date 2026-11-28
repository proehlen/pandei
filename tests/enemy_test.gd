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


func test_main_scene_places_enemy_at_its_design_position_with_its_own_speed() -> void:
	var packed: PackedScene = load("res://src/core/main.tscn")
	var main: Node = auto_free(packed.instantiate())
	var player_node: Node = main.get_node_or_null("Player")
	(player_node as Player).move_speed = 9.0 # a different player speed must not leak into the enemy
	var enemy_node: Node = main.get_node_or_null("Enemy")
	(enemy_node as Enemy).set_physics_process(false) # placement check only: keep the enemy on its post instead of chasing the nearby sword
	add_child(main) # triggers _ready
	await get_tree().physics_frame # lets the enemy acquire its target from the "player" group
	var player: Node = main.get_node_or_null("Player")
	var enemy: Node = enemy_node
	assert_that(player).is_not_null()
	assert_that(enemy).is_not_null()
	assert_that(player.is_in_group("player")).is_true()
	# placed at (7, 0, 6) in main.tscn: sqrt(7^2 + 6^2) ~ 9.22 m from the player at the origin
	assert_that((enemy as Node3D).position).is_equal(Vector3(7, 0, 6))
	assert_that(absf(player.global_position.distance_to(enemy.global_position) - sqrt(85.0)) < 0.001).is_true()
	var enemy_body := enemy as Enemy
	assert_that(enemy_body.detection_radius).is_equal(8.0)
	assert_that(enemy_body.give_up_radius).is_equal(2.0 * enemy_body.detection_radius)
	assert_that(enemy_body.move_speed).is_equal(6.0) # its own design value, not the player's 9.0
	assert_that(enemy_body.move_speed).is_not_equal((player as Player).move_speed)
	assert_that(enemy_body.start_position).is_equal(Vector3(7, 0, 6)) # give-up leash anchored at the spawn point
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
	enemy.start_position = enemy.global_position # leash anchored where the enemy stands
	target.global_position = Vector3.ZERO
	assert_that(enemy.compute_chase_velocity()).is_equal(Vector3.ZERO) # 25 m > 8 m default radius
	target.global_position = Vector3(20, 0, 10) # 5 m away: inside the 8 m default radius
	var chase: Vector3 = enemy.compute_chase_velocity()
	assert_that(absf(chase.length() - enemy.move_speed) < 0.0001).is_true()
	assert_that(chase.z < 0.0 and absf(chase.x) < 0.0001).is_true() # straight toward the target


func test_enemy_stays_idle_outside_radius_and_chases_inside_it_at_its_own_speed() -> void:
	var player: Player = auto_free(Player.new())
	add_child(player)
	player.global_position = Vector3.ZERO
	player.move_speed = 9.0 # the enemy must not take its speed from the player
	var enemy: Enemy = auto_free(Enemy.new())
	enemy.set_physics_process(false) # tests step _physics_process manually
	enemy.target = player
	add_child(enemy)
	enemy.global_position = Vector3(20, 0, 15) # 25 m away: outside the 8 m default radius
	enemy.start_position = enemy.global_position # leash anchored where the enemy stands
	enemy._physics_process(1.0 / 60.0)
	assert_that(Vector3(enemy.velocity.x, 0.0, enemy.velocity.z)).is_equal(Vector3.ZERO)
	player.global_position = Vector3(18, 0, 15) # 2 m away: inside the radius
	for i in 14: # 14 frames at 30 m/s^2 reach the 6 m/s top speed (capped by ease_velocity)
		enemy._physics_process(1.0 / 60.0)
	var horizontal := Vector3(enemy.velocity.x, 0.0, enemy.velocity.z)
	assert_that(enemy.move_speed).is_equal(6.0)
	assert_that(absf(horizontal.length() - enemy.move_speed) < 0.001).is_true()
	assert_that(horizontal.x < 0.0 and absf(horizontal.z) < 0.0001).is_true() # straight toward the player


func test_give_up_radius_defaults_to_twice_the_detection_radius() -> void:
	var enemy: Enemy = auto_free(Enemy.new())
	assert_that(enemy.give_up_radius).is_equal(2.0 * enemy.detection_radius)


func test_enemy_gives_up_when_target_is_beyond_give_up_radius_from_its_start() -> void:
	var enemy: Enemy = auto_free(Enemy.new())
	enemy.set_physics_process(false) # tests step _physics_process manually
	add_child(enemy) # _ready anchors start_position at the origin
	assert_that(enemy.start_position).is_equal(Vector3.ZERO)
	var target: Node3D = auto_free(Node3D.new())
	add_child(target)
	enemy.target = target
	enemy.global_position = Vector3(0, 0, 10) # the enemy has chased 10 m away from its post
	target.global_position = Vector3(0, 0, 15) # 5 m from the enemy (inside detection), 15 m from start (inside leash)
	assert_that(enemy.compute_chase_velocity()).is_not_equal(Vector3.ZERO)
	target.global_position = Vector3(0, 0, 17) # 7 m from the enemy (still inside detection) but 17 m from start: beyond the leash
	assert_that(enemy.compute_chase_velocity()).is_equal(Vector3.ZERO)


func test_ease_velocity_moves_toward_target_by_at_most_acceleration_times_delta() -> void:
	var eased := Enemy.ease_velocity(Vector3.ZERO, Vector3(6, 0, 0), 30.0, 1.0 / 60.0)
	assert_that(absf(eased.x - 0.5) < 0.0001 and absf(eased.z) < 0.0001).is_true() # 30 * 1/60, not full speed
	# a step larger than the remaining distance lands exactly on the target
	assert_that(Enemy.ease_velocity(Vector3(5.9, 0, 0), Vector3(6, 0, 0), 30.0, 1.0 / 60.0)).is_equal(Vector3(6, 0, 0))
	# easing out uses the same rate back toward zero
	var slowed := Enemy.ease_velocity(Vector3(6, 0, 0), Vector3.ZERO, 30.0, 1.0 / 60.0)
	assert_that(absf(slowed.x - 5.5) < 0.0001).is_true()


func test_enemy_eases_in_to_top_speed_and_eases_out_to_a_stop() -> void:
	var enemy: Enemy = auto_free(Enemy.new())
	enemy.set_physics_process(false) # tests step _physics_process manually
	add_child(enemy) # start_position at the origin
	var target: Node3D = auto_free(Node3D.new())
	add_child(target)
	enemy.target = target
	target.global_position = Vector3(0, 0, 7) # inside detection radius and leash
	enemy._physics_process(1.0 / 60.0)
	var first := Vector3(enemy.velocity.x, 0.0, enemy.velocity.z)
	assert_that(absf(first.length() - enemy.acceleration / 60.0) < 0.0001).is_true() # ease in, not instantly at max
	assert_that(first.length() < enemy.move_speed).is_true()
	for i in 13:
		enemy._physics_process(1.0 / 60.0)
	var top := Vector3(enemy.velocity.x, 0.0, enemy.velocity.z)
	assert_that(absf(top.length() - enemy.move_speed) < 0.001).is_true() # top speed reached
	target.global_position = Vector3(0, 0, 100) # out of range: desired velocity drops to zero
	enemy._physics_process(1.0 / 60.0)
	var slowed := Vector3(enemy.velocity.x, 0.0, enemy.velocity.z)
	assert_that(absf(slowed.length() - (enemy.move_speed - enemy.acceleration / 60.0)) < 0.0001).is_true() # ease out, not instantly zero


func test_enemy_collision_capsule_mimics_the_players_wider_hand_span_capsule() -> void:
	var player: Player = auto_free((load("res://src/entities/player/player.tscn") as PackedScene).instantiate())
	var enemy: Enemy = auto_free((load("res://src/entities/enemy/enemy.tscn") as PackedScene).instantiate())
	var player_shape := player.get_node("CollisionShape3D").shape as CapsuleShape3D
	var enemy_shape := enemy.get_node("CollisionShape3D").shape as CapsuleShape3D
	assert_that(enemy_shape.radius).is_equal(player_shape.radius) # same diameter on both bodies
	assert_that(enemy_shape.radius > 0.4).is_true() # wider than the old torso-only capsule
	assert_that(enemy_shape.height).is_equal(player_shape.height) # only the diameter grew, not the height
	assert_that(absf(enemy_shape.height - 1.6) < 0.0001).is_true() # height unchanged (float32 from the scene)


func test_enemy_scene_has_a_right_hand_like_the_players_and_sits_in_the_enemy_group() -> void:
	var packed: PackedScene = load("res://src/entities/enemy/enemy.tscn")
	var enemy: Enemy = auto_free(packed.instantiate())
	assert_that(enemy.is_in_group("enemy")).is_true()
	var hand: Node = enemy.get_node_or_null("SwingPivot/RightHand")
	assert_that(hand).is_not_null()
	assert_that((hand as Node3D).position).is_equal(Vector3(-0.55, 0.8, 0.15)) # same design pose as the player's hand
	var placeholder: Node = enemy.get_node_or_null("SwingPivot/RightHand/Placeholder_RightHand")
	assert_that(placeholder).is_not_null()
	assert_that(placeholder.is_in_group("ai_placeholder")).is_true()
	assert_that((placeholder as MeshInstance3D).mesh is SphereMesh).is_true()
	assert_that(enemy.has_weapon()).is_false() # empty hand: no weapon yet


func test_enemy_without_weapon_chases_a_detected_sword_and_ignores_a_closer_player() -> void:
	var player: Player = auto_free(Player.new())
	player.add_to_group("player")
	add_child(player)
	player.global_position = Vector3(2, 0, 0) # 2 m away: closer than the sword, but must be ignored
	var enemy: Enemy = auto_free((load("res://src/entities/enemy/enemy.tscn") as PackedScene).instantiate())
	enemy.set_physics_process(false) # tests step compute_chase_velocity manually
	add_child(enemy) # _ready anchors start_position at the origin and acquires the player
	var sword: ShortSword = auto_free((load("res://src/entities/weapon/short_sword.tscn") as PackedScene).instantiate())
	sword.set_physics_process(false) # no self-pickup while the test steps things manually
	sword.set_process(false)
	add_child(sword)
	sword.global_position = Vector3(0, 0, 5) # 5 m away: inside the 8 m detection radius
	assert_that(sword.is_in_group("weapon")).is_true()
	assert_that(enemy.has_weapon()).is_false()
	assert_that(enemy.find_weapon_target()).is_equal(sword)
	assert_that(enemy.current_chase_target()).is_equal(sword) # the sword, not the closer player
	var chase: Vector3 = enemy.compute_chase_velocity()
	assert_that(absf(chase.length() - enemy.move_speed) < 0.0001).is_true()
	assert_that(chase.z > 0.0 and absf(chase.x) < 0.0001).is_true() # straight toward the sword, not the player at +X


func test_enemy_prefers_the_nearest_detected_weapon() -> void:
	var enemy: Enemy = auto_free((load("res://src/entities/enemy/enemy.tscn") as PackedScene).instantiate())
	enemy.set_physics_process(false)
	add_child(enemy) # start_position at the origin
	var near_sword: ShortSword = auto_free((load("res://src/entities/weapon/short_sword.tscn") as PackedScene).instantiate())
	near_sword.set_physics_process(false)
	near_sword.set_process(false)
	add_child(near_sword)
	near_sword.global_position = Vector3(3, 0, 0)
	var far_sword: ShortSword = auto_free((load("res://src/entities/weapon/short_sword.tscn") as PackedScene).instantiate())
	far_sword.set_physics_process(false)
	far_sword.set_process(false)
	add_child(far_sword)
	far_sword.global_position = Vector3(0, 0, 6) # both inside the 8 m detection radius
	assert_that(enemy.find_weapon_target()).is_equal(near_sword)
	var chase: Vector3 = enemy.compute_chase_velocity()
	assert_that(chase.x > 0.0 and absf(chase.z) < 0.0001).is_true() # toward the nearer sword


func test_enemy_ignores_weapons_beyond_detection_radius_and_chases_the_player() -> void:
	var player: Player = auto_free(Player.new())
	player.add_to_group("player")
	add_child(player)
	player.global_position = Vector3(0, 0, 5) # 5 m: inside detection
	var enemy: Enemy = auto_free((load("res://src/entities/enemy/enemy.tscn") as PackedScene).instantiate())
	enemy.set_physics_process(false)
	add_child(enemy)
	enemy.target = player
	var sword: ShortSword = auto_free((load("res://src/entities/weapon/short_sword.tscn") as PackedScene).instantiate())
	sword.set_physics_process(false)
	sword.set_process(false)
	add_child(sword)
	sword.global_position = Vector3(0, 0, 9) # 9 m: outside the 8 m detection radius
	assert_that(enemy.find_weapon_target()).is_null()
	assert_that(enemy.current_chase_target()).is_equal(player)
	var chase: Vector3 = enemy.compute_chase_velocity()
	assert_that(chase.z > 0.0 and absf(chase.x) < 0.0001).is_true() # straight at the player


func test_enemy_with_equipped_sword_chases_the_player_under_the_existing_limits() -> void:
	var player: Player = auto_free(Player.new())
	player.add_to_group("player")
	add_child(player)
	player.global_position = Vector3(0, 0, 5) # inside detection, inside the leash
	var enemy: Enemy = auto_free((load("res://src/entities/enemy/enemy.tscn") as PackedScene).instantiate())
	enemy.set_physics_process(false)
	add_child(enemy)
	enemy.target = player
	var sword: ShortSword = auto_free((load("res://src/entities/weapon/short_sword.tscn") as PackedScene).instantiate())
	sword.set_process(false)
	sword.set_physics_process(false)
	add_child(sword)
	sword.global_position = Vector3(0, 0, 3) # detected, but the enemy already has a weapon: irrelevant now
	sword.equip(enemy) # picked up into the enemy's RightHand
	assert_that(enemy.has_weapon()).is_true()
	assert_that(sword.get_parent()).is_equal(enemy.get_node("SwingPivot/RightHand"))
	assert_that(enemy.current_chase_target()).is_equal(player) # the detected sword no longer distracts it
	var chase: Vector3 = enemy.compute_chase_velocity()
	assert_that(absf(chase.length() - enemy.move_speed) < 0.0001).is_true()
	assert_that(chase.z > 0.0 and absf(chase.x) < 0.0001).is_true() # straight at the player
	enemy.global_position = Vector3(0, 0, 10) # the enemy has chased 10 m away from its post
	player.global_position = Vector3(0, 0, 17) # 7 m from the enemy (inside detection) but 17 m from start: beyond the leash
	assert_that(enemy.compute_chase_velocity()).is_equal(Vector3.ZERO) # the existing give-up limit still applies


func test_chasing_enemy_stops_at_capsule_contact_instead_of_reaching_the_player() -> void:
	var player: Player = auto_free((load("res://src/entities/player/player.tscn") as PackedScene).instantiate())
	player.set_physics_process(false) # stationary target
	player.gravity = 0.0 # stay at y=0 even if the physics loop runs: capsules must overlap vertically to collide
	add_child(player)
	player.global_position = Vector3(0, 0, 5)
	var enemy: Enemy = auto_free((load("res://src/entities/enemy/enemy.tscn") as PackedScene).instantiate())
	enemy.gravity = 0.0 # keep both capsules at the same height so they can collide
	add_child(enemy) # start_position at the origin; the real physics loop drives the chase
	enemy.target = player
	for i in 120: # 2 s of chase at up to 6 m/s easily covers the 5 m gap
		await get_tree().physics_frame
	var player_shape := player.get_node("CollisionShape3D").shape as CapsuleShape3D
	var enemy_shape := enemy.get_node("CollisionShape3D").shape as CapsuleShape3D
	var contact := player_shape.radius + enemy_shape.radius # center distance when the capsules touch
	var gap := player.global_position.distance_to(enemy.global_position)
	assert_that(gap < 5.0).is_true() # the enemy actually closed in on the player
	assert_that(gap >= contact - 0.05).is_true() # ...but stops at contact instead of overlapping


func test_enemy_starts_alive_at_full_health_with_a_billboard_bar_over_its_head() -> void:
	var enemy: Enemy = auto_free((load("res://src/entities/enemy/enemy.tscn") as PackedScene).instantiate())
	add_child(enemy) # _ready fills health and refreshes the bar
	assert_that(enemy.alive).is_true()
	assert_that(enemy.health).is_equal(enemy.max_health)
	var bar: Node = enemy.get_node_or_null("Placeholder_HealthBar")
	assert_that(bar).is_not_null()
	assert_that(bar.is_in_group("ai_placeholder")).is_true()
	assert_that((bar as Node3D).position.y > 1.6).is_true() # above the 1.6 m tall body
	assert_that(bar.visible).is_true()
	var background: Node = bar.get_node_or_null("Placeholder_HealthBarBackground")
	var fill: Node = bar.get_node_or_null("Placeholder_HealthBarFill")
	assert_that(background).is_not_null()
	assert_that(fill).is_not_null()
	assert_that(background.is_in_group("ai_placeholder")).is_true()
	assert_that(fill.is_in_group("ai_placeholder")).is_true()
	assert_that((background as MeshInstance3D).mesh is QuadMesh).is_true()
	assert_that((fill as MeshInstance3D).mesh is QuadMesh).is_true()
	var bg_material := (background as MeshInstance3D).get_active_material(0) as StandardMaterial3D
	var fill_material := (fill as MeshInstance3D).get_active_material(0) as StandardMaterial3D
	assert_that(bg_material.billboard_mode == BaseMaterial3D.BILLBOARD_ENABLED).is_true() # always faces the camera
	assert_that(fill_material.billboard_mode == BaseMaterial3D.BILLBOARD_ENABLED).is_true()
	assert_that(absf((fill as MeshInstance3D).scale.x - 1.0) < 0.0001).is_true() # full bar at full health


func test_health_fraction_clamps_between_zero_and_one() -> void:
	assert_that(Enemy.health_fraction(100.0, 100.0)).is_equal(1.0)
	assert_that(Enemy.health_fraction(70.0, 100.0)).is_equal(0.7)
	assert_that(Enemy.health_fraction(0.0, 100.0)).is_equal(0.0)
	assert_that(Enemy.health_fraction(-5.0, 100.0)).is_equal(0.0)
	assert_that(Enemy.health_fraction(150.0, 100.0)).is_equal(1.0)
	assert_that(Enemy.health_fraction(10.0, 0.0)).is_equal(0.0) # degenerate max: no division by zero


func test_take_damage_reduces_health_scales_the_bar_and_pushes_the_enemy_away_from_the_strike() -> void:
	var enemy: Enemy = auto_free((load("res://src/entities/enemy/enemy.tscn") as PackedScene).instantiate())
	enemy.set_physics_process(false) # the knockback velocity is inspected, not integrated
	add_child(enemy)
	enemy.global_position = Vector3(5, 0, 0)
	enemy.take_damage(30.0, Vector3.ZERO) # struck from the origin: pushed toward +X
	assert_that(enemy.alive).is_true()
	assert_that(enemy.health).is_equal(70.0)
	assert_that(absf(enemy.velocity.x - enemy.knockback_speed) < 0.0001).is_true()
	assert_that(absf(enemy.velocity.z) < 0.0001).is_true()
	var fill := enemy.get_node("Placeholder_HealthBar/Placeholder_HealthBarFill") as MeshInstance3D
	assert_that(absf(fill.scale.x - 0.7) < 0.0001).is_true() # the bar shows 70%
	assert_that(absf(fill.position.x - (-0.5 * 0.3)) < 0.0001).is_true() # the fill stays anchored at the left edge


func test_take_damage_clamps_at_zero_kills_the_enemy_and_hides_the_bar() -> void:
	var enemy: Enemy = auto_free((load("res://src/entities/enemy/enemy.tscn") as PackedScene).instantiate())
	enemy.set_physics_process(false)
	add_child(enemy)
	enemy.global_position = Vector3(5, 0, 0)
	enemy.take_damage(250.0, Vector3.ZERO)
	assert_that(enemy.health).is_equal(0.0)
	assert_that(enemy.alive).is_false()
	assert_that(enemy.get_node("Placeholder_HealthBar").visible).is_false()
	enemy.take_damage(10.0, Vector3.ZERO) # a dead enemy takes no further damage
	assert_that(enemy.health).is_equal(0.0)


func test_dead_enemy_stops_chasing() -> void:
	var player: Player = auto_free(Player.new())
	player.add_to_group("player")
	add_child(player)
	player.global_position = Vector3(0, 0, 5) # inside detection radius and leash
	var enemy: Enemy = auto_free((load("res://src/entities/enemy/enemy.tscn") as PackedScene).instantiate())
	enemy.set_physics_process(false)
	add_child(enemy)
	enemy.target = player
	assert_that(enemy.compute_chase_velocity()).is_not_equal(Vector3.ZERO) # alive: chases
	enemy.take_damage(1000.0, Vector3.ZERO)
	assert_that(enemy.compute_chase_velocity()).is_equal(Vector3.ZERO) # dead: stands down


func test_dead_enemy_falls_onto_its_side_away_from_the_strike_and_stays_down() -> void:
	var enemy: Enemy = auto_free((load("res://src/entities/enemy/enemy.tscn") as PackedScene).instantiate())
	enemy.set_physics_process(false) # tests step _physics_process manually
	enemy.gravity = 0.0 # no floor in the test scene: keep y fixed while the fall plays out
	add_child(enemy)
	enemy.global_position = Vector3(2, 0, 0)
	enemy.take_damage(1000.0, Vector3.ZERO) # struck from -X: falls toward +X
	assert_that(enemy.alive).is_false()
	assert_that(absf((enemy.basis * Vector3.UP).y - 1.0) < 0.0001).is_true() # still upright at the moment of death
	for i in 60: # 1 s: twice the death fall duration
		enemy._physics_process(1.0 / 60.0)
	var up := enemy.basis * Vector3.UP
	assert_that(absf(up.y) < 0.01).is_true() # lying down: the up axis is horizontal
	assert_that(absf(up.length() - 1.0) < 0.01).is_true()
	assert_that(up.x > 0.9).is_true() # tipped away from the strike (+X)
	var fallen := enemy.basis
	for i in 10:
		enemy._physics_process(1.0 / 60.0)
	assert_that(enemy.basis.is_equal_approx(fallen)).is_true() # stays down


func test_health_bar_faces_the_camera_and_the_fill_stays_in_front_of_the_background_from_either_side() -> void:
	var packed: PackedScene = load("res://src/core/main.tscn")
	var main: Node = auto_free(packed.instantiate())
	add_child(main) # brings the active Camera3D
	var enemy: Enemy = main.get_node("Enemy")
	enemy.set_physics_process(false) # hold the enemy still so nothing rotates between the facing and the assertions
	var bar := enemy.get_node("Placeholder_HealthBar") as Node3D
	var background := bar.get_node("Placeholder_HealthBarBackground") as Node3D
	var fill := bar.get_node("Placeholder_HealthBarFill") as Node3D
	var camera := main.get_node("Camera3D") as Camera3D
	for cam_z in [-6.0, 18.0]: # camera on the -Z side of the enemy (z=6), then on the +Z side
		camera.global_position = Vector3(0, 10.5, cam_z)
		enemy._process(0.0) # face the bar at the camera, synchronously (no frames run during this test)
		var to_camera := (camera.global_position - bar.global_position).normalized()
		assert_that((bar.global_basis * Vector3(0, 0, 1)).dot(to_camera) > 0.999).is_true() # the quads' +Z normal faces the camera
		assert_that(camera.global_position.distance_to(fill.global_position) < camera.global_position.distance_to(background.global_position)).is_true() # fill strictly in front: no z-fighting from this side
