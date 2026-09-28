extends PanelContainer
## NotesApp — the tester's own notes: the current assignment, the build's level
## list and the canon glossary. This is the "work" surface of the game.

@onready var tabs: TabContainer = $VBox/Body/Tabs
@onready var task_title: Label = $VBox/Body/Tabs/Task/Box/Title
@onready var task_text: RichTextLabel = $VBox/Body/Tabs/Task/Box/Text
@onready var level_list: ItemList = $VBox/Body/Tabs/Build/Box/Row/Scroll/Levels
@onready var level_note: RichTextLabel = $VBox/Body/Tabs/Build/Box/Note
@onready var canon_text: RichTextLabel = $VBox/Body/Tabs/Glossary/Text
@onready var close: Button = $VBox/Header/Close

var _rows: Array[Dictionary] = []


func _ready() -> void:
	add_to_group("notes_app")
	var s := StyleBoxFlat.new()
	s.bg_color = Color(0.06, 0.07, 0.1, 0.98)
	s.border_color = Color(0.2, 0.34, 0.46, 1)
	s.set_border_width_all(1)
	s.set_content_margin_all(4)
	add_theme_stylebox_override("panel", s)
	tabs.set_tab_title(0, "Задание")
	tabs.set_tab_title(1, "Сборка")
	tabs.set_tab_title(2, "Глоссарий")
	tabs.tab_changed.connect(_on_tab_changed)
	close.pressed.connect(_on_close)
	level_list.item_selected.connect(_on_level_selected)
	level_list.item_activated.connect(_on_level_activated)
	TaskSystem.chapter_hint_changed.connect(func(_h: String) -> void: refresh_task())
	TaskSystem.task_completed.connect(func(_t: String) -> void: refresh_task())
	StorySystem.chapter_changed.connect(func(_c: int, _t: String) -> void: refresh_all())
	refresh_all()


func refresh_all() -> void:
	refresh_task()
	refresh_levels()
	refresh_canon()


func refresh_task() -> void:
	var t := TaskSystem.get_current_task()
	if t == null:
		task_title.text = "Назначений нет"
		task_text.text = "Ожидайте задание от руководителя."
		return
	task_title.text = "%s — %s" % [t.id, t.title]
	var body := t.description
	if t.target_amount > 0:
		body += "\n\nПрогресс: %d / %d" % [TaskSystem.progress_of(t.id), t.target_amount]
	if not t.required_bug_ids.is_empty():
		var done: PackedStringArray = PackedStringArray()
		var all: PackedStringArray = PackedStringArray()
		for b in t.required_bug_ids:
			all.append(String(b))
			if BugSystem.is_reported(String(b)):
				done.append(String(b))
		body += "\n\nПодтверждено: %d / %d" % [done.size(), all.size()]
	if t.hint != "":
		body += "\n\nЗаметка для себя: %s" % t.hint
	body += "\n\nГлава: %s" % StorySystem.chapter_title()
	task_text.text = body


func refresh_levels() -> void:
	_rows = MinigameSystem.build_list()
	level_list.clear()
	for row: Dictionary in _rows:
		var name_text: String = row["name"]
		if not bool(row["unlocked"]):
			name_text = "??? — закрыт"
		if bool(row["secret"]):
			name_text = "[?] %s" % name_text
		level_list.add_item(name_text)
	var cur := MinigameSystem.get_active_level_index()
	if cur >= 0 and cur < _rows.size():
		level_list.select(cur)


func _on_level_selected(index: int) -> void:
	if index < 0 or index >= _rows.size():
		return
	AudioManager.play_ui("hover")
	var row: Dictionary = _rows[index]
	var lvl := MinigameSystem.get_level(int(row["index"]))
	if lvl == null:
		return
	var text := "%s\nРазмер: %d x %d плиток\nАномалий в сборке: %d\n\n%s" % [
		lvl.display_name, lvl.width_tiles, lvl.height_tiles, lvl.bug_ids.size(), lvl.build_note
	]
	if not bool(row["unlocked"]):
		text = "Уровень не открыт текущей сборкой."
	level_note.text = text


func _on_level_activated(index: int) -> void:
	if index < 0 or index >= _rows.size():
		return
	var row: Dictionary = _rows[index]
	if not bool(row["unlocked"]):
		AudioManager.play_computer("error")
		level_note.text = "Уровень не открыт текущей сборкой."
		return
	if MinigameSystem.is_game_running():
		MinigameSystem.go_to_level(int(row["index"]))
	else:
		MinigameSystem.launch_from_desktop(int(row["index"]))
		AudioManager.play_ui("open")


func refresh_canon() -> void:
	canon_text.text = CanonRegistry.render_markdown()


func _on_tab_changed(_idx: int) -> void:
	if tabs.current_tab != 2:
		return
	refresh_canon()
	# Reading the glossary is what actually exposes the tester to the terms, so
	# this is the moment `canon_term_seen` becomes true.
	var fresh := CanonRegistry.mark_all_seen()
	if fresh.is_empty():
		return
	var line := "Глоссарий собран автоматически. Часть терминов не проверена."
	if fresh.size() > 1:
		line = "Новые термины в глоссарии: %d. Ни один не подтверждён." % fresh.size()
	DialogueSystem.queue_line(line, "NotesApp")


func _on_close() -> void:
	AudioManager.play_ui("close")
	ComputerSystem.close_app()