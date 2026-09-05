extends Control

var touching_camera = false
var last_touch_pos = Vector2.ZERO
var joystick_touch_index = -1
var move_dir = Vector2.ZERO

@onready var joystick_base = $JoystickBase
@onready var joystick_knob = $JoystickBase/Knob

func _input(event):
	if event is InputEventScreenTouch:
		if event.pressed:
			var stick_rect = Rect2(joystick_base.global_position, joystick_base.size)
			if stick_rect.has_point(event.position):
				joystick_touch_index = event.index
			elif event.position.x > get_viewport_rect().size.x * 0.5:
				touching_camera = true
				last_touch_pos = event.position
		else:
			if event.index == joystick_touch_index:
				joystick_touch_index = -1
				move_dir = Vector2.ZERO
				joystick_knob.position = joystick_base.size / 2 - joystick_knob.size / 2
			if touching_camera and not event.pressed:
				touching_camera = false

	if event is InputEventScreenDrag:
		if event.index == joystick_touch_index:
			var center = joystick_base.global_position + joystick_base.size / 2
			var diff = event.position - center
			var radius = joystick_base.size.x / 2 - joystick_knob.size.x / 2
			var clamped = diff.clamped(radius)
			joystick_knob.position = joystick_base.size / 2 + clamped - joystick_knob.size / 2
			move_dir = clamped / radius

		elif touching_camera:
			var diff = event.position - last_touch_pos
			last_touch_pos = event.position
			var player = get_tree().get_first_node_in_group("player")
			if player:
				player.rotate_y(-diff.x * 0.003)
				player.head.rotate_x(-diff.y * 0.003)
				player.head.rotation.x = clamp(player.head.rotation.x, -PI/2, PI/2)

func _process(_delta):
	var player = get_tree().get_first_node_in_group("player")
	if player:
		player.mobile_input = move_dir

func _on_jump_button_pressed():
	var player = get_tree().get_first_node_in_group("player")
	if player and player.is_on_floor():
		player.velocity.y = player.JUMP_VELOCITY
