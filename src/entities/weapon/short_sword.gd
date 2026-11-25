class_name ShortSword
extends Node3D

## Height above the ground at which the sword hovers while floating.
@export var hover_height: float = 1.2
## How far the sword bobs above and below hover_height, in meters.
@export var bob_amplitude: float = 0.25
## Bobbing angular speed in radians per second.
@export var bob_speed: float = 2.0

## Elapsed time since the sword started bobbing.
var _bob_time: float = 0.0


## Vertical bob offset for a given time: a sine wave of the given amplitude
## and angular speed. Pure function so it stays unit-testable.
static func bob_offset(time: float, amplitude: float, speed: float) -> float:
	return amplitude * sin(speed * time)


func _ready() -> void:
	position.y = hover_height + bob_offset(_bob_time, bob_amplitude, bob_speed)


func _process(delta: float) -> void:
	_bob_time += delta
	position.y = hover_height + bob_offset(_bob_time, bob_amplitude, bob_speed)
