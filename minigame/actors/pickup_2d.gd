class_name MinigamePickup
extends Area2D
## Collectible shard. Some bugs make it float out of reach.

signal collected(pickup: MinigamePickup)

const TILE := 16

@export var base_position: Vector2 = Vector2.ZERO
@export var floating: bool = false
@export var float_amplitude: float = 10.0
@export var unreachable: bool = false

var _time: float = 0.0
var _taken: bool = false
var _sprite: Node2D


func _ready() -> void:
	add_to_group("minigame_pickup")
	base_position = global_position
	var shape := CircleShape2D.new()
	shape.radius = 5.0
	var col := CollisionShape2D.new()
	col.shape = shape
	add_child(col)

	_sprite = Node2D.new()
	add_child(_sprite)
	var r := ColorRect.new()
	r.position = Vector2(-3, -3)
	r.size = Vector2(6, 6)
	r.color = Color(0.4, 0.95, 0.7)
	_sprite.add_child(r)

	body_entered.connect(_on_body_entered)


func _process(delta: float) -> void:
	if _taken:
		return
	_time += delta
	if floating:
		_sprite.position.y = sin(_time * 2.4) * float_amplitude
		_sprite.rotation = _time * 1.2
	if unreachable:
		# Unreachable shards still glimmer, drawing the eye to a broken object.
		_sprite.modulate.a = 0.5 + 0.5 * sin(_time * 3.0)


func _on_body_entered(body: Node2D) -> void:
	if _taken or unreachable:
		return
	if not body.is_in_group("minigame_player"):
		return
	_taken = true
	visible = false
	monitoring = false
	collected.emit(self)


func set_floating(value: bool) -> void:
	floating = value
	if value:
		unreachable = true


func is_taken() -> bool:
	return _taken
