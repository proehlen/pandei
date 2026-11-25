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

## Elapsed time since the sword started bobbing.
var _bob_time: float = 0.0
## Elapsed time since the sword started spinning.
var _spin_time: float = 0.0


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


func _ready() -> void:
	position.y = hover_height + bob_offset(_bob_time, bob_amplitude, bob_speed)
	rotation = sword_rotation(_spin_time * spin_speed, tilt_angle)


func _process(delta: float) -> void:
	_bob_time += delta
	_spin_time += delta
	position.y = hover_height + bob_offset(_bob_time, bob_amplitude, bob_speed)
	rotation = sword_rotation(_spin_time * spin_speed, tilt_angle)
