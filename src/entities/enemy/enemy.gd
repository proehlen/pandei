class_name Enemy
extends CharacterBody3D

## Distance in meters at which the enemy spots the player and starts chasing.
@export var detection_radius: float = 15.0
## Chase speed in meters per second. main.gd syncs this to the player's
## move_speed so the enemy chases at exactly the player's max speed.
@export var move_speed: float = 6.0
## Gravity applied while airborne so the enemy stays grounded.
@export var gravity: float = 20.0
## How quickly the enemy turns to face the player (radians per second).
@export var turn_speed: float = 12.0

## The node the enemy chases. Acquired from the "player" group when unset.
var target: Node3D = null


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


func _ready() -> void:
	acquire_target()


func _physics_process(delta: float) -> void:
	acquire_target()
	var chase := compute_chase_velocity()
	velocity.x = chase.x
	velocity.z = chase.z
	if not chase.is_zero_approx():
		rotation.y = lerp_angle(rotation.y, atan2(chase.x, chase.z), clampf(turn_speed * delta, 0.0, 1.0))
	if not is_on_floor():
		velocity.y -= gravity * delta
	move_and_slide()


## Horizontal velocity toward the target while it is within detection_radius, else zero.
func compute_chase_velocity() -> Vector3:
	if target == null or not is_instance_valid(target):
		return Vector3.ZERO
	if not is_within_detection(global_position, target.global_position, detection_radius):
		return Vector3.ZERO
	return chase_velocity(global_position, target.global_position, move_speed)


## Finds the player via the "player" group when no target is assigned yet.
func acquire_target() -> void:
	if target == null:
		target = get_tree().get_first_node_in_group("player") as Node3D
