class_name Player
extends CharacterBody3D

## Top-down movement speed in meters per second.
@export var move_speed: float = 6.0
## Gravity applied while airborne so the character stays grounded.
@export var gravity: float = 20.0
## How quickly the character turns to face its movement direction (radians per second).
@export var turn_speed: float = 12.0

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

## Yaw of the viewport's active camera, making WASD camera-relative: W moves in
## the direction the camera looks, A to the camera's left. Returns 0 when the
## viewport has no camera.
func _camera_yaw() -> float:
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return 0.0
	return camera.global_rotation.y


func _physics_process(delta: float) -> void:
	var input := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	var camera_yaw := _camera_yaw()
	var horizontal := input_to_velocity(input, move_speed, camera_yaw)
	velocity.x = horizontal.x
	velocity.z = horizontal.z
	if not is_on_floor():
		velocity.y -= gravity * delta
	move_and_slide()
	var direction := input_to_direction(input, camera_yaw)
	if not direction.is_zero_approx():
		rotation.y = lerp_angle(rotation.y, atan2(direction.x, direction.z), clampf(turn_speed * delta, 0.0, 1.0))
