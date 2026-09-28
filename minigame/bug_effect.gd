class_name BugEffect
extends Node2D
## Applies ONE bug's observable behaviour inside the game under test.
##
## The bug itself is data (BugResource); this node is the runtime interpreter of
## that data. It never decides *when* the bug happens — MinigameSystem does.

const TILE := 16

var bug_id: String = ""
var kind: int = BugResource.Kind.NONE
var target: Node2D = null
var level: LevelResource = null
var lifetime: float = 0.0
var _time: float = 0.0
var _marker: Node2D = null
var _ghost: Node2D = null
var _label: Label = null
var _tear: ColorRect = null


func configure(bug: BugResource, target_node: Node2D, level_res: LevelResource) -> void:
	bug_id = bug.id
	kind = bug.kind
	target = target_node
	level = level_res
	lifetime = bug.active_window
	name = "BugEffect_" + bug.id
	_build_marker()
	_apply()


func _process(delta: float) -> void:
	_time += delta
	if lifetime > 0.0 and _time > lifetime:
		queue_free()
		return
	match kind:
		BugResource.Kind.ANIMATION_LOOP:
			_animation_loop()
		BugResource.Kind.SCREEN_TEAR:
			_screen_tear()
		BugResource.Kind.WRONG_SPAWN:
			_wrong_spawn()
		BugResource.Kind.BROKEN_PATROL:
			_broken_patrol()
		BugResource.Kind.PLAYER_AVATAR:
			_player_avatar()
		BugResource.Kind.TEXT_MUTATION:
			_text_mutation()
		_:
			pass


func _build_marker() -> void:
	if _marker != null:
		return
	_marker = Node2D.new()
	_marker.name = "Marker"
	add_child(_marker)
	var c := ColorRect.new()
	c.name = "Highlight"
	c.size = Vector2(2, 2)
	c.color = Color(1, 0.2, 0.2, 0.0)
	c.position = Vector2(-1, -14)
	_marker.add_child(c)
	if target != null and target is Node2D:
		_marker.global_position = target.global_position


func get_marker_node() -> Node2D:
	return _marker if _marker != null else self


func marker_world_position() -> Vector2:
	if target != null and is_instance_valid(target):
		return target.global_position
	return global_position


func _apply() -> void:
	match kind:
		BugResource.Kind.NPC_THROUGH_WALL:
			if target is MinigameEnemy:
				(target as MinigameEnemy).set_ignores_walls(true)
		BugResource.Kind.FLOATING_PICKUP:
			if target is MinigamePickup:
				(target as MinigamePickup).set_floating(true)
		BugResource.Kind.INVISIBLE_ENEMY:
			if target is MinigameEnemy:
				(target as MinigameEnemy).set_visible_art(false)
		BugResource.Kind.NPC_WATCHES:
			if target is MinigameEnemy:
				(target as MinigameEnemy).set_look_at_camera(true)
			_add_label("...?", Color(1, 0.3, 0.3))
		BugResource.Kind.LTL_INSCRIPTION:
			_add_label("LTL", Color(0.85, 0.85, 0.9))
		BugResource.Kind.HIDDEN_PASSAGE:
			if target != null and target is StaticBody2D:
				(target as StaticBody2D).process_mode = Node.PROCESS_MODE_DISABLED
				_apply_ghost(target.global_position, Vector2(24, 40), Color(0.1, 0.1, 0.12, 0.0))
		BugResource.Kind.BROKEN_PATROL:
			if target is MinigameEnemy:
				(target as MinigameEnemy).set_ignores_gravity(true)
		BugResource.Kind.WRONG_SPAWN:
			_apply_ghost(_wrong_spawn_point(), Vector2(14, 14), Color(0.7, 0.2, 0.7, 0.85))
		BugResource.Kind.PLAYER_AVATAR:
			_build_avatar()
		BugResource.Kind.TEXT_MUTATION:
			_add_label("УРОВЕНЬ ПРОЙДЕН", Color(0.9, 0.9, 0.9))
		BugResource.Kind.SCREEN_TEAR:
			_screen_tear()
		_:
			pass
	_stroke_marker()


func _stroke_marker() -> void:
	if _marker == null:
		return
	var hl := _marker.get_node_or_null("Highlight") as ColorRect
	if hl == null:
		return
	# A subtle frame so the anomaly is *visible* to a human tester, but the bug
	# id is only in the log — the player must connect the two by eye.
	var pulse: float = 0.35 + 0.25 * sin(_time * 4.0)
	hl.color = Color(1.0, 0.25, 0.2, pulse)
	hl.size = Vector2(14, 18) if target != null else Vector2(4, 4)
	hl.position = Vector2(-7, -18) if target != null else Vector2(-2, -4)


func _add_label(text: String, color: Color) -> void:
	_label = Label.new()
	_label.text = text
	_label.add_theme_color_override("font_color", color)
	_label.add_theme_font_size_override("font_size", 6)
	_label.add_theme_constant_override("outline_size", 3)
	_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	_label.position = Vector2(-6, -26)
	_label.z_index = 40
	add_child(_label)


func _apply_ghost(at: Vector2, size: Vector2, color: Color) -> void:
	_ghost = Node2D.new()
	_ghost.global_position = at
	_ghost.z_index = 3
	add_child(_ghost)
	var r := ColorRect.new()
	r.size = size
	r.position = -size * 0.5
	r.color = color
	_ghost.add_child(r)


func _wrong_spawn_point() -> Vector2:
	if level == null:
		return global_position
	# The object appears where nothing was authored: above the spawn point.
	return Vector2(level.spawn.x * TILE, level.spawn.y * TILE) - Vector2(0, TILE * 3.0)


func _animation_loop() -> void:
	if target == null or not (target is MinigameEnemy):
		return
	var e := target as MinigameEnemy
	var frame := int(_time * 3.0) % 2
	e.color_body = Color(0.82, 0.28, 0.3) if frame == 0 else Color(0.28, 0.82, 0.3)
	e.modulate = Color(1, 1, 1) if frame == 0 else Color(1.0, 0.75, 0.75)


func _screen_tear() -> void:
	if _tear == null or not is_instance_valid(_tear):
		_tear = ColorRect.new()
		_tear.size = Vector2(400, 4)
		_tear.color = Color(0.9, 0.9, 1.0, 0.35)
		_tear.z_index = 60
		add_child(_tear)
	for i in 3:
		_tear.position.y = fmod(_time * 47.0 + i * 61.0, 240.0)
		_tear.position.x = fmod(_time * 91.0 + i * 13.0, 100.0) - 50.0
		_tear.color.a = 0.2 + 0.25 * absf(sin(_time * 9.0 + i))


func _wrong_spawn() -> void:
	if _ghost == null or not is_instance_valid(_ghost):
		return
	_ghost.position.y = sin(_time * 3.0) * 3.0
	_ghost.modulate.a = 0.6 + 0.4 * sin(_time * 6.0)


func _broken_patrol() -> void:
	if target == null or not (target is MinigameEnemy):
		return
	var e := target as MinigameEnemy
	e.velocity = Vector2(sin(_time * 0.7) * 26.0, cos(_time * 0.5) * 8.0)
	e.move_and_slide()


func _player_avatar() -> void:
	if _ghost == null or not is_instance_valid(_ghost):
		return
	var p := get_tree().get_first_node_in_group("minigame_player") as Node2D
	if p == null:
		return
	# A copy of the tester stands where the tester was a moment ago.
	_ghost.global_position = p.global_position + Vector2(0, 0)
	_ghost.modulate = Color(1, 1, 1, 0.9)


func _build_avatar() -> void:
	_ghost = Node2D.new()
	_ghost.z_index = 6
	add_child(_ghost)
	var body := ColorRect.new()
	body.size = Vector2(8, 12)
	body.position = Vector2(-4, -12)
	body.color = Color(0.36, 0.55, 0.85)
	_ghost.add_child(body)
	var head := ColorRect.new()
	head.size = Vector2(6, 6)
	head.position = Vector2(-3, -18)
	head.color = Color(0.92, 0.82, 0.68)
	_ghost.add_child(head)
	if _marker != null:
		_marker.global_position = Vector2.ZERO


func _text_mutation() -> void:
	if _label == null or not is_instance_valid(_label):
		return
	var pool := ["УРОВЕНЬ ПРОЙДЕН", "ТЕСТЕР ОБНАРУЖЕН", "LTL", "ВЫХОДА НЕТ"]
	_label.text = String(pool[int(_time) % pool.size()])
