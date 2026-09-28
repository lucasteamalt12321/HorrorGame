extends Control
## Touch controls for phones.
##
## The buttons do not re-implement gameplay: they inject the same InputMap
## actions the keyboard produces, so there is exactly one code path for
## interacting, photographing and pausing on every platform.

const EDGE_MARGIN := 32.0
const BUTTON_SIZE := 120.0
const BUTTON_GAP := 0.0

var touching_camera := false
var last_touch_pos := Vector2.ZERO
var joystick_touch_index := -1
var move_dir := Vector2.ZERO
var player: CharacterBody3D = null

@onready var joystick_base: Control = $JoystickBase
@onready var joystick_knob: Control = $JoystickBase/Knob
@onready var jump_button: Button = $JumpButton
@onready var photo_button: Button = $PhotoButton
@onready var interact_button: Button = $InteractButton
@onready var pause_button: Button = $PauseButton

var _buttons: Array[Button] = []


func _ready() -> void:
	_buttons = [jump_button, photo_button, interact_button, pause_button]
	# Mobile controls must never be visible or active on desktop.
	if not _is_mobile():
		visible = false
		process_mode = Node.PROCESS_MODE_DISABLED
		return

	jump_button.pressed.connect(_press_action.bind(&"jump"))
	interact_button.pressed.connect(_press_action.bind(&"interact"))
	photo_button.pressed.connect(_press_action.bind(&"photo"))
	# Esc is the only pause input the game actually reads, so the button uses it.
	pause_button.pressed.connect(_press_action.bind(&"ui_cancel"))
	get_viewport().size_changed.connect(_apply_safe_area)
	Settings.settings_changed.connect(_apply_toggle)
	_apply_toggle()
	_apply_safe_area()
	_reset_joystick()


## The panel exposes "Сенсорное управление", so the setting has to reach the
## controls instead of sitting in the config file.
func _apply_toggle() -> void:
	visible = bool(Settings.get_value("touch_controls", true))


func _is_mobile() -> bool:
	return GameManager.is_mobile()


# --- safe area --------------------------------------------------------------

## Keeps the controls clear of notches, punch-holes and the home indicator.
## The safe area is reported in physical pixels, so it is normalised against the
## window and then scaled into the viewport the Control lives in.
func _apply_safe_area() -> void:
	if not _is_mobile() or not is_inside_tree():
		return
	var view := get_viewport_rect().size
	if view.x <= 0.0 or view.y <= 0.0:
		return
	var insets := _safe_insets()

	joystick_base.position = Vector2(
		insets.x * view.x + EDGE_MARGIN,
		view.y - joystick_base.size.y - insets.w * view.y - EDGE_MARGIN)

	var right_x := view.x - insets.z * view.x - EDGE_MARGIN - BUTTON_SIZE
	interact_button.position = Vector2(right_x, view.y - insets.w * view.y - EDGE_MARGIN - 3.0 * (BUTTON_SIZE + BUTTON_GAP) + BUTTON_GAP)
	photo_button.position = Vector2(right_x, view.y - insets.w * view.y - EDGE_MARGIN - 2.0 * (BUTTON_SIZE + BUTTON_GAP) + 2.0 * BUTTON_GAP)
	jump_button.position = Vector2(right_x, view.y - insets.w * view.y - EDGE_MARGIN - BUTTON_SIZE)
	pause_button.position = Vector2(view.x - insets.z * view.x - EDGE_MARGIN - 88.0, insets.y * view.y + EDGE_MARGIN)


func _safe_insets() -> Vector4:
	var win := Vector2(DisplayServer.window_get_size())
	if win.x <= 0.0 or win.y <= 0.0:
		return Vector4.ZERO
	var safe := DisplayServer.get_display_safe_area()
	if safe.size.x <= 0 or safe.size.y <= 0:
		return Vector4.ZERO
	return Vector4(
		float(safe.position.x) / win.x,
		float(safe.position.y) / win.y,
		float(win.x - (safe.position.x + safe.size.x)) / win.x,
		float(win.y - (safe.position.y + safe.size.y)) / win.y)


# --- input ------------------------------------------------------------------

func _press_action(action: StringName) -> void:
	var press := InputEventAction.new()
	press.action = action
	press.pressed = true
	Input.parse_input_event(press)
	var release := InputEventAction.new()
	release.action = action
	release.pressed = false
	Input.parse_input_event.call_deferred(release)


func _input(event: InputEvent) -> void:
	if not _is_mobile():
		return
	if event is InputEventScreenTouch:
		_handle_screen_touch(event)
	elif event is InputEventScreenDrag:
		_handle_screen_drag(event)


func _handle_screen_touch(event: InputEventScreenTouch) -> void:
	if event.pressed:
		var stick_rect := Rect2(joystick_base.global_position, joystick_base.size)
		if stick_rect.has_point(event.position):
			joystick_touch_index = event.index
			_update_joystick(event.position)
			return
		# A touch that starts on a button belongs to that button: without this the
		# camera would swing every time the player taps "E".
		if _hit_button(event.position):
			return
		if event.position.x > get_viewport_rect().size.x * 0.5:
			touching_camera = true
			last_touch_pos = event.position
	else:
		if event.index == joystick_touch_index:
			joystick_touch_index = -1
			move_dir = Vector2.ZERO
			_reset_joystick()
		if touching_camera and event.position.x > get_viewport_rect().size.x * 0.5:
			touching_camera = false


func _hit_button(at: Vector2) -> bool:
	for b in _buttons:
		if b.visible and b.get_global_rect().has_point(at):
			return true
	return false


func _handle_screen_drag(event: InputEventScreenDrag) -> void:
	if event.index == joystick_touch_index:
		_update_joystick(event.position)
		return
	if not touching_camera:
		return
	var body := _body()
	if body == null or not GameManager.is_exploring():
		return
	var diff := event.position - last_touch_pos
	last_touch_pos = event.position
	body.rotate_y(-diff.x * 0.003)
	var head := body.get_node_or_null("Head") as Node3D
	if head == null:
		return
	head.rotate_x(-diff.y * 0.003)
	head.rotation.x = clampf(head.rotation.x, -PI / 2.0, PI / 2.0)


func _update_joystick(touch_position: Vector2) -> void:
	var center := joystick_base.global_position + joystick_base.size * 0.5
	var diff := touch_position - center
	var radius := joystick_base.size.x * 0.5 - joystick_knob.size.x * 0.5
	if radius <= 0.0:
		move_dir = Vector2.ZERO
		return
	var clamped := diff.limit_length(radius)
	joystick_knob.position = joystick_base.size * 0.5 + clamped - joystick_knob.size * 0.5
	move_dir = clamped / radius


func _reset_joystick() -> void:
	if not joystick_base or not joystick_knob:
		return
	joystick_knob.position = joystick_base.size * 0.5 - joystick_knob.size * 0.5


func _process(_delta: float) -> void:
	var body := _body()
	if body == null:
		return
	player = body
	player.mobile_input = move_dir


## Resolved late on purpose: the player may be added to the world after this
## control, and GameManager already owns the authoritative reference.
func _body() -> CharacterBody3D:
	if player != null and is_instance_valid(player):
		return player
	var node := get_tree().get_first_node_in_group("player")
	player = node as CharacterBody3D
	return player
