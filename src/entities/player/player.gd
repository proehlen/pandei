class_name Player
extends CharacterBody3D

## Top-down movement speed in meters per second.
@export var move_speed: float = 6.0
## Horizontal acceleration in m/s^2 used to ease in/out of movement. At the
## defaults this reaches move_speed in ~0.2 s, keeping the ramp subtle.
@export var acceleration: float = 30.0
## Gravity applied while airborne so the character stays grounded.
@export var gravity: float = 20.0
## How quickly the character turns toward its facing target (radians per second):
## the movement direction, or the attack-clicked direction while a swing lock is active.
@export var turn_speed: float = 12.0

## Yaw (radians) the player is locked to face while an attack swing plays, taken
## from the clicked screen position; NAN when no lock is active and facing
## follows the movement direction while moving.
var _attack_facing_yaw: float = NAN

## Maps a 2D input vector (x = left/right, y = up/down) to a normalized
## world-space direction on the XZ plane, rotated by `camera_yaw` radians so the
## input is camera-relative: W (0, -1) moves along the direction the camera
## looks, A (-1, 0) to the camera's left. With yaw 0 this is the raw mapping
## Vector3(input.x, 0, input.y). Pure function so it stays unit-testable.
static func input_to_direction(input: Vector2, camera_yaw: float = 0.0) -> Vector3:
	if input.is_zero_approx():
		return Vector3.ZERO
	return Vector3(input.x, 0.0, input.y).rotated(Vector3.UP, camera_yaw).normalized()

## Horizontal velocity for a given input vector and speed, rotated by
## `camera_yaw` like input_to_direction (y stays 0; gravity is applied
## separately in _physics_process).
static func input_to_velocity(input: Vector2, speed: float, camera_yaw: float = 0.0) -> Vector3:
	var direction := input_to_direction(input, camera_yaw)
	return Vector3(direction.x * speed, 0.0, direction.z * speed)

## Horizontal velocity after easing `current` toward `target` by at most
## `acceleration * delta` meters. Pure function so it stays unit-testable.
static func ease_velocity(current: Vector3, target: Vector3, acceleration: float, delta: float) -> Vector3:
	return current.move_toward(target, acceleration * delta)

## Horizontal yaw from `from` to `to` on the XZ plane, matching the
## rotation.y = atan2(direction.x, direction.z) facing convention. Returns NAN
## when both points share the same XZ position (no defined direction). Pure
## function so it stays unit-testable.
static func yaw_toward(from: Vector3, to: Vector3) -> float:
	var delta := Vector3(to.x - from.x, 0.0, to.z - from.z)
	if delta.is_zero_approx():
		return NAN
	return atan2(delta.x, delta.z)

## True when the ray from `origin` along `direction` crosses the horizontal
## plane y = plane_y at a positive distance in front of the origin (not
## parallel, not behind the ray's origin). Pure function so it stays
## unit-testable.
static func ray_crosses_plane_ahead(origin: Vector3, direction: Vector3, plane_y: float) -> bool:
	if absf(direction.y) < 0.0001:
		return false
	return (plane_y - origin.y) / direction.y > 0.0

## World point where the ray from `origin` along `direction` crosses the
## horizontal plane y = plane_y. Only meaningful when ray_crosses_plane_ahead
## is true. Pure function so it stays unit-testable.
static func ray_plane_intersection(origin: Vector3, direction: Vector3, plane_y: float) -> Vector3:
	var t := (plane_y - origin.y) / direction.y
	return origin + direction * t

## Yaw of the viewport's active camera, making WASD camera-relative: W moves in
## the direction the camera looks, A to the camera's left. Returns 0 when the
## viewport has no camera.
func _camera_yaw() -> float:
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return 0.0
	return camera.global_rotation.y


## Projects a screen position (e.g. a mouse click) through the viewport's active
## camera onto the horizontal plane at the player's height and locks facing
## toward that world point, so an attack swings at what was clicked. Does
## nothing without a camera, when the click ray misses the plane, or when the
## clicked point sits exactly on the player (no defined direction).
func face_toward_screen_position(screen_pos: Vector2) -> void:
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return
	var origin := camera.project_ray_origin(screen_pos)
	var direction := camera.project_ray_normal(screen_pos)
	if not ray_crosses_plane_ahead(origin, direction, global_position.y):
		return
	var point := ray_plane_intersection(origin, direction, global_position.y)
	var yaw := yaw_toward(global_position, point)
	if not is_nan(yaw):
		_attack_facing_yaw = yaw


## Releases the attack-facing lock: facing follows the movement direction again
## while moving, and holds still when idle. Called by the equipped sword when
## a swing ends.
func release_attack_facing() -> void:
	_attack_facing_yaw = NAN


## True while an attack-facing lock is active and the player has not yet
## finished turning to face the clicked point. The equipped sword waits for
## this to clear before swinging, so the swing arc plays out in the final
## facing direction no matter which side the click is on.
func is_turning_to_attack_target() -> bool:
	if is_nan(_attack_facing_yaw):
		return false
	return absf(angle_difference(rotation.y, _attack_facing_yaw)) > 0.0001


func _physics_process(delta: float) -> void:
	var input := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	var camera_yaw := _camera_yaw()
	var desired := input_to_velocity(input, move_speed, camera_yaw)
	var horizontal := ease_velocity(Vector3(velocity.x, 0.0, velocity.z), desired, acceleration, delta)
	velocity.x = horizontal.x
	velocity.z = horizontal.z
	if not is_on_floor():
		velocity.y -= gravity * delta
	move_and_slide()
	var direction := input_to_direction(input, camera_yaw)
	var facing_target: float = NAN
	if not is_nan(_attack_facing_yaw):
		facing_target = _attack_facing_yaw # attack lock: turn toward the clicked point; movement is unaffected
	elif not direction.is_zero_approx():
		facing_target = atan2(direction.x, direction.z)
	if not is_nan(facing_target):
		var step := turn_speed * delta
		if absf(angle_difference(rotation.y, facing_target)) <= step:
			rotation.y = facing_target # within one frame's turn: settle exactly on the target
		else:
			rotation.y = lerp_angle(rotation.y, facing_target, clampf(step, 0.0, 1.0))
