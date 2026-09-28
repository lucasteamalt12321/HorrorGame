class_name MinigameEnemy
extends CharacterBody2D
## Enemy of the game under test. Behaviour is deliberately readable so that
## "the patrol is broken" is something the player can actually notice.

enum Kind { WALKER, CHASER, FLYER, IDLE_NPC }

signal touched_player()

const TILE := 16

@export var kind: int = Kind.WALKER
@export var patrol_range: float = 4.0
@export var speed: float = 34.0
@export var ignores_gravity: bool = false
@export var passes_walls: bool = false
@export var color_body: Color = Color(0.82, 0.28, 0.3)
@export var contact_damage: bool = true
@export var watches_player: bool = false

var origin: Vector2 = Vector2.ZERO
var player: Node2D = null
var frozen: bool = false
var look_at_camera: bool = false
var _dir: int = 1
var _time: float = 0.0
var _sprite: Node2D
var _eye: ColorRect


func _ready() -> void:
	add_to_group("minigame_enemy")
	z_index = 4
	origin = global_position
	_build()


func _build() -> void:
	var shape := RectangleShape2D.new()
	shape.size = Vector2(10, 12)
	var col := CollisionShape2D.new()
	col.shape = shape
	add_child(col)

	_sprite = Node2D.new()
	add_child(_sprite)
	var body := ColorRect.new()
	body.position = Vector2(-4, -8)
	body.size = Vector2(8, 8)
	body.color = color_body
	_sprite.add_child(body)
	_eye = ColorRect.new()
	_eye.position = Vector2(0, -10)
	_eye.size = Vector2(3, 3)
	_eye.color = Color(1, 0.95, 0.6)
	_sprite.add_child(_eye)

	if kind == Kind.FLYER:
		var wing := ColorRect.new()
		wing.name = "Wing"
		wing.position = Vector2(-7, -7)
		wing.size = Vector2(14, 3)
		wing.color = color_body.darkened(0.3)
		_sprite.add_child(wing)


func _physics_process(delta: float) -> void:
	if frozen:
		return
	_time += delta
	match kind:
		Kind.WALKER:
			_walk(delta)
		Kind.CHASER:
			_chase(delta)
		Kind.FLYER:
			_fly(delta)
		Kind.IDLE_NPC:
			_idle(delta)
	_animate()


func _walk(delta: float) -> void:
	if not ignores_gravity:
		velocity.y = minf(velocity.y + 620.0 * delta, 320.0)
	velocity.x = _dir * speed
	move_and_slide()
	if is_on_wall():
		_dir = -_dir
	elif patrol_range > 0.0 and absf(global_position.x - origin.x) > patrol_range * TILE:
		_dir = signf(int(origin.x - global_position.x))
		_dir = 1 if _dir == 0 else _dir
	_check_contact()


func _chase(delta: float) -> void:
	if not ignores_gravity:
		velocity.y = minf(velocity.y + 620.0 * delta, 320.0)
	if player != null and is_instance_valid(player):
		var to := player.global_position - global_position
		velocity.x = signf(to.x) * speed * 1.4
		_eye.color = Color(1, 0.3, 0.2)
	else:
		velocity.x = 0.0
	move_and_slide()
	if is_on_wall():
		_dir = -_dir
	_check_contact()


func _fly(delta: float) -> void:
	# Sine drift: readable, and the "broken patrol" bug makes it worse.
	velocity.x = cos(_time * 0.8) * speed
	velocity.y = sin(_time * 2.1) * speed * 0.4
	if patrol_range > 0.0:
		var limit := patrol_range * TILE
		if absf(global_position.x - origin.x) > limit:
			velocity.x = signf(origin.x - global_position.x) * speed
	move_and_slide()
	_check_contact()


func _idle(delta: float) -> void:
	# Stands in one spot. In chapter 2 it starts looking at the camera.
	if not ignores_gravity:
		velocity.y = minf(velocity.y + 620.0 * delta, 320.0)
	velocity.x = 0.0
	move_and_slide()
	if look_at_camera or watches_player:
		_time += 0.0
		_eye.color = Color(0.95, 0.15, 0.1).lerp(Color(0.4, 0.9, 1.0), 0.5 + 0.5 * sin(_time * 3.0))
	else:
		_eye.color = Color(0.6, 0.6, 0.6)


func _check_contact() -> void:
	if not contact_damage or player == null or not is_instance_valid(player):
		return
	if not (player as MinigamePlayer).alive:
		return
	var body: PhysicsBody2D = player as PhysicsBody2D
	if body == null:
		return
	var d := (body.global_position - global_position).abs()
	if d.x < 8.0 and d.y < 12.0:
		touched_player.emit()


func _animate() -> void:
	if kind == Kind.WALKER:
		_sprite.scale.x = float(_dir)
		var bob := sin(_time * 8.0) * 0.5
		_sprite.position.y = bob
	elif kind == Kind.FLYER:
		_sprite.rotation = sin(_time * 2.1) * 0.12


func set_frozen(value: bool) -> void:
	frozen = value


func set_ignores_walls(value: bool) -> void:
	passes_walls = value
	collision_mask = 0 if value else 1


func set_ignores_gravity(value: bool) -> void:
	ignores_gravity = value


func set_visible_art(value: bool) -> void:
	_sprite.visible = value


func set_look_at_camera(value: bool) -> void:
	look_at_camera = value
	watches_player = value
