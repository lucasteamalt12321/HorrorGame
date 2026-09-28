class_name OfficeNpc
extends Interactable
## The colleague at the next desk.
##
## The colleague is a gameplay object, not lore: they answer in short lines,
## turn to watch the tester when approached, and stop answering as the chapters
## progress. Nothing here states anything about the world outside this office.

@export var lines_early: PackedStringArray = PackedStringArray()
@export var lines_mid: PackedStringArray = PackedStringArray()
@export var lines_late: PackedStringArray = PackedStringArray()
## The chapter at which the colleague stops being there at all.
@export var vanish_chapter: int = 10
@export var body_color: Color = Color(0.32, 0.34, 0.42)
@export var head_color: Color = Color(0.88, 0.79, 0.66)
@export var look_at_distance: float = 3.0

var _body: Node3D = null
var _gone: bool = false


func _ready() -> void:
	super()
	add_to_group("office_npc")
	_build_visual()
	refresh_presence()


func get_prompt() -> String:
	if _gone:
		return "Пусто"
	return prompt_text


func on_interact(by: Node) -> bool:
	if not super(by):
		return false
	if _gone:
		DialogueSystem.queue_line("...", "office_npc")
		AudioManager.play_ui("error")
		return true
	_face_player()
	var lines := _current_lines()
	if lines.is_empty():
		DialogueSystem.queue_line("...", "office_npc")
	else:
		for line: String in lines:
			DialogueSystem.queue_line(line, "office_npc")
	TaskSystem.notify_document_read("npc_colleague")
	AudioManager.play_ui("click")
	refresh_presence()
	return true


func is_gone() -> bool:
	return _gone


## Exposed for save games: the colleague must not come back mid-ending.
func set_gone(value: bool) -> void:
	_gone = value
	_apply_presence()


func _process(_delta: float) -> void:
	if _body == null or not _body.visible:
		return
	var player := GameManager.get_player()
	if player == null or not is_instance_valid(player):
		return
	var here := _body.global_position
	if here.distance_to(player.global_position) > look_at_distance:
		return
	_face_player()


func _face_player() -> void:
	var player := GameManager.get_player()
	if player == null or not is_instance_valid(player) or _body == null:
		return
	if _body.global_position.distance_to(player.global_position) < 0.05:
		return
	_body.look_at(player.global_position, Vector3.UP)


func _current_lines() -> PackedStringArray:
	if _gone:
		return PackedStringArray()
	var chapter := StorySystem.get_chapter()
	if chapter >= vanish_chapter - 2:
		return lines_late
	if chapter >= 4:
		return lines_mid
	return lines_early


func _refresh_presence() -> void:
	var should_be_gone := StorySystem.get_chapter() >= vanish_chapter
	if should_be_gone == _gone:
		return
	_gone = should_be_gone
	_apply_presence()
	if _gone:
		DialogueSystem.queue_line("Стул напротив пуст.", "office_npc")


## Re-reads the chapter: the director calls this whenever the story moves.
func refresh_presence() -> void:
	_refresh_presence()


func _apply_presence() -> void:
	if _body != null:
		_body.visible = not _gone


func _build_visual() -> void:
	# Seated on the chair next to them: local -Z is forward, so the legs reach
	# towards -Z. The chair itself is furniture and belongs to the director.
	_body = Node3D.new()
	_body.name = "Body"
	add_child(_body)

	_add_box(_body, Vector3(0.34, 0.55, 0.24), body_color, Vector3(0.0, 0.85, 0.0))
	_add_box(_body, Vector3(0.19, 0.22, 0.19), head_color, Vector3(0.0, 1.2, -0.02))
	_add_box(_body, Vector3(0.12, 0.4, 0.12), body_color.darkened(0.15), Vector3(-0.23, 0.82, 0.0))
	_add_box(_body, Vector3(0.12, 0.4, 0.12), body_color.darkened(0.15), Vector3(0.23, 0.82, 0.0))
	_add_box(_body, Vector3(0.13, 0.13, 0.4), Color(0.2, 0.21, 0.26), Vector3(-0.08, 0.5, -0.1))
	_add_box(_body, Vector3(0.13, 0.13, 0.4), Color(0.2, 0.21, 0.26), Vector3(0.08, 0.5, -0.1))
	_add_box(_body, Vector3(0.13, 0.45, 0.13), Color(0.2, 0.21, 0.26), Vector3(-0.08, 0.22, -0.26))
	_add_box(_body, Vector3(0.13, 0.45, 0.13), Color(0.2, 0.21, 0.26), Vector3(0.08, 0.22, -0.26))

	var shape := BoxShape3D.new()
	shape.size = Vector3(0.5, 1.3, 0.6)
	var col := CollisionShape3D.new()
	col.shape = shape
	col.position = Vector3(0.0, 0.65, -0.1)
	add_child(col)


func _add_box(parent: Node3D, size: Vector3, color: Color, at: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.95
	mi.material_override = mat
	mi.position = at
	parent.add_child(mi)
	return mi
