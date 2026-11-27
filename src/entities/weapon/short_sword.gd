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
## facing direction), as if readied for combat. Applied to the holder's
## RightHand node, which carries the grip pose while the sword is equipped.
@export var equipped_lean: float = 0.35
## Total angle in radians the hand sweeps around the holder during a swing.
## Applied with positive sign so the arc covers the front of the holder's
## facing direction: the RightHand sits on the holder's right (-X), and a
## positive yaw sweeps -X toward +Z.
@export var swing_angle: float = deg_to_rad(160.0)
## Duration of one swing in seconds — another 1.2x faster than the previous 0.35 / 1.2 s.
@export var swing_duration: float = 0.35 / 1.2 / 1.2

## Elapsed time since the sword started bobbing.
var _bob_time: float = 0.0
## Elapsed time since the sword started spinning.
var _spin_time: float = 0.0
## True once the sword has been picked up and equipped.
var equipped: bool = false
## The node holding the sword. Acquired from the "player" group when unset.
var holder: Node3D = null
## Child node carrying the sword's own orientation (loot pose only; the grip
## pose is carried by the holder's RightHand node when equipped); null when the
## script runs without the placeholder scene.
var _pivot: Node3D = null
## Elapsed time of the current swing in seconds; negative when not swinging.
var _swing_time: float = -1.0
## The holder's SwingPivot node (origin at the holder's center). The swing
## rotates this node, not the RightHand, so the hand orbits the holder at a
## constant distance while its grip pose stays independent of the swing.
var _swing_pivot: Node3D = null


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
## long axis so it reads correctly in the hand. Applied to the holder's
## RightHand node on equip. Pure function so it stays unit-testable.
static func equipped_basis(forward_lean: float) -> Basis:
	return Basis(Vector3(1, 0, 0), forward_lean) * Basis(Vector3(0, 0, 1), PI / 2.0)


## Basis for the holder's RightHand node: while a swing is playing the hand is
## yawed 180 degrees about vertical so the blade lies flat and points outward
## from the right hand (-X), sweeping forward as the pivot yaws; otherwise the
## equipped grip pose applies. Pure function so it stays unit-testable.
static func hand_pose_basis(swinging: bool, forward_lean: float) -> Basis:
	if swinging:
		return Basis(Vector3.UP, PI)
	return equipped_basis(forward_lean)


## Smoothstep easing in [0, 1]: 0 at 0, 1 at 1, with zero slope at both ends,
## so a swing eases in and out. Pure function so it stays unit-testable.
static func ease_smoothstep(t: float) -> float:
	var x := clampf(t, 0.0, 1.0)
	return x * x * (3.0 - 2.0 * x)


## Angle swept by the swing pivot `time` seconds into a swing of `duration`
## seconds and `total_angle` radians: smoothstep-eased, clamped to the full
## angle once the swing is over. Pure function so it stays unit-testable.
static func swing_angle_at(time: float, duration: float, total_angle: float) -> float:
	if duration <= 0.0:
		return total_angle
	return ease_smoothstep(time / duration) * total_angle


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
		_process_equipped(delta)
		return
	_bob_time += delta
	_spin_time += delta
	position.y = hover_height + bob_offset(_bob_time, bob_amplitude, bob_speed)
	rotation = Vector3(0.0, _spin_time * spin_speed, 0.0) # slow spin around the vertical axis


func _unhandled_input(event: InputEvent) -> void:
	var mouse := event as InputEventMouseButton
	if mouse != null and mouse.pressed and mouse.button_index == MOUSE_BUTTON_LEFT:
		if start_swing():
			aim_holder_at(mouse.position)


## Points the holder's facing at the clicked screen position (projected onto
## the ground plane) so the swing goes toward the click, not the direction of
## travel. Only called when a swing actually started, so the facing lock is
## always paired with a swing that will release it.
func aim_holder_at(screen_pos: Vector2) -> void:
	if holder == null or not is_instance_valid(holder):
		return
	if holder is Player:
		(holder as Player).face_toward_screen_position(screen_pos)


## Releases the holder's attack-facing lock now that the swing is over.
func release_holder_facing() -> void:
	if holder != null and is_instance_valid(holder) and holder is Player:
		(holder as Player).release_attack_facing()


## Advances the swing if one is playing, then keeps the holder's RightHand node in
## the pose for the current state: yawed 180 degrees (blade flat, pointing
## outward) while swinging, the equipped grip pose otherwise.
func _process_equipped(delta: float) -> void:
	if _swing_time >= 0.0:
		_swing_time += delta
		if _swing_time >= swing_duration:
			_swing_time = -1.0
			if is_instance_valid(_swing_pivot):
				_swing_pivot.rotation = Vector3.ZERO # swing over: pivot back to rest
			release_holder_facing() # swing over: facing follows travel again
		elif is_instance_valid(_swing_pivot):
			# positive sign: the RightHand sits at -X, so positive rotation.y sweeps it toward +Z (the front)
			_swing_pivot.rotation.y = swing_angle_at(_swing_time, swing_duration, swing_angle)
	_update_hand_pose(_swing_time >= 0.0)


## Initiates a swing: the hand is yawed 180 degrees (blade flat, pointing
## outward from the right hand) and the holder's
## SwingPivot sweeps `swing_angle` radians around the holder over
## `swing_duration` seconds, carrying the hand at a constant distance from the
## holder's center. Returns true when a swing started; false when the sword is
## not equipped or the holder has no SwingPivot (no swing, no facing change).
func start_swing() -> bool:
	if not equipped or holder == null or not is_instance_valid(holder):
		return false
	_swing_pivot = holder.get_node_or_null("SwingPivot") as Node3D
	if _swing_pivot == null:
		return false
	_swing_time = 0.0
	return true


## Keeps the holder's RightHand node in the pose for the current swing state.
func _update_hand_pose(swinging: bool) -> void:
	if holder == null or not is_instance_valid(holder):
		return
	var hand := holder.get_node_or_null("SwingPivot/RightHand") as Node3D
	if hand == null:
		return
	hand.basis = hand_pose_basis(swinging, equipped_lean)


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


## Attaches the sword to the holder's RightHand node: the right hand (positioned
## at design time in the player scene, under the SwingPivot) is rotated into the equipped
## grip pose, and the sword is parented to it with an identity local transform
## so the hilt sits exactly at the hand. The hand — not the sword — carries the
## grip orientation; a swing rotates the holder's SwingPivot around the holder's
## center instead.
func equip(new_holder: Node3D) -> void:
	equipped = true
	holder = new_holder
	_swing_pivot = new_holder.get_node_or_null("SwingPivot") as Node3D
	var hand := new_holder.get_node_or_null("SwingPivot/RightHand") as Node3D
	if hand == null:
		push_warning("ShortSword.equip: holder has no SwingPivot/RightHand node, attaching at the holder's origin.")
		reparent(new_holder)
	else:
		hand.basis = equipped_basis(equipped_lean) # the hand takes the grip pose
		reparent(hand)
	transform = Transform3D.IDENTITY # hilt sits exactly at the hand
	if _pivot == null:
		_pivot = get_node_or_null("Placeholder_SwordPivot") as Node3D
	if _pivot != null:
		_pivot.basis = Basis.IDENTITY # the hand carries the grip orientation, not the sword

