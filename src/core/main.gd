class_name Main
extends Node3D

## World-space offset of the camera from the player. Negative Z puts the
## camera behind the character's facing direction (+Z), looking at its back.
@export var camera_offset: Vector3 = Vector3(0, 10.5, -6)
## Fixed world-space orientation of the camera (top-down pitch, yawed 180
## degrees so it looks along +Z from behind the player).
## The camera deliberately does NOT rotate with the player, so movement can be
## tested independent of the view. Camera rotation via keys can be added later.
@export var camera_rotation: Vector3 = Vector3(-1.1257, PI, 0)
## Whether the discrete FPS counter is shown in the top-left corner.
@export var show_fps: bool = true

@onready var player: Player = $Player
@onready var camera: Camera3D = $Camera3D
@onready var fps_label: Label = $UI/FPSLabel

## Side length of one checkerboard tile on the placeholder ground grid.
const GROUND_TILE_SIZE := 2.0
## Slight lift so the grid tiles sit above the ground plane without z-fighting.
const GROUND_TILE_LIFT := 0.02
const GROUND_TILE_COLOR_A := Color(0.27, 0.4, 0.25)
const GROUND_TILE_COLOR_B := Color(0.34, 0.5, 0.33)


func _ready() -> void:
	build_placeholder_ground_grid()


func _process(_delta: float) -> void:
	follow_player()
	set_fps_display(Engine.get_frames_per_second())


## Locks the camera to the player's position while keeping its orientation fixed.
func follow_player() -> void:
	camera.global_position = player.global_position + camera_offset
	camera.rotation = camera_rotation


## Overlays the flat ground plane with a checkerboard of placeholder tiles so
## player movement stays visible from the fixed camera. Tiles use only the
## built-in PlaneMesh and flat-color materials; every tile is named with the
## Placeholder_ prefix and tracked in the ai_placeholder group.
func build_placeholder_ground_grid() -> void:
	var ground_mesh: MeshInstance3D = $Placeholder_Ground/Placeholder_GroundMesh
	var ground_size: Vector2 = (ground_mesh.mesh as PlaneMesh).size
	var tile_mesh := PlaneMesh.new()
	tile_mesh.size = Vector2(GROUND_TILE_SIZE, GROUND_TILE_SIZE)
	var material_a := StandardMaterial3D.new()
	material_a.albedo_color = GROUND_TILE_COLOR_A
	var material_b := StandardMaterial3D.new()
	material_b.albedo_color = GROUND_TILE_COLOR_B
	var grid := Node3D.new()
	grid.name = "Placeholder_GroundGrid"
	grid.add_to_group("ai_placeholder")
	add_child(grid)
	var count_x := int(ground_size.x / GROUND_TILE_SIZE)
	var count_z := int(ground_size.y / GROUND_TILE_SIZE)
	for ix in count_x:
		for iz in count_z:
			var tile := MeshInstance3D.new()
			tile.name = "Placeholder_Tile_%d_%d" % [ix, iz]
			tile.add_to_group("ai_placeholder")
			tile.mesh = tile_mesh
			tile.position = Vector3(
				-ground_size.x / 2.0 + (ix + 0.5) * GROUND_TILE_SIZE,
				GROUND_TILE_LIFT,
				-ground_size.y / 2.0 + (iz + 0.5) * GROUND_TILE_SIZE
			)
			tile.material_override = material_a if (ix + iz) % 2 == 0 else material_b
			grid.add_child(tile)


## Formats a raw FPS value as a discrete integer readout, e.g. "60 FPS".
## Pure function so it stays unit-testable.
static func format_fps(fps: float) -> String:
	return "%d FPS" % int(round(fps))


## Updates the on-screen FPS label from a raw FPS value.
func set_fps_display(fps: float) -> void:
	fps_label.visible = show_fps
	fps_label.text = format_fps(fps)
