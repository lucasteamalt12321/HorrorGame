class_name OfficeProp
extends Interactable
## A readable object in the office: the registration book, the build notes, the
## photo of the colleague, the mug.
##
## Reading shows its lines as subtitles and counts once towards the TALK_TO task
## condition. Re-reading replays the lines but never counts twice, so nothing
## depends on the player remembering whether they already did it.

@export var document_id: String = ""
## One line per paragraph; they are queued as subtitles in order.
@export_multiline var lines_text: String = ""
@export var prop_size: Vector3 = Vector3(0.22, 0.03, 0.3)
@export var prop_color: Color = Color(0.86, 0.84, 0.76)
@export var read_sound: String = "click"

var _lines: PackedStringArray = PackedStringArray()
var _read_once: bool = false


func _ready() -> void:
	super()
	_lines = _split_lines()
	_build_visual()


func get_prompt() -> String:
	if _read_once:
		return "%s (уже прочитано)" % prompt_text
	return prompt_text


func on_interact(by: Node) -> bool:
	if not super(by):
		return false
	_read_once = true
	for line: String in _lines:
		DialogueSystem.queue_line(line, document_id)
	if document_id != "":
		TaskSystem.notify_document_read(document_id)
	AudioManager.play_ui(read_sound)
	return true


func is_read() -> bool:
	return _read_once


## Restores the read state from a save so prompts stay honest across sessions.
func set_read(value: bool) -> void:
	_read_once = value


func get_document_id() -> String:
	return document_id


func _split_lines() -> PackedStringArray:
	var out := PackedStringArray()
	for raw: String in lines_text.split("\n"):
		var line := raw.strip_edges()
		if line != "":
			out.append(line)
	return out


func _build_visual() -> void:
	var mesh := BoxMesh.new()
	mesh.size = prop_size
	var mi := MeshInstance3D.new()
	mi.name = "Visual"
	mi.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_color = prop_color
	mat.roughness = 0.9
	mi.material_override = mat
	add_child(mi)

	var shape := BoxShape3D.new()
	shape.size = prop_size
	var col := CollisionShape3D.new()
	col.shape = shape
	add_child(col)
