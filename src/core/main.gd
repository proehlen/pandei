class_name Main
extends Node3D

## World-space offset of the camera from the player.
@export var camera_offset: Vector3 = Vector3(0, 14, 8)
## Fixed world-space orientation of the camera (top-down pitch, no yaw).
## The camera deliberately does NOT rotate with the player, so movement can be
## tested independent of the view. Camera rotation via keys can be added later.
@export var camera_rotation: Vector3 = Vector3(-1.0472, 0, 0)

@onready var player: Player = $Player
@onready var camera: Camera3D = $Camera3D


func _process(_delta: float) -> void:
	follow_player()


## Locks the camera to the player's position while keeping its orientation fixed.
func follow_player() -> void:
	camera.global_position = player.global_position + camera_offset
	camera.rotation = camera_rotation
