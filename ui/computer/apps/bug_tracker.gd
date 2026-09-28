extends PanelContainer
## BugTracker — the in-game QA tool: the list of everything the tester has
## found, and the report composer. Presentation only; all rules live in
## BugSystem / ReportSystem.

signal report_filed(bug_id: String)

@onready var list: ItemList = $VBox/Body/Split/Left/Row/Scroll/List
@onready var detail_title: Label = $VBox/Body/Split/Right/Scroll/Detail/Title
@onready var detail_body: RichTextLabel = $VBox/Body/Split/Right/Scroll/Detail/Body
@onready var photo_label: Label = $VBox/Body/Split/Right/Scroll/Detail/Photos
@onready var comment: TextEdit = $VBox/Body/Split/Right/Form/Comment
@onready var submit: Button = $VBox/Body/Split/Right/Form/Actions/Submit
@onready var status: Label = $VBox/Status
@onready var counter: Label = $VBox/Header/Counter

var _rows: Array[Dictionary] = []
var _selected: String = ""


func _ready() -> void:
	add_to_group("bug_tracker")
	add_theme_stylebox_override("panel", _make_window_style())
	$VBox/Header/Close.pressed.connect(_on_close)
	$VBox/Body/Split/Right/Form/Actions/Submit.pressed.connect(_on_submit)
	$VBox/Body/Split/Right/Form/Actions/Gallery.pressed.connect(_on_gallery)
	list.item_selected.connect(_on_selected)
	ReportSystem.tracker_changed.connect(refresh)
	ReportSystem.report_opened.connect(_on_report_opened)
	BugSystem.bug_discovered.connect(func(_id: String) -> void: refresh())
	StorySystem.chapter_changed.connect(func(_c: int, _t: String) -> void: refresh())
	refresh()


func _make_window_style() -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = Color(0.06, 0.07, 0.1, 0.98)
	s.border_color = Color(0.2, 0.34, 0.46, 1)
	s.set_border_width_all(1)
	s.set_corner_radius_all(2)
	s.set_content_margin_all(4)
	return s


func refresh() -> void:
	if not is_inside_tree():
		return
	_rows = ReportSystem.build_tracker()
	list.clear()
	for row: Dictionary in _rows:
		var mark := " "
		if bool(row["reported"]):
			mark = "x"
		elif bool(row["photo_valid"]):
			mark = "*"
		elif bool(row["photo_required"]):
			mark = "o"
		list.add_item("[%s] %s" % [mark, row["title"]])
	counter.text = "Открыто: %d   Отправлено: %d / %d" % [
		_rows.size(), ReportSystem.reported_count(), BugSystem.all_bugs().size()
	]
	_show_detail(_selected)


func _on_selected(index: int) -> void:
	if index < 0 or index >= _rows.size():
		return
	_selected = String(_rows[index]["id"])
	AudioManager.play_ui("hover")
	_show_detail(_selected)


func _show_detail(bug_id: String) -> void:
	if bug_id == "":
		detail_title.text = "Выберите запись"
		detail_body.text = "Список заполняется по мере находок.\nДоказательство: ЛКМ в кадре аномалии."
		photo_label.text = ""
		submit.disabled = true
		return
	var bug := BugSystem.get_bug(bug_id)
	if bug == null:
		return
	detail_title.text = "%s  [%s / %s]" % [bug.title, bug.category_label(), bug.severity_label()]
	detail_body.text = "%s\n\nЛокация: %s\nПорог серьёзности: %d\n\nПодсказка: %s" % [
		bug.description, bug.location, bug.severity, bug.hint
	]
	var photos := BugSystem.photo_ids_for(bug_id)
	var names: PackedStringArray = PackedStringArray()
	for p in photos:
		names.append(p)
	photo_label.text = "Доказательства: %s" % (", ".join(names) if names.size() > 0 else "нет")
	var can := ReportSystem.can_submit(bug_id)
	submit.disabled = not can
	submit.text = "Отчёт отправлен" if BugSystem.is_reported(bug_id) else "Отправить отчёт"
	if BugSystem.is_reported(bug_id):
		# A filed report has its own thread, so re-selecting a reported row shows
		# the thread instead of the raw bug hint - the report is the useful text.
		detail_body.text = ReportSystem.report_body(bug_id)
		status.text = "Отчёт принят. Ответ разработчиков в почте."
		status.add_theme_color_override("font_color", Color(0.45, 0.85, 0.5, 1))
	elif bug.photo_required and not BugSystem.is_photo_valid(bug_id):
		status.text = ReportSystem.REJECT_NO_EVIDENCE
		status.add_theme_color_override("font_color", Color(0.95, 0.5, 0.4, 1))
	else:
		status.text = "Готово к отправке."
		status.add_theme_color_override("font_color", Color(0.75, 0.8, 0.9, 1))


## ReportSystem announces that a thread was opened (including a repeat open).
## The tracker shows it when the thread is the one on screen.
func _on_report_opened(bug_id: String) -> void:
	if bug_id == _selected:
		show_report(bug_id)


func _on_submit() -> void:
	if _selected == "":
		return
	var rec := ReportSystem.submit(_selected, comment.text, TaskSystem.get_current_task_id())
	if rec != null:
		comment.text = ""
		report_filed.emit(_selected)
		show_report(_selected)
		refresh()


func show_report(bug_id: String) -> void:
	detail_body.text = ReportSystem.report_body(bug_id)
	status.text = "Отчёт зарегистрирован: %s" % bug_id
	status.add_theme_color_override("font_color", Color(0.45, 0.85, 0.5, 1))


func _on_close() -> void:
	AudioManager.play_ui("close")
	ComputerSystem.close_app()


func _on_gallery() -> void:
	# The photo archive is a 3D-side layer (GameRoot), shared by the tracker and
	# the Tab key: the app never owns it.
	var root := get_tree().get_first_node_in_group("game_root")
	if root != null and root.has_method("open_gallery"):
		root.call("open_gallery")
