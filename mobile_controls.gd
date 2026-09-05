extends Control

var touching_camera = false
var last_touch_pos = Vector2.ZERO

@onready var joystick_base = $JoystickBase
@onready var joystick_knob = $JoystickBase/Knob

var joystick_touch_index = -1
var joystick_center = Vector2.ZERO
var joystick_radius = 50.0
var move_dir = Vector2.ZERO

func _ready():
	joystick_radius = joystick_base.size.x / 2 - 10

func _input(event):
	if event is InputEventScreenTouch:
		if event.pressed:
			if event.position.x < get_viewport_rect().size.x * 0.4:
				joystick_touch_index = event.index
				joystick_center = event.position
				joystick_base.global_position = event.position - joystick_base.size / 2
			elif event.position.x > get_viewport_rect().size.x * 0.5:
				touching_camera = true
				last_touch_pos = event.position
		else:
			if event.index == joystick_touch_index:
				joystick_touch_index = -1
				move_dir = Vector2.ZERO
				joystick_knob.position = joystick_base.size / 2 - joystick_knob.size / 2
			if touching_camera:
				touching_camera = false

	if event is InputEventScreenDrag:
		if event.index == joystick_touch_index:
			var diff = event.position - joystick_center
			var clamped = diff.clamped(joystick_radius)
			joystick_knob.position = joystick_base.size / 2 + clamped - joystick_knob.size / 2
			move_dir = clamped / joystick_radius

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
