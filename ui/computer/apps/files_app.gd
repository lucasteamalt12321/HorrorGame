extends PanelContainer
## FilesApp — the build tree of the game under test plus the raw test log.
##
## The log is what proves bugs marked UNPHOTOGRAPHABLE: those cannot be captured
## with the camera, so the tester must file them from the system log instead.

@onready var tree_list: ItemList = $VBox/Body/Left/Row/Scroll/Tree
@onready var content: RichTextLabel = $VBox/Body/Right/Scroll/Content
@onready var close: Button = $VBox/Header/Close
@onready var log_button: Button = $VBox/Header/LogButton
@onready var tree_button: Button = $VBox/Header/TreeButton

var _mode: int = 0
var _selected: int = -1

const TREE := [
	"build_0.7.13.exe",
	"levels/L1_GARDEN.txt",
	"levels/L2_PIPES.txt",
	"levels/L3_CLOCKWORK.txt",
	"levels/TEST_ROOM.txt",
	"text/long_english.txt",
	"text/strings_ru.txt",
	"logs/session.log",
	"reports/.git",
]


func _ready() -> void:
	add_to_group("files_app")
	var s := StyleBoxFlat.new()
	s.bg_color = Color(0.06, 0.07, 0.1, 0.98)
	s.border_color = Color(0.2, 0.34, 0.46, 1)
	s.set_border_width_all(1)
	s.set_content_margin_all(4)
	add_theme_stylebox_override("panel", s)
	close.pressed.connect(_on_close)
	log_button.pressed.connect(func() -> void: _set_mode(1))
	tree_button.pressed.connect(func() -> void: _set_mode(0))
	tree_list.item_selected.connect(_on_selected)
	StorySystem.chapter_changed.connect(func(_c: int, _t: String) -> void: refresh())
	refresh()


func _set_mode(value: int) -> void:
	_mode = value
	_selected = -1
	refresh()


func refresh() -> void:
	if not is_inside_tree():
		return
	log_button.disabled = _mode == 1
	tree_button.disabled = _mode == 0
	tree_list.clear()
	if _mode == 0:
		for i in TREE.size():
			tree_list.add_item(_entry_label(i))
		$VBox/Header/Title.text = "ФАЙЛЫ СБОРКИ · NINE CIRCLES 0.7.13"
	else:
		var rows := _log_rows()
		for row: String in rows:
			tree_list.add_item(row)
		$VBox/Header/Title.text = "ЖУРНАЛ ТЕСТИРОВАНИЯ"
	_show(_selected)


func _entry_label(i: int) -> String:
	var path := String(TREE[i])
	if path == "levels/TEST_ROOM.txt":
		if not StoryFlags.has_flag(&"secret_level_found"):
			return "levels/???.txt — не существует"
		return "levels/TEST_ROOM.txt (создан 00:00)"
	if path == "reports/.git":
		return "reports/.git — доступ запрещён"
	return path


func _log_rows() -> PackedStringArray:
	var out := PackedStringArray()
	out.append("[лог] сессия начата")
	out.append("[лог] сборка 0.7.13, профиль QA-07")
	for id in BugSystem.discovered_ids():
		var b := BugSystem.get_bug(id)
		if b == null:
			continue
		if b.kind == BugResource.Kind.UNPHOTOGRAPHABLE:
			out.append("[аномалия] %s — камера недоступна, протокол %s" % [b.id, b.location])
		elif BugSystem.is_reported(id):
			out.append("[отчёт] %s закрыт" % b.id)
		else:
			out.append("[наблюдение] %s" % b.id)
	if StoryFlags.has_flag(&"secret_level_found"):
		out.append("[лог] добавлена папка levels/TEST_ROOM")
	return out


func _on_selected(index: int) -> void:
	AudioManager.play_ui("hover")
	_selected = index
	_show(index)


func _show(index: int) -> void:
	if _mode == 1:
		var rows := _log_rows()
		content.text = rows[index] if index >= 0 and index < rows.size() else "Выберите строку журнала."
		return
	if index < 0 or index >= TREE.size():
		content.text = "Выберите файл."
		return
	var path := String(TREE[index])
	match path:
		"levels/L1_GARDEN.txt":
			content.text = "L1_GARDEN\nСектор: сад за стеной.\nЗамечание QA: маршрут NPC не учитывает коллизии стен (см. BUG_NPC_WALL).\nДлина: 64 плитки."
		"levels/L2_PIPES.txt":
			content.text = "L2_PIPES\nСектор: технические тоннели.\nЗамечание QA: предметы зависают вне коллизий (BUG_FLOAT).\nДлина: 72 плитки."
		"levels/L3_CLOCKWORK.txt":
			content.text = "L3_CLOCKWORK\nСектор: часовой механизм.\nЗамечание QA: анимация стражника зацикливается на одном кадре (BUG_ANIM_LOOP).\nДлина: 80 плиток."
		"levels/TEST_ROOM.txt":
			if StoryFlags.has_flag(&"secret_level_found"):
				content.text = "TEST_ROOM\nФайл создан после вашей последней сессии.\nАвтор: —\nВнутреннее имя сцены: office_copy\nПримечание: «это не должно быть здесь»."
			else:
				content.text = "Файл не найден."
		"text/long_english.txt":
			content.text = "long_english.txt\nСтрок: 1\nСодержимое: LTL\n\n[ последняя правка: сегодня, 03:12, автор не определён ]"
		"text/strings_ru.txt":
			content.text = "strings_ru.txt\nПроверка целостности строк: 1184 из 1184.\nОдна строка не прошла сверку:\n  0812: «ТЫ ЧИТАЕШЬ ЭТО»\nКомментарий: файл не менялся с начала сборки."
		"logs/session.log":
			_set_mode(1)
			content.text = "Открыт журнал тестирования."
		"reports/.git":
			content.text = "fatal: доступ к каталогу запрещён политикой QA.\n\n(Подсказка: отчёты отправляются через баг-трекер.)"
		_:
			content.text = "%s\n\nДвоичный файл. Показать hex нельзя: у вас нет на это прав." % path


func _on_close() -> void:
	AudioManager.play_ui("close")
	ComputerSystem.close_app()