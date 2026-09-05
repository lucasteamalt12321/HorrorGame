extends Control

var look_delta = Vector2.ZERO
var touching_camera = false
var last_touch_pos = Vector2.ZERO

@onready var btn_up = $Buttons/Up
@onready var btn_down = $Buttons/Down
@onready var btn_left = $Buttons/Left
@onready var btn_right = $Buttons/Right
@onready var btn_jump = $Buttons/Jump

func _input(event):
	if event is InputEventScreenTouch:
		if event.pressed and event.position.x > get_viewport_rect().size.x * 0.5:
			touching_camera = true
			last_touch_pos = event.position
		elif not event.pressed:
			touching_camera = false

	if event is InputEventScreenDrag and touching_camera:
		var diff = event.position - last_touch_pos
		last_touch_pos = event.position
		var player = get_tree().get_first_node_in_group("player")
		if player:
			player.camera_offset -= diff * 0.003

func _process(_delta):
	var dir = Vector2.ZERO
	if btn_up and btn_up.button_pressed:
		dir.y -= 1
	if btn_down and btn_down.button_pressed:
		dir.y += 1
	if btn_left and btn_left.button_pressed:
		dir.x -= 1
	if btn_right and btn_right.button_pressed:
		dir.x += 1

	var player = get_tree().get_first_node_in_group("player")
	if player:
		player.mobile_input = dir
