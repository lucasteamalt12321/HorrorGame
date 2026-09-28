class_name TestRoomDoor
extends Interactable
## The panel behind the shelf that leads to TEST_ROOM.
##
## It answers only once the tester has been given the name of the room, so the
## director gates it. Opening it unlocks the secret 2D level and reports the
## discovery to TaskSystem — the panel is the discovery, not the level launch.

@export var panel_size: Vector3 = Vector3(0.9, 2.1, 0.08)
@export var locked_lines: PackedStringArray = PackedStringArray()
@export var open_lines: PackedStringArray = PackedStringArray()
## The chapter at which the panel stops pretending to be part of the wall.
@export var reveal_chapter: int = 5
## The assignment that names the room is the other way in: if T09 is the open
## assignment, the panel has to answer.
@export var reveal_task_id: String = "T09_TEST_ROOM"

var _panel: MeshInstance3D = null
var _revealed: bool = false
var _opened: bool = false


func _ready() -> void:
	super()
	add_to_group("test_room_door")
	_build_visual()
	refresh_state()


func get_prompt() -> String:
	if _opened:
		return "TEST_ROOM открыт"
	if _revealed:
		return prompt_text
	return "Стена"


func on_interact(by: Node) -> bool:
	if not super(by):
		return false
	if _opened:
		DialogueSystem.queue_line("Комната уже открыта.", "test_room_door")
		return true
	if not _revealed:
		for line: String in locked_lines:
			DialogueSystem.queue_line(line, "test_room_door")
		AudioManager.play_ui("error")
		return true
	for line: String in open_lines:
		DialogueSystem.queue_line(line, "test_room_door")
	AudioManager.play_ui("unlock")
	# The panel is the discovery; whether the 2D level was still locked is a
	# separate fact owned by MinigameSystem (a horror event may have opened it
	# earlier). The panel must never re-close itself because of that.
	MinigameSystem.unlock_secret_level()
	TaskSystem.notify_test_room_entered()
	StoryFlags.set_flag(&"test_room_found", true)
	_opened = true
	_apply_visual()
	return true


func is_opened() -> bool:
	return _opened


func is_revealed() -> bool:
	return _revealed


## The director asks whether the panel is still part of the wall; the door
## answers from system state only, so a save reload cannot desynchronise it.
func should_be_revealed() -> bool:
	if _opened:
		return true
	if reveal_task_id != "" and TaskSystem.is_active(reveal_task_id):
		return true
	return StorySystem.get_chapter() >= reveal_chapter


func _refresh_state() -> void:
	_revealed = should_be_revealed()
	_apply_visual()


## Re-reads the chapter: the director calls this whenever the story moves.
func refresh_state() -> void:
	_refresh_state()


## A save must not close the room again; only the absence of the flag re-hides
## the panel.
func set_opened(value: bool) -> void:
	_opened = value
	_revealed = should_be_revealed()
	_apply_visual()


func _apply_visual() -> void:
	if _panel == null:
		return
	var mat := _panel.material_override as StandardMaterial3D
	if mat == null:
		return
	if _opened:
		mat.albedo_color = Color(0.05, 0.05, 0.06)
		mat.emission_enabled = true
		mat.emission = Color(0.25, 0.4, 0.45)
		mat.emission_energy_multiplier = 0.6
	elif _revealed:
		mat.albedo_color = Color(0.2, 0.21, 0.24)
		mat.emission_enabled = true
		mat.emission = Color(0.3, 0.32, 0.36)
		mat.emission_energy_multiplier = 0.15
	else:
		mat.albedo_color = Color(0.42, 0.41, 0.4)
		mat.emission_enabled = false


func _build_visual() -> void:
	var mesh := BoxMesh.new()
	mesh.size = panel_size
	_panel = MeshInstance3D.new()
	_panel.name = "Panel"
	_panel.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.roughness = 0.95
	_panel.material_override = mat
	_panel.position = Vector3(0.0, panel_size.y * 0.5, 0.0)
	add_child(_panel)

	var shape := BoxShape3D.new()
	shape.size = panel_size
	var col := CollisionShape3D.new()
	col.shape = shape
	col.position = _panel.position
	add_child(col)
