class_name OfficeDirector
extends Node3D
## Owner of the office content: which props exist, how the colleague behaves and
## when the panel behind the shelf stops pretending to be a wall.
##
## The director builds its props in code because every mesh in this game is
## procedural. It reads system state and reports events; it never writes story
## prose, and it never claims anything about the world outside this office.

const REGISTRY_BOOK := "doc_registry_book"
const BUILD_NOTES := "doc_build_notes"
const COLLEAGUE_PHOTO := "doc_colleague_photo"
const SHIFT_LOG := "doc_shift_log"
const NPC_ID := "npc_colleague"

const NPC_POSITION := Vector3(-2.55, 0.0, -0.35)
const NPC_YAW := -90.0

## Horror beats must always revert: nothing here may block progress, so every
## temporary change has a guaranteed undo and a bounded lifetime.
const PROP_RESTORE_SECONDS := 26.0
const LEAK_LIFETIME := 9.0
const REWRITE_LIFETIME := 14.0

var _props: Dictionary = {}    ## document_id -> OfficeProp
var _npc: OfficeNpc = null
var _door: TestRoomDoor = null
var _read_ids: PackedStringArray = PackedStringArray()
var _lights: Array[Light3D] = []
var _light_energy: Array[float] = []
var _flicker_left: float = 0.0
var _rewrite_left: float = 0.0
var _prop_restore: Dictionary = {}  ## document_id -> seconds left


func _ready() -> void:
	add_to_group("office_director")
	_build_furniture()
	_build_props()
	_build_colleague()
	_build_test_room_door()
	_collect_lights()
	SaveSystem.register(&"office", self)
	StorySystem.chapter_changed.connect(_on_chapter_changed)
	TaskSystem.task_accepted.connect(_on_task_accepted)
	TaskSystem.task_completed.connect(_on_task_completed)
	HorrorSystem.register_receiver(HorrorEventResource.Target.OFFICE_PROP, self)
	HorrorSystem.register_receiver(HorrorEventResource.Target.OFFICE_LIGHT, self)
	HorrorSystem.register_receiver(HorrorEventResource.Target.OFFICE_WINDOW, self)
	_restore_read_state()
	_refresh_presence()


func _exit_tree() -> void:
	SaveSystem.unregister(&"office")
	HorrorSystem.clear_receiver(HorrorEventResource.Target.OFFICE_PROP)
	HorrorSystem.clear_receiver(HorrorEventResource.Target.OFFICE_LIGHT)
	HorrorSystem.clear_receiver(HorrorEventResource.Target.OFFICE_WINDOW)


# --- content ----------------------------------------------------------------

## The second workstation belongs to the colleague. It stays when they do not.
func _build_furniture() -> void:
	var desk := Node3D.new()
	desk.name = "ColleagueDesk"
	desk.position = Vector3(-3.45, 0.0, NPC_POSITION.z)
	desk.rotation.y = deg_to_rad(NPC_YAW)
	add_child(desk)
	_add_box(desk, Vector3(0.7, 0.06, 1.4), Color(0.4, 0.33, 0.26), Vector3(0.0, 0.9, 0.0))
	for sx: float in [-0.28, 0.28]:
		for sz: float in [-0.6, 0.6]:
			_add_box(desk, Vector3(0.05, 0.9, 0.05), Color(0.3, 0.25, 0.2), Vector3(sx, 0.45, sz))

	var chair := Node3D.new()
	chair.name = "ColleagueChair"
	chair.position = NPC_POSITION
	chair.rotation.y = deg_to_rad(NPC_YAW)
	add_child(chair)
	_add_box(chair, Vector3(0.5, 0.06, 0.5), Color(0.24, 0.25, 0.28), Vector3(0.0, 0.45, 0.05))
	_add_box(chair, Vector3(0.5, 0.5, 0.06), Color(0.24, 0.25, 0.28), Vector3(0.0, 0.72, 0.28))
	_add_box(chair, Vector3(0.08, 0.42, 0.08), Color(0.2, 0.21, 0.24), Vector3(0.0, 0.21, 0.05))
	_add_box(chair, Vector3(0.44, 0.05, 0.44), Color(0.18, 0.19, 0.22), Vector3(0.0, 0.03, 0.05))

func _build_props() -> void:
	_add_prop(REGISTRY_BOOK, "Книга регистрации", Vector3(0.86, 1.0, -0.72),
			Vector3(0.26, 0.035, 0.34), Color(0.62, 0.24, 0.22),
			"Строка на сегодняшний день уже есть.\nПодпись тестера, но почерк незнакомый.")
	_add_prop(BUILD_NOTES, "Стопка документов", Vector3(-1.0, 1.0, -0.78),
			Vector3(0.3, 0.09, 0.22), Color(0.87, 0.85, 0.79),
			"Сборка от сегодняшней ночи.\nОтметка «проверено» стоит на всех пунктах, включая те, что вы не проверяли.")
	_add_prop(SHIFT_LOG, "Журнал смен", Vector3(1.32, 1.0, -0.42),
			Vector3(0.22, 0.03, 0.3), Color(0.9, 0.88, 0.8),
			"Прошлый тестер отработал смену и ушёл.\nВ графе «время выхода» пусто.")
	_add_prop(COLLEAGUE_PHOTO, "Фото коллеги", Vector3(-3.44, 1.06, -2.12),
			Vector3(0.02, 0.2, 0.26), Color(0.78, 0.74, 0.66),
			"Фотография из общего отдела. Человек на снимке смотрит в сторону.")


func _build_colleague() -> void:
	_npc = OfficeNpc.new()
	_npc.name = "Colleague"
	_npc.prompt_text = "Поговорить"
	_npc.focus_priority = 2
	_npc.position = NPC_POSITION
	_npc.rotation.y = deg_to_rad(NPC_YAW)
	_npc.lines_early = PackedStringArray([
		"Смена только начинается. Не торопись.",
		"Следи за вкладкой отчётов. Там всё, что ты поймал.",
	])
	_npc.lines_mid = PackedStringArray([
		"Ты третий день читаешь тот же документ.",
		"Я не помню, чтобы мы меняли состав документов.",
	])
	_npc.lines_late = PackedStringArray([
		"Я не буду это повторять.",
		"...",
	])
	add_child(_npc)


func _build_test_room_door() -> void:
	_door = TestRoomDoor.new()
	_door.name = "TestRoomPanel"
	_door.prompt_text = "TEST_ROOM"
	_door.focus_priority = 1
	_door.position = Vector3(-4.36, 0.0, -0.9)
	_door.rotation.y = deg_to_rad(90.0)
	_door.locked_lines = PackedStringArray([
		"Ровная стена. Ни ручки, ни стыка.",
	])
	_door.open_lines = PackedStringArray([
		"За стеной комната. Она выглядит как этот офис.",
		"На двери изнутри написано: не закрывай.",
	])
	add_child(_door)


func _add_prop(document_id: String, label: String, at: Vector3, size: Vector3,
		color: Color, lines: String) -> void:
	var prop := OfficeProp.new()
	prop.name = label.capitalize().replace(" ", "")
	prop.document_id = document_id
	prop.prompt_text = label
	prop.lines_text = lines
	prop.prop_size = size
	prop.prop_color = color
	prop.focus_priority = 3
	prop.position = at
	add_child(prop)
	prop.interact_performed.connect(_on_prop_interacted.bind(prop))
	_props[document_id] = prop


func _on_prop_interacted(_by: Node, prop: OfficeProp) -> void:
	note_read(prop.get_document_id())


func _add_box(parent: Node3D, size: Vector3, color: Color, at: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	var mi := MeshInstance3D.new()
	mi.name = "Part"
	mi.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.95
	mi.material_override = mat
	mi.position = at
	parent.add_child(mi)
	return mi


# --- state ------------------------------------------------------------------

func get_prop(document_id: String) -> OfficeProp:
	return _props.get(document_id, null)


func get_colleague() -> OfficeNpc:
	return _npc


func get_test_room_door() -> TestRoomDoor:
	return _door


func get_read_ids() -> PackedStringArray:
	return _read_ids.duplicate()


## Called by the props so a reload shows "уже прочитано" instead of lying.
func note_read(document_id: String) -> void:
	if document_id == "" or _read_ids.has(document_id):
		return
	_read_ids.append(document_id)
	var prop := get_prop(document_id)
	if prop != null:
		prop.set_read(true)


func _restore_read_state() -> void:
	for document_id: String in _read_ids:
		var prop := get_prop(document_id)
		if prop != null:
			prop.set_read(true)


func _refresh_presence() -> void:
	if _npc != null:
		_npc.refresh_presence()
	if _door != null:
		_door.refresh_state()


func _on_chapter_changed(_chapter: int, _title: String) -> void:
	_refresh_presence()


## A new assignment can be the thing that makes the office answer, so the panel
## is re-evaluated whenever the tester takes work.
func _on_task_accepted(_task_id: String) -> void:
	_refresh_presence()


func _on_task_completed(task_id: String) -> void:
	if task_id == "T09_TEST_ROOM":
		_refresh_presence()


# --- horror receivers -------------------------------------------------------
#
# HorrorSystem addresses the office through these four methods. Everything here is
# cosmetic and self-reverting: a beat may make the office feel wrong for a few
# seconds, and it may never make a document unreadable or a panel unreachable.

func _collect_lights() -> void:
	_lights.clear()
	_light_energy.clear()
	for node: Node in get_tree().get_nodes_in_group("office_light"):
		var light := node as Light3D
		if light == null:
			continue
		_lights.append(light)
		_light_energy.append(light.light_energy)


## Drives the ceiling / desk / window lamps of office.tscn.
func set_light_flicker(duration: float) -> void:
	_flicker_left = maxf(_flicker_left, maxf(0.4, duration))
	AudioManager.play_horror("glitch")


## `hide`, `show` or `jump` a document. A hidden document always comes back.
func apply_prop_event(prop_id: String, action: String) -> void:
	var prop := get_prop(prop_id)
	if prop == null:
		return
	match action:
		"hide":
			prop.visible = false
			_prop_restore[prop_id] = PROP_RESTORE_SECONDS
		"show":
			prop.visible = true
			_prop_restore.erase(prop_id)
		"jump":
			_prop_jump(prop)
		_:
			pass


func _prop_jump(prop: OfficeProp) -> void:
	var home := prop.position
	var tween := create_tween()
	tween.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(prop, "position", home + Vector3(0.0, 0.16, 0.0), 0.12)
	tween.tween_interval(0.35)
	tween.tween_property(prop, "position", home + Vector3(0.0, -0.05, 0.12), 0.18)
	tween.tween_property(prop, "position", home, 0.22)
	AudioManager.play_3d("noise", prop.global_position, -20.0, 1.3)


## The 2D game leaks into the 3D office: a flat sprite of a game asset stands on
## the desk for a few seconds and is gone again.
func spawn_leaked_object(source_id: String) -> void:
	var at := _leak_anchor()
	var quad := QuadMesh.new()
	quad.size = Vector2(0.32, 0.32)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.35, 0.55, 0.95, 0.85)
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	quad.material = mat
	var mi := MeshInstance3D.new()
	mi.name = "LeakedObject"
	mi.mesh = quad
	mi.position = at
	mi.rotation.y = deg_to_rad(15.0)
	add_child(mi)
	StoryFlags.set_flag(&"leaked_object_in_office", true)
	AudioManager.play_3d("glitch", at, -8.0, 0.8)
	var tween := create_tween()
	tween.tween_property(mi, "position", at + Vector3(0.0, 0.06, 0.0), 0.4)
	tween.tween_interval(LEAK_LIFETIME)
	tween.tween_property(mi, "position", at + Vector3(0.0, 0.5, 0.0), 0.6)
	tween.tween_callback(mi.queue_free)


func _leak_anchor() -> Vector3:
	var doc := get_prop(SHIFT_LOG)
	if doc != null:
		return doc.global_position + Vector3(0.0, 0.22, 0.0)
	return global_position + Vector3(0.0, 1.2, 0.0)


## The office is briefly not the office: the window light goes cold and the desk
## lamp dies, then the room comes back exactly as it was.
func rewrite_office() -> void:
	_rewrite_left = maxf(_rewrite_left, REWRITE_LIFETIME)
	for light: Light3D in _lights:
		if light.name == "DeskLamp":
			light.visible = false
		elif light.name == "WindowLight":
			light.light_color = Color(0.55, 0.68, 0.95)
	AudioManager.play_horror("drone_hit")
	DialogueSystem.queue_line("Свет в офисе не такой, каким вы его оставили.", "OfficeDirector")


func _process(delta: float) -> void:
	_tick_flicker(delta)
	_tick_rewrite(delta)
	_tick_prop_restore(delta)


func _tick_flicker(delta: float) -> void:
	if _flicker_left <= 0.0:
		_restore_light_energy()
		return
	_flicker_left -= delta
	for i in _lights.size():
		_lights[i].light_energy = _light_energy[i] * randf_range(0.05, 1.15)


func _restore_light_energy() -> void:
	for i in _lights.size():
		if _lights[i] != null and is_instance_valid(_lights[i]):
			_lights[i].light_energy = _light_energy[i]


func _tick_rewrite(delta: float) -> void:
	if _rewrite_left <= 0.0:
		return
	_rewrite_left -= delta
	if _rewrite_left > 0.0:
		return
	for light: Light3D in _lights:
		if light == null or not is_instance_valid(light):
			continue
		if light.name == "DeskLamp":
			light.visible = true
		elif light.name == "WindowLight":
			light.light_color = Color(0.78, 0.85, 1.0)
	_restore_light_energy()


func _tick_prop_restore(delta: float) -> void:
	if _prop_restore.is_empty():
		return
	for prop_id: String in _prop_restore.keys().duplicate():
		var left := float(_prop_restore[prop_id]) - delta
		if left <= 0.0:
			_prop_restore.erase(prop_id)
			var prop := get_prop(prop_id)
			if prop != null:
				prop.visible = true
		else:
			_prop_restore[prop_id] = left


# --- persistence ------------------------------------------------------------

func get_save_state() -> Dictionary:
	return {
		"read": _read_ids,
		"colleague_gone": _npc != null and _npc.is_gone(),
		"test_room_open": _door != null and _door.is_opened(),
	}


func apply_save_state(data: Dictionary) -> void:
	_read_ids = PackedStringArray()
	for document_id: Variant in data.get("read", []):
		var id := String(document_id)
		if not _read_ids.has(id):
			_read_ids.append(id)
	if _npc != null:
		_npc.set_gone(bool(data.get("colleague_gone", false)))
	if _door != null:
		_door.set_opened(bool(data.get("test_room_open", false)))
	_restore_read_state()
	_refresh_presence()
