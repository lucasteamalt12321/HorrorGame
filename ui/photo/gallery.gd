extends PanelContainer
## Gallery — Tab. The QA photo archive.
##
## Photos stay in memory for the whole session (never written to disk). The
## gallery is also the place where the player can attach evidence to a bug, and
## where mutated photos become obvious.

@onready var grid: GridContainer = $VBox/Body/Left/Scroll/Center/Grid
@onready var preview: TextureRect = $VBox/Body/Right/Preview
@onready var meta: RichTextLabel = $VBox/Body/Right/Scroll/Meta
@onready var empty: Label = $VBox/Body/Left/Empty
@onready var attach: Button = $VBox/Body/Right/Attach
@onready var close: Button = $VBox/Header/Close
@onready var counter: Label = $VBox/Header/Counter

var _index: int = -1
var _slots: Array[Button] = []


func _ready() -> void:
	add_to_group("gallery")
	var s := StyleBoxFlat.new()
	s.bg_color = Color(0.04, 0.05, 0.07, 0.96)
	s.border_color = Color(0.25, 0.35, 0.5, 1)
	s.set_border_width_all(1)
	s.set_content_margin_all(6)
	add_theme_stylebox_override("panel", s)
	close.pressed.connect(_on_close)
	attach.pressed.connect(_on_attach)
	attach.disabled = true
	PhotoSystem.photo_count_changed.connect(func(_c: int) -> void: refresh())
	refresh()


func _on_close() -> void:
	AudioManager.play_ui("close")
	if is_inside_tree():
		get_tree().get_first_node_in_group("game_root").close_gallery()


func _on_attach() -> void:
	var rec := _current()
	if rec == null or rec.bug_id == "":
		return
	ReportSystem.attach_photo(rec.id, rec.bug_id)
	AudioManager.play_ui("click")
	refresh()


func _current() -> PhotoRecord:
	if _index < 0 or _index >= PhotoSystem.photos.size():
		return null
	return PhotoSystem.photos[_index]


func refresh() -> void:
	for b in _slots:
		if is_instance_valid(b):
			b.queue_free()
	_slots.clear()
	var photos := PhotoSystem.photos
	counter.text = "%d / %d" % [photos.size(), PhotoSystem.MAX_PHOTOS]
	empty.visible = photos.is_empty()
	for i in photos.size():
		var rec := photos[i]
		var b := Button.new()
		b.custom_minimum_size = Vector2(76, 60)
		b.focus_mode = Control.FOCUS_NONE
		b.tooltip_text = rec.id
		var tex := rec.make_texture()
		if tex != null:
			b.icon = tex
			b.expand_icon = true
		else:
			b.text = rec.id
		var mark := "•" if rec.valid else " "
		if rec.mutation_level > 0:
			mark = "!"
		b.text = "%s %s" % [mark, rec.id]
		b.pressed.connect(func() -> void:
			AudioManager.play_ui("hover")
			select(i))
		grid.add_child(b)
		_slots.append(b)
	if _index >= photos.size():
		_index = photos.size() - 1
	if not photos.is_empty():
		if _index < 0:
			select(photos.size() - 1)
		else:
			_show()


func select(i: int) -> void:
	_index = i
	_show()


func _show() -> void:
	var rec := _current()
	if rec == null:
		preview.texture = null
		meta.text = "Архив пуст."
		attach.disabled = true
		return
	preview.texture = rec.make_texture()
	attach.disabled = rec.bug_id == ""
	var lines := PackedStringArray()
	lines.append("[b]%s[/b]" % rec.id)
	lines.append("источник: %s" % ("камера в офисе" if rec.source == "office" else "камера монитора"))
	lines.append("снимок сделан: %s" % rec.time_string())
	lines.append("глава: %d" % rec.chapter)
	if rec.bug_id != "":
		lines.append("аномалия: %s" % rec.bug_id)
		lines.append("подтверждение: %s" % ("принято" if rec.valid else "не подтверждено"))
	else:
		lines.append("аномалия: не распознана")
	if rec.mutation_level > 0:
		lines.append("[color=#d06a6a]редактура: снимок менялся (rev.%d)[/color]" % (rec.mutation_level + 1))
	lines.append("объект в кадре: %s" % rec.label)
	if rec.valid and ReportSystem.has_photo(rec.id):
		lines.append("приложено к отчёту: да")
	meta.text = "\n".join(lines)
