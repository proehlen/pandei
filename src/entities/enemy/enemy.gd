class_name Enemy
extends CharacterBody3D

## Distance in meters at which the enemy spots the player and starts chasing.
@export var detection_radius: float = 8.0
## The enemy's own top chase speed in meters per second, independent of the
## player's speed; tune per enemy type.
@export var move_speed: float = 6.0
## Distance in meters from the enemy's starting position beyond which it gives
## up chasing and idles again. Defaults to twice detection_radius.
@export var give_up_radius: float = 16.0
## Gravity applied while airborne so the enemy stays grounded.
@export var gravity: float = 20.0
## How quickly the enemy turns to face the player (radians per second).
@export var turn_speed: float = 12.0
## Horizontal acceleration in m/s^2 used to ease in/out of movement. At the
## defaults this reaches move_speed in ~0.2 s, keeping the ramp subtle.
@export var acceleration: float = 30.0
## Hitpoints the enemy starts with. Reaching zero kills it.
@export var max_health: float = 100.0
## Horizontal push speed in m/s applied away from the strike when the enemy
## is hit. The chase easing decays it over ~knockback_speed/acceleration seconds.
@export var knockback_speed: float = 8.0
## Seconds the death fall (tipping the model onto its side) takes.
@export var death_fall_duration: float = 0.5

## The node the enemy chases. Acquired from the "player" group when unset.
var target: Node3D = null
## World position where the enemy entered the scene. The give-up leash is
## anchored here so the enemy cannot be kited arbitrarily far from its post.
var start_position: Vector3
## Current hitpoints. Set to max_health in _ready; clamped at zero on death.
var health: float = 0.0
## False once health reached zero: a dead enemy stops chasing and falls over.
var alive: bool = true
## Elapsed seconds since death; negative while alive.
var _death_time: float = -1.0
## Body basis captured when death started and the lying-down pose it eases toward.
var _death_start_basis := Basis.IDENTITY
var _death_target_basis := Basis.IDENTITY
## World-space horizontal direction of the last hit, used to pick the fall direction.
var _last_hit_direction := Vector3.ZERO


## True when the enemy's RightHand holds an equipped weapon (a ShortSword
## picked up from the "weapon" group).
func has_weapon() -> bool:
	var hand := get_node_or_null("SwingPivot/RightHand")
	if hand == null:
		return false
	for child in hand.get_children():
		if child is ShortSword and (child as ShortSword).equipped:
			return true
	return false


## Nearest unequipped weapon (ShortSword in the "weapon" group) within
## detection_radius of the enemy, or null when none is detected.
func find_weapon_target() -> Node3D:
	var nearest: Node3D = null
	var nearest_dist := INF
	for member in get_tree().get_nodes_in_group("weapon"):
		var sword := member as ShortSword
		if sword == null or not is_instance_valid(sword) or sword.equipped:
			continue
		var dist := global_position.distance_to(sword.global_position)
		if dist <= detection_radius and dist < nearest_dist:
			nearest_dist = dist
			nearest = sword
	return nearest


## The node the enemy currently wants to move toward: when it carries no
## weapon and detects one, the nearest detected weapon (the player is
## ignored); otherwise the player target.
func current_chase_target() -> Node3D:
	if not has_weapon():
		var weapon := find_weapon_target()
		if weapon != null:
			return weapon
	return target


## True when `to` lies within `radius` meters of `from`. Pure function so it stays unit-testable.
static func is_within_detection(from: Vector3, to: Vector3, radius: float) -> bool:
	return from.distance_to(to) <= radius


## Horizontal velocity that moves from `from` toward `to` at `speed` on the XZ
## plane (y stays 0; gravity is applied separately in _physics_process).
## Returns Vector3.ZERO when already at the target. Pure function so it stays unit-testable.
static func chase_velocity(from: Vector3, to: Vector3, speed: float) -> Vector3:
	var to_target := Vector3(to.x - from.x, 0.0, to.z - from.z)
	if to_target.length() < 0.001:
		return Vector3.ZERO
	return to_target.normalized() * speed


## Horizontal velocity after easing `current` toward `target_velocity` by at most
## `accel * delta` meters. Pure function so it stays unit-testable.
static func ease_velocity(current: Vector3, target_velocity: Vector3, accel: float, delta: float) -> Vector3:
	return current.move_toward(target_velocity, accel * delta)


## Health as a fraction in [0, 1] for the given max. Pure function so it stays
## unit-testable; a non-positive max yields 0 instead of dividing by zero.
static func health_fraction(current: float, maximum: float) -> float:
	if maximum <= 0.0:
		return 0.0
	return clampf(current / maximum, 0.0, 1.0)


func _ready() -> void:
	start_position = global_position
	acquire_target()
	health = max_health
	_update_health_bar()


func _process(_delta: float) -> void:
	_face_health_bar_to_camera()


## Rotates the health bar so its local +Z (the quads' normal) points at the
## active camera. The fill quad sits at +Z of the background quad, so this
## keeps the fill in front along the view direction from any camera side,
## instead of z-fighting with the background as the camera moves around.
func _face_health_bar_to_camera() -> void:
	var bar := get_node_or_null("Placeholder_HealthBar") as Node3D
	if bar == null or not bar.visible:
		return
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return
	var to_camera := camera.global_position - bar.global_position
	if to_camera.is_zero_approx():
		return
	var dir := -to_camera.normalized() # Basis.looking_at points -Z along dir: this puts +Z toward the camera
	var up := Vector3.UP
	if absf(dir.y) > 0.999: # camera almost straight above/below: pick a non-parallel up
		up = Vector3.FORWARD
	bar.global_basis = Basis.looking_at(dir, up)


func _physics_process(delta: float) -> void:
	acquire_target()
	var chase := compute_chase_velocity()
	var horizontal := ease_velocity(Vector3(velocity.x, 0.0, velocity.z), chase, acceleration, delta)
	velocity.x = horizontal.x
	velocity.z = horizontal.z
	if not chase.is_zero_approx():
		rotation.y = lerp_angle(rotation.y, atan2(chase.x, chase.z), clampf(turn_speed * delta, 0.0, 1.0))
	elif not alive:
		_advance_death_fall(delta)
	if not is_on_floor():
		velocity.y -= gravity * delta
	move_and_slide()


## Horizontal velocity toward the current chase target while it is within
## detection_radius of the enemy and within give_up_radius of the enemy's
## starting position, else zero.
func compute_chase_velocity() -> Vector3:
	if not alive:
		return Vector3.ZERO # a dead enemy stands down
	var chase_target := current_chase_target()
	if chase_target == null or not is_instance_valid(chase_target):
		return Vector3.ZERO
	if not is_within_detection(global_position, chase_target.global_position, detection_radius):
		return Vector3.ZERO
	if not is_within_detection(start_position, chase_target.global_position, give_up_radius):
		return Vector3.ZERO
	return chase_velocity(global_position, chase_target.global_position, move_speed)


## Finds the player via the "player" group when no target is assigned yet.
func acquire_target() -> void:
	if target == null:
		target = get_tree().get_first_node_in_group("player") as Node3D


## World-space center of the enemy's body capsule (the point a weapon strikes).
func hit_center() -> Vector3:
	var shape_node := get_node_or_null("CollisionShape3D") as CollisionShape3D
	var local := shape_node.position if shape_node != null else Vector3(0.0, 0.8, 0.0)
	return global_transform * local


## Applies `amount` damage from a strike originating at `source_position`:
## health is reduced (clamped at zero), the enemy is pushed away from the
## source at knockback_speed, and at zero health it dies. No-op when dead or
## when the amount is not positive.
func take_damage(amount: float, source_position: Vector3) -> void:
	if not alive or amount <= 0.0:
		return
	health = maxf(0.0, health - amount)
	var push := Vector3(global_position.x - source_position.x, 0.0, global_position.z - source_position.z)
	if not push.is_zero_approx():
		var direction := push.normalized()
		_last_hit_direction = direction
		velocity.x = direction.x * knockback_speed
		velocity.z = direction.z * knockback_speed
	_update_health_bar()
	if health <= 0.0:
		die()


## Kills the enemy: it stops chasing and tips over onto its side, away from
## the last strike, easing to the lying pose over death_fall_duration seconds.
func die() -> void:
	if not alive:
		return
	alive = false
	_death_time = 0.0
	_death_start_basis = basis
	var push := _last_hit_direction
	if push.is_zero_approx():
		push = Vector3.RIGHT
	var local_push := basis.inverse() * push
	if local_push.is_zero_approx():
		local_push = Vector3.RIGHT
	# rotate about the horizontal axis perpendicular to the hit so the top of
	# the model tips toward the push direction and it lands on its side
	var axis := Vector3.UP.cross(local_push.normalized())
	_death_target_basis = basis * Basis(axis, PI / 2.0)
	_update_health_bar() # hides the bar


## Eases the body from the pose at death toward the lying-down pose.
func _advance_death_fall(delta: float) -> void:
	_death_time += delta
	var t := 1.0
	if death_fall_duration > 0.0:
		t = clampf(_death_time / death_fall_duration, 0.0, 1.0)
	var eased := t * t * (3.0 - 2.0 * t) # smoothstep
	basis = _death_start_basis.slerp(_death_target_basis, eased)


## Shows the health bar over the enemy's head while it is alive and scales the
## fill quad to the current health fraction, anchored at the bar's left edge.
func _update_health_bar() -> void:
	var bar := get_node_or_null("Placeholder_HealthBar") as Node3D
	if bar == null:
		return
	bar.visible = alive
	var fill := bar.get_node_or_null("Placeholder_HealthBarFill") as MeshInstance3D
	if fill == null:
		return
	var width := 1.0
	if fill.mesh is QuadMesh:
		width = (fill.mesh as QuadMesh).size.x
	var fraction := health_fraction(health, max_health)
	fill.scale.x = fraction
	fill.position.x = -width * 0.5 * (1.0 - fraction)
