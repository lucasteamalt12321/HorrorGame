extends PanelContainer
## MailApp — the in-game inbox. Read-only content comes from EmailResource
## data; the only logic is read/unread bookkeeping (which DialogueSystem owns).

@onready var list: ItemList = $VBox/Body/Left/Row/Scroll/List
@onready var from_label: Label = $VBox/Body/Right/Scroll/Reader/From
@onready var subject_label: Label = $VBox/Body/Right/Scroll/Reader/Subject
@onready var body_label: RichTextLabel = $VBox/Body/Right/Scroll/Reader/Body
@onready var close: Button = $VBox/Header/Close
@onready var unread_label: Label = $VBox/Header/Unread

var _mail: Array[EmailResource] = []
var _selected: String = ""


func _ready() -> void:
	add_to_group("mail_app")
	var s := StyleBoxFlat.new()
	s.bg_color = Color(0.06, 0.07, 0.1, 0.98)
	s.border_color = Color(0.2, 0.34, 0.46, 1)
	s.set_border_width_all(1)
	s.set_content_margin_all(4)
	add_theme_stylebox_override("panel", s)

	close.pressed.connect(_on_close)
	list.item_selected.connect(_on_selected)
	DialogueSystem.inbox_changed.connect(refresh)
	DialogueSystem.unread_changed.connect(func(_n: int) -> void: refresh())
	refresh()


func refresh() -> void:
	if not is_inside_tree():
		return
	_mail = DialogueSystem.get_inbox()
	var keep := _selected
	list.clear()
	for mail in _mail:
		var mark := "" if DialogueSystem.is_read(mail.id) else "* "
		list.add_item("%s%s" % [mark, mail.subject])
	unread_label.text = "непрочитанных: %d" % DialogueSystem.unread_count()
	if keep != "":
		var idx := _mail.find_custom(func(m: EmailResource) -> bool: return m.id == keep)
		if idx >= 0:
			list.select(idx)
			_open(_mail[idx])
	else:
		_clear()


func _on_selected(index: int) -> void:
	if index < 0 or index >= _mail.size():
		return
	AudioManager.play_ui("hover")
	_open(_mail[index])


func _open(mail: EmailResource) -> void:
	_selected = mail.id
	from_label.text = "От: %s <%s>" % [mail.sender_name, mail.sender_address]
	subject_label.text = mail.subject
	body_label.text = DialogueSystem.email_body(mail)
	DialogueSystem.mark_read(mail.id)
	refresh()


func _clear() -> void:
	from_label.text = "От: —"
	subject_label.text = "Нет непрочитанных сообщений"
	body_label.text = "Папка пуста.\n\nПродолжайте тестирование сборки."


func _on_close() -> void:
	AudioManager.play_ui("close")
	ComputerSystem.close_app()