extends CharacterBody3D
## PlayerController — first person movement, look, and the two "meta" verbs the
## office needs: interact (delegated to InteractionSystem) and photograph
## (delegated to PhotoSystem). No game rules live here.

signal footstep()
signal landed(impact: float)

@export_group("Movement")
@export var speed: float = 3.1
@export var sprint_multiplier: float = 1.45
@export var acceleration: float = 12.0
@export var deceleration: float = 16.0
@export var jump_velocity: float = 4.6
@export var air_control: float = 0.35
@export var mouse_sensitivity: float = 0.002
@export var max_pitch_deg: float = 89.0

@export_group("Camera")
@export var default_fov: float = 75.0
@export var head_bob_enabled: bool = true
@export var head_bob_amount: float = 0.035
@export var head_bob_frequency: float = 9.0

@export_group("Flashlight")
@export var flashlight_energy: float = 2.4
@export var flashlight_range: float = 9.0
@export var flashlight_angle: float = 26.0
@export var flashlight_start_on: bool = false

@export_group("Feedback")
@export var footstep_interval: float = 0.42
@export var landing_shake: float = 0.15

@onready var head: Node3D = $Head
@onready var camera: Camera3D = $Head/Camera3D
@onready var flashlight: SpotLight3D = $Head/Flashlight

var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity", 9.8)
var mobile_input: Vector2 = Vector2.ZERO
var look_delta: Vector2 = Vector2.ZERO
var jump_requested: bool = false
var freeze_input: bool = false

var _bob_phase: float = 0.0
var _step_timer: float = 0.0
var _base_fov: float = 75.0
var _fov_scale: float = 1.0
var _look_scale: float = 1.0
var _invert_y: bool = false
var _was_on_floor: bool = true
var _flashlight_on: bool = false
## Monitor framing: bounds cached for as long as the player is seated, the world
## point the eye is pinned on, and whether the pin is active at all.
var _computer_bounds := {}
var _computer_focus := Vector3.ZERO
var _computer_view_active := false


func _ready() -> void:
	add_to_group("player")
	_base_fov = default_fov
	_apply_fov()
	camera.current = true
	GameManager.register_player(self)
	Settings.settings_changed.connect(_apply_settings)
	_apply_settings()
	_was_on_floor = is_on_floor()
	_set_flashlight(flashlight_start_on)
	ComputerSystem.entered.connect(_on_computer_entered)
	ComputerSystem.exited.connect(_on_computer_exited)


func _apply_settings() -> void:
	mouse_sensitivity = float(Settings.get_value("mouse_sensitivity", mouse_sensitivity))
	head_bob_enabled = bool(Settings.get_value("head_bob_enabled", true))
	_invert_y = bool(Settings.get_value("invert_y", false))
	_base_fov = float(Settings.get_value("fov", default_fov))
	_apply_fov()


func _apply_fov() -> void:
	if camera:
		camera.fov = _base_fov * _fov_scale


## Used by CameraSystem while the viewfinder is raised.
func set_fov_scale(value: float) -> void:
	_fov_scale = clampf(value, 0.3, 1.0)
	_apply_fov()


## A raised viewfinder steadies the aim instead of making it twitchy.
func set_look_scale(value: float) -> void:
	_look_scale = clampf(value, 0.1, 1.0)


# --- computer view -----------------------------------------------------------
#
# Sitting down has to land the eye on the monitor. With the aim left where it
# was, the view swings past the quad, the desktop shows up as a thin strip along
# one edge and the text reads as unreadable speckle - which is what "the screen
# is too small" actually is. Frame the screen on enter, widen back out on leave.

func _on_computer_entered(computer: Node3D) -> void:
	if head == null or not is_instance_valid(computer):
		return
	if not computer.has_method("get_screen_bounds"):
		return
	_computer_bounds = computer.call("get_screen_bounds") as Dictionary
	_computer_focus = _computer_bounds.get("center", computer.global_position) as Vector3
	_computer_view_active = true
	_frame_monitor()


func _on_computer_exited() -> void:
	_computer_view_active = false
	_computer_bounds = {}
	set_fov_scale(1.0)


## Pin the eye on the monitor on every frame rather than once on entry, and keep
## the framing honest while doing it. The player can still be settling into the
## chair when `entered` fires, so an aim taken at that instant is measured from a
## head that is about to drop, and the view it leaves behind points at the floor;
## the same settling moves the eye close enough that a FOV solved once comes out
## too wide and shaves the right edge off the desktop. The bounds are read once,
## only the arithmetic is repeated, and the camera is touched only when the
## answer actually moves.
func _frame_monitor() -> void:
	if not _computer_view_active or head == null:
		return
	head.look_at(_computer_focus, Vector3.UP)
	var wanted := _fit_fov_scale(_computer_focus, _computer_bounds)
	if not is_equal_approx(wanted, _fov_scale):
		set_fov_scale(wanted)


## Narrow the FOV just far enough to hold the quad plus a margin at the distance
## the player is actually sitting at, so the whole desktop lands inside the frame
## and is drawn as large as the framing allows. Never widens past the base FOV:
## a monitor seen from across the room is better walked up to than zoomed out
## for, and a zoom would make the text smaller, not larger.
func _fit_fov_scale(center: Vector3, bounds: Dictionary) -> float:
	var dist := maxf(head.global_position.distance_to(center), 0.5)
	var margin := 1.1
	var half_u := float(bounds.get("half_u", 0.6)) * margin
	var half_v := float(bounds.get("half_v", 0.4)) * margin
	# Godot's FOV is vertical: the vertical axis binds directly, while the
	# horizontal axis has to be converted through the viewport aspect first.
	var needed := 2.0 * atan(half_v / dist)
	needed = maxf(needed, 2.0 * atan(half_u / dist / maxf(_viewport_aspect(), 0.1)))
	# `atan` yields radians and `default_fov` is exported in degrees; dividing one
	# by the other directly collapses to the clamp floor and zooms all the way in.
	return clampf(rad_to_deg(needed) / maxf(_base_fov, 1.0), 0.3, 1.0)


func _viewport_aspect() -> float:
	var vp := get_viewport()
	if vp == null:
		return 1.0
	var size := vp.get_visible_rect().size
	if size.y <= 0.0:
		return 1.0
	return size.x / size.y


# --- flashlight --------------------------------------------------------------

func is_flashlight_on() -> bool:
	return _flashlight_on


func toggle_flashlight() -> void:
	_set_flashlight(not _flashlight_on)


func _set_flashlight(value: bool) -> void:
	_flashlight_on = value and flashlight != null
	if flashlight != null:
		flashlight.visible = _flashlight_on
	AudioManager.play_sfx("click", -14.0, 0.6)


# --- input ------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if not GameManager.is_exploring() or freeze_input:
		return
	if event is InputEventMouseMotion and not _is_mobile():
		var relative: Vector2 = (event as InputEventMouseMotion).relative * _look_scale
		relative.y = -relative.y if _invert_y else relative.y
		look_delta += relative * mouse_sensitivity
	if event.is_action_pressed("jump"):
		jump_requested = true
	if event.is_action_pressed("flashlight"):
		toggle_flashlight()


func apply_look(delta: Vector2) -> void:
	if delta == Vector2.ZERO:
		return
	rotate_y(-delta.x)
	head.rotate_x(-delta.y)
	var limit := deg_to_rad(max_pitch_deg)
	head.rotation.x = clampf(head.rotation.x, -limit, limit)


func _physics_process(delta: float) -> void:
	apply_look(look_delta)
	look_delta = Vector2.ZERO
	_frame_monitor()

	if not is_on_floor():
		velocity.y -= gravity * delta
	elif velocity.y < 0.0:
		velocity.y = 0.0

	if not GameManager.is_exploring() or freeze_input:
		_decelerate(delta)
		move_and_slide()
		_update_bob(delta, 0.0)
		return

	if jump_requested and is_on_floor():
		velocity.y = jump_velocity
		AudioManager.play_sfx("blip", -20.0, 0.7)
	jump_requested = false

	var input_dir := _gather_input()
	var wish := (transform.basis * Vector3(input_dir.x, 0.0, input_dir.y))
	wish.y = 0.0
	if wish.length_squared() > 1.0:
		wish = wish.normalized()
	var target_speed := speed
	if Input.is_action_pressed("move_forward") and Input.is_key_pressed(KEY_SHIFT):
		target_speed *= sprint_multiplier
	var target := wish * target_speed

	var rate := acceleration if wish.length_squared() > 0.0 else deceleration
	if not is_on_floor():
		rate *= air_control
	velocity.x = move_toward(velocity.x, target.x, rate * delta)
	velocity.z = move_toward(velocity.z, target.z, rate * delta)

	move_and_slide()
	_update_footsteps(delta, Vector2(velocity.x, velocity.z).length())
	_update_bob(delta, Vector2(velocity.x, velocity.z).length())

	if not _was_on_floor and is_on_floor():
		var impact := absf(velocity.y)
		landed.emit(impact)
		HorrorSystem.shake(landing_shake, 0.18)
		AudioManager.play_sfx("noise", -22.0, 0.8)
	_was_on_floor = is_on_floor()


func _decelerate(delta: float) -> void:
	velocity.x = move_toward(velocity.x, 0.0, deceleration * delta)
	velocity.z = move_toward(velocity.z, 0.0, deceleration * delta)


func _gather_input() -> Vector2:
	if _is_mobile():
		return mobile_input.limit_length(1.0)
	return Input.get_vector("move_left", "move_right", "move_forward", "move_backward")


func _update_footsteps(delta: float, horizontal_speed: float) -> void:
	if not is_on_floor() or horizontal_speed < 0.6:
		_step_timer = footstep_interval
		return
	_step_timer -= delta
	if _step_timer <= 0.0:
		_step_timer = footstep_interval * (speed / maxf(horizontal_speed, 0.01))
		footstep.emit()
		AudioManager.play_3d("noise", global_position, -26.0, randf_range(0.8, 1.2))


func _update_bob(delta: float, horizontal_speed: float) -> void:
	var target := Vector3.ZERO
	if head_bob_enabled and GameManager.is_exploring() and is_on_floor() and horizontal_speed > 0.6:
		_bob_phase += delta * head_bob_frequency * clampf(horizontal_speed / speed, 0.4, 1.6)
		target.y = sin(_bob_phase) * head_bob_amount * clampf(horizontal_speed / speed, 0.2, 1.0)
		target.x = cos(_bob_phase * 0.5) * head_bob_amount * 0.5
	var shake := HorrorSystem.get_shake_offset()
	target.x += shake.x * 0.02
	target.y += shake.y * 0.02
	head.position = head.position.lerp(Vector3(0.0, 1.62, 0.0) + target, clampf(delta * 12.0, 0.0, 1.0))
	camera.rotation.z = lerpf(camera.rotation.z, shake.x * 0.01, clampf(delta * 8.0, 0.0, 1.0))


func request_jump() -> void:
	jump_requested = true


func teleport(to: Vector3, yaw: float = NAN) -> void:
	velocity = Vector3.ZERO
	global_position = to
	if not is_nan(yaw):
		rotation.y = yaw
	head.rotation.x = 0.0


func is_mobile() -> bool:
	return _is_mobile()


func _is_mobile() -> bool:
	return OS.has_feature("mobile") or OS.has_feature("android") or OS.has_feature("ios")
