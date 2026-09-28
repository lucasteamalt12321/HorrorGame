class_name MinigamePlayer
extends CharacterBody2D
## The avatar of the game under test. Deliberately simple: the horror comes
## from the game noticing the tester, not from platforming difficulty.

signal died(cause: String)
signal jumped()
signal landed()

const TILE := 16

@export var move_speed: float = 88.0
@export var acceleration: float = 900.0
@export var friction: float = 1100.0
@export var gravity: float = 620.0
@export var jump_height: float = 3.4 * TILE
@export var max_fall_speed: float = 320.0
@export var coyote_time: float = 0.09
@export var jump_buffer: float = 0.10
@export var input_enabled: bool = true
@export var lives: int = 3

var facing: int = 1
var alive: bool = true
var external_move: Vector2 = Vector2.ZERO
var jump_requested: bool = false
var frozen: bool = false

var _coyote: float = 0.0
var _buffer: float = 0.0
var _anim_time: float = 0.0
var _sprite: Node2D
var _leg_l: ColorRect
var _leg_r: ColorRect
var _body: ColorRect
var _head: ColorRect
var _badge: ColorRect


func _ready() -> void:
	add_to_group("minigame_player")
	z_index = 5
	_build_collision()
	_build_sprite()
	floor_snap_length = 4.0
	floor_max_angle = deg_to_rad(50.0)


func _build_collision() -> void:
	var shape := RectangleShape2D.new()
	shape.size = Vector2(10, 14)
	var col := CollisionShape2D.new()
	col.shape = shape
	add_child(col)


func _build_sprite() -> void:
	_sprite = Node2D.new()
	_sprite.name = "Sprite"
	add_child(_sprite)

	_body = _rect(Vector2(-4, -8), Vector2(8, 8), Color(0.36, 0.55, 0.85))
	_head = _rect(Vector2(-3, -14), Vector2(6, 6), Color(0.92, 0.82, 0.68))
	_leg_l = _rect(Vector2(-4, 0), Vector2(3, 4), Color(0.22, 0.24, 0.32))
	_leg_r = _rect(Vector2(1, 0), Vector2(3, 4), Color(0.22, 0.24, 0.32))
	# A tiny badge: the tester is always "at work".
	_badge = _rect(Vector2(0, -7), Vector2(3, 3), Color(0.95, 0.95, 0.35))
	_badge.name = "Badge"


func _rect(pos: Vector2, size: Vector2, color: Color) -> ColorRect:
	var r := ColorRect.new()
	r.position = pos
	r.size = size
	r.color = color
	_sprite.add_child(r)
	return r


func _physics_process(delta: float) -> void:
	if not alive or frozen:
		velocity = Vector2.ZERO
		return

	var dir := Vector2.ZERO
	if input_enabled:
		dir = Input.get_vector("move_left", "move_right", "move_forward", "move_backward")
		dir += external_move
		dir = dir.limit_length(1.0)
		if Input.is_action_just_pressed("minigame_jump") or jump_requested:
			_buffer = jump_buffer
	jump_requested = false

	velocity.x = move_toward(velocity.x, dir.x * move_speed, (acceleration if dir.x != 0.0 else friction) * delta)
	velocity.y = minf(velocity.y + gravity * delta, max_fall_speed)

	if is_on_floor():
		_coyote = coyote_time
	else:
		_coyote = maxf(0.0, _coyote - delta)
	_buffer = maxf(0.0, _buffer - delta)
	if _buffer > 0.0 and _coyote > 0.0:
		velocity.y = -sqrt(2.0 * gravity * jump_height)
		_buffer = 0.0
		_coyote = 0.0
		jumped.emit()

	var was_floor := is_on_floor()
	move_and_slide()
	if not was_floor and is_on_floor():
		landed.emit()

	if absf(velocity.x) > 4.0:
		facing = 1 if velocity.x > 0.0 else -1
	_sprite.scale.x = float(facing)
	_animate(delta)


func _animate(delta: float) -> void:
	_anim_time += delta * (6.0 + absf(velocity.x) / 12.0)
	var swing := 0.0
	if is_on_floor() and absf(velocity.x) > 8.0:
		swing = sin(_anim_time * 6.0) * 1.5
	_leg_l.position.y = swing
	_leg_r.position.y = -swing
	_body.color = Color(0.36, 0.55, 0.85).lerp(Color(0.55, 0.35, 0.75), clampf(-velocity.y / 400.0, 0.0, 0.5))


func kill(cause: String = "enemy") -> void:
	if not alive:
		return
	alive = false
	visible = false
	died.emit(cause)


func revive(at: Vector2) -> void:
	alive = true
	visible = true
	velocity = Vector2.ZERO
	global_position = at
