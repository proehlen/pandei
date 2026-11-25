class_name ShortSword
extends Node3D

## Height above the ground at which the sword hovers while floating.
@export var hover_height: float = 1.2
## How far the sword bobs above and below hover_height, in meters.
@export var bob_amplitude: float = 0.25
## Bobbing angular speed in radians per second.
@export var bob_speed: float = 2.0
## How far the sword leans off vertical in the loot pose, in radians — a
## slight diagonal tilt, like one sword of a crossed pair in front of a shield.
@export var tilt_angle: float = 0.4
## Spin angular speed around the vertical axis, in radians per second.
@export var spin_speed: float = 0.6
## Distance in meters at which a player walking over the sword picks it up.
@export var pickup_radius: float = 1.5
## Forward lean of the blade in radians when equipped (+Z is the holder's
## facing direction), as if readied for combat. Applied to the holder's Hand
## node, which carries the grip pose while the sword is equipped.
@export var equipped_lean: float = 0.35

## Elapsed time since the sword started bobbing.
var _bob_time: float = 0.0
## Elapsed time since the sword started spinning.
var _spin_time: float = 0.0
## True once the sword has been picked up and equipped.
var equipped: bool = false
## The node holding the sword. Acquired from the "player" group when unset.
var holder: Node3D = null
## Child node carrying the sword's own orientation (loot pose only; the grip
## pose is carried by the holder's Hand node when equipped); null when the
## script runs without the placeholder scene.
var _pivot: Node3D = null


## Vertical bob offset for a given time: a sine wave of the given amplitude
## and angular speed. Pure function so it stays unit-testable.
static func bob_offset(time: float, amplitude: float, speed: float) -> float:
	return amplitude * sin(speed * time)


## Basis for the floating loot pose: stands the sword upright (the placeholder
## parts are laid out along +X, so +90 degrees about Z points the blade along
## +Y), leans it `tilt` radians off vertical, and rolls the blade -90 degrees
## about its long axis so its edge runs horizontally, like one sword of a
## crossed pair. Pure function so it stays unit-testable.
static func loot_basis(tilt: float) -> Basis:
	return Basis(Vector3(0, 0, 1), PI / 2.0 - tilt) * Basis(Vector3(1, 0, 0), -PI / 2.0)


## Basis for the equipped grip pose: blade up, leaning `forward_lean` radians
## toward the holder's facing direction (+Z), with no roll about the blade's
## long axis so it reads correctly in the hand. Applied to the holder's Hand
## node on equip. Pure function so it stays unit-testable.
static func equipped_basis(forward_lean: float) -> Basis:
	return Basis(Vector3(1, 0, 0), forward_lean) * Basis(Vector3(0, 0, 1), PI / 2.0)


## Basis for the holder's Hand node: while the attack button is held the
## rotation is reset to zero (the design-time pose); otherwise the equipped
## grip pose applies. Pure function so it stays unit-testable.
static func hand_pose_basis(button_held: bool, forward_lean: float) -> Basis:
	if button_held:
		return Basis.IDENTITY
	return equipped_basis(forward_lean)


## True when `to` lies within `radius` meters of `from`. Pure function so it stays unit-testable.
static func is_within_pickup(from: Vector3, to: Vector3, radius: float) -> bool:
	return from.distance_to(to) <= radius


func _ready() -> void:
	_pivot = get_node_or_null("Placeholder_SwordPivot") as Node3D
	if _pivot != null:
		_pivot.basis = loot_basis(tilt_angle)
	position.y = hover_height + bob_offset(_bob_time, bob_amplitude, bob_speed)
	rotation = Vector3(0.0, _spin_time * spin_speed, 0.0)


func _process(delta: float) -> void:
	if equipped:
		_update_hand_pose(Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT))
		return
	_bob_time += delta
	_spin_time += delta
	position.y = hover_height + bob_offset(_bob_time, bob_amplitude, bob_speed)
	rotation = Vector3(0.0, _spin_time * spin_speed, 0.0) # slow spin around the vertical axis


## Keeps the holder's Hand node in the pose for the current button state: the
## grip pose normally, reset to zero rotation while the attack button is held.
func _update_hand_pose(button_held: bool) -> void:
	if holder == null or not is_instance_valid(holder):
		return
	var hand := holder.get_node_or_null("Hand") as Node3D
	if hand == null:
		return
	hand.basis = hand_pose_basis(button_held, equipped_lean)


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


## Attaches the sword to the holder's Hand node: the hand (positioned at design
## time in the player scene) is rotated into the equipped grip pose, and the
## sword is parented to it with an identity local transform so the hilt sits
## exactly at the hand. The hand — not the sword — carries the grip orientation,
## so rotating the hand is what will drive a swing later.
func equip(new_holder: Node3D) -> void:
	equipped = true
	holder = new_holder
	var hand := new_holder.get_node_or_null("Hand") as Node3D
	if hand == null:
		push_warning("ShortSword.equip: holder has no Hand node, attaching at the holder's origin.")
		reparent(new_holder)
	else:
		hand.basis = equipped_basis(equipped_lean) # the hand takes the grip pose
		reparent(hand)
	transform = Transform3D.IDENTITY # hilt sits exactly at the hand
	if _pivot == null:
		_pivot = get_node_or_null("Placeholder_SwordPivot") as Node3D
	if _pivot != null:
		_pivot.basis = Basis.IDENTITY # the hand carries the grip orientation, not the sword

