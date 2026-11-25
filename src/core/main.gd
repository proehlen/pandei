class_name Main
extends Node3D

## World-space offset of the camera from the player.
@export var camera_offset: Vector3 = Vector3(0, 10.5, 6)
## Fixed world-space orientation of the camera (top-down pitch, no yaw).
## The camera deliberately does NOT rotate with the player, so movement can be
## tested independent of the view. Camera rotation via keys can be added later.
@export var camera_rotation: Vector3 = Vector3(-1.0472, 0, 0)
## Whether the discrete FPS counter is shown in the top-left corner.
@export var show_fps: bool = true

@onready var player: Player = $Player
@onready var camera: Camera3D = $Camera3D
@onready var fps_label: Label = $UI/FPSLabel


func _process(_delta: float) -> void:
	follow_player()
	set_fps_display(Engine.get_frames_per_second())


## Locks the camera to the player's position while keeping its orientation fixed.
func follow_player() -> void:
	camera.global_position = player.global_position + camera_offset
	camera.rotation = camera_rotation


## Formats a raw FPS value as a discrete integer readout, e.g. "60 FPS".
## Pure function so it stays unit-testable.
static func format_fps(fps: float) -> String:
	return "%d FPS" % int(round(fps))


## Updates the on-screen FPS label from a raw FPS value.
func set_fps_display(fps: float) -> void:
	fps_label.visible = show_fps
	fps_label.text = format_fps(fps)
