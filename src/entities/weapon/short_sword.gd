class_name ShortSword
extends Node3D

## Height above the ground at which the sword hovers while floating.
@export var hover_height: float = 1.2
## How far the sword bobs above and below hover_height, in meters.
@export var bob_amplitude: float = 0.25
## Bobbing angular speed in radians per second.
@export var bob_speed: float = 2.0
## How far the sword leans off vertical, in radians — a slight diagonal tilt,
## like one sword of a crossed pair in front of a shield.
@export var tilt_angle: float = 0.4
## Spin angular speed around the vertical axis, in radians per second.
@export var spin_speed: float = 0.6
## Distance in meters at which a player walking over the sword picks it up.
@export var pickup_radius: float = 1.5
## Local position of the sword's grip (hilt) relative to the holder when
## equipped — beside the body at hand height, slightly forward.
@export var equipped_position: Vector3 = Vector3(0.55, 1.05, 0.15)
## Local rotation when equipped: blade up and leaning slightly forward (+Z is
## the holder's facing direction), as if readied for combat. The placeholder
## parts lie along +X, so +90 degrees about Z points the blade along +Y.
@export var equipped_rotation: Vector3 = Vector3(0.35, 0.0, PI / 2.0)

## Elapsed time since the sword started bobbing.
var _bob_time: float = 0.0
## Elapsed time since the sword started spinning.
var _spin_time: float = 0.0
## True once the sword has been picked up and equipped.
var equipped: bool = false
## The node holding the sword. Acquired from the "player" group when unset.
var holder: Node3D = null


## Vertical bob offset for a given time: a sine wave of the given amplitude
## and angular speed. Pure function so it stays unit-testable.
static func bob_offset(time: float, amplitude: float, speed: float) -> float:
	return amplitude * sin(speed * time)


## Euler rotation that stands the sword upright (the placeholder parts are laid
## out along +X, so +90 degrees about Z points the blade along +Y), leans it
## `tilt` radians off vertical, and spins it `spin` radians around the vertical
## axis. Pure function so it stays unit-testable.
static func sword_rotation(spin: float, tilt: float) -> Vector3:
	return Vector3(0.0, spin, PI / 2.0 - tilt)


## True when `to` lies within `radius` meters of `from`. Pure function so it stays unit-testable.
static func is_within_pickup(from: Vector3, to: Vector3, radius: float) -> bool:
	return from.distance_to(to) <= radius


func _ready() -> void:
	position.y = hover_height + bob_offset(_bob_time, bob_amplitude, bob_speed)
	rotation = sword_rotation(_spin_time * spin_speed, tilt_angle)


func _process(delta: float) -> void:
	if equipped:
		return
	_bob_time += delta
	_spin_time += delta
	position.y = hover_height + bob_offset(_bob_time, bob_amplitude, bob_speed)
	rotation = sword_rotation(_spin_time * spin_speed, tilt_angle)


func _physics_process(_delta: float) -> void:
	if equipped:
		return
	acquire_holder()
	if holder != null and is_instance_valid(holder) and is_within_pickup(global_position, holder.global_position, pickup_radius):
		equip(holder)


## Finds the player via the "player" group when no holder is assigned yet.
func acquire_holder() -> void:
	if holder == null:
		holder = get_tree().get_first_node_in_group("player") as Node3D


## Attaches the sword to `new_holder` at the equipped grip pose: the hilt sits
## where the hand would be and the blade points up, readied for combat.
func equip(new_holder: Node3D) -> void:
	equipped = true
	holder = new_holder
	reparent(new_holder)
	position = equipped_position
	rotation = equipped_rotation
