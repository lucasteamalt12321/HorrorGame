extends Control

var touching_camera := false
var last_touch_pos := Vector2.ZERO
var joystick_touch_index := -1
var move_dir := Vector2.ZERO
var player: CharacterBody3D

@onready var joystick_base: Control = $JoystickBase
@onready var joystick_knob: Control = $JoystickBase/Knob
@onready var jump_button: Button = $JumpButton

func _ready() -> void:
	# Mobile controls must never be visible or active on desktop.
	if not _is_mobile():
		visible = false
		process_mode = Node.PROCESS_MODE_DISABLED
		return

	player = get_tree().get_first_node_in_group("player") as CharacterBody3D
	_reset_joystick()

func _is_mobile() -> bool:
	return OS.has_feature("mobile") or OS.has_feature("android") or OS.has_feature("ios")

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

		if jump_button.get_global_rect().has_point(event.position):
			return

		if event.position.x > get_viewport_rect().size.x * 0.5:
			touching_camera = true
			last_touch_pos = event.position
	else:
		if event.index == joystick_touch_index:
			joystick_touch_index = -1
			move_dir = Vector2.ZERO
			_reset_joystick()

		if touching_camera:
			touching_camera = false

func _handle_screen_drag(event: InputEventScreenDrag) -> void:
	if event.index == joystick_touch_index:
		_update_joystick(event.position)
		return

	if touching_camera and player:
		var diff := event.position - last_touch_pos
		last_touch_pos = event.position

		player.rotate_y(-diff.x * 0.003)
		player.head.rotate_x(-diff.y * 0.003)
		player.head.rotation.x = clamp(player.head.rotation.x, -PI / 2.0, PI / 2.0)

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
	if player:
		player.mobile_input = move_dir

func _on_jump_button_pressed() -> void:
	if player and player.is_on_floor():
		player.velocity.y = player.JUMP_VELOCITY
