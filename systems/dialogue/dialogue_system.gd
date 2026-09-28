extends Node
## DialogueSystem — e-mail client data, subtitle lines and readable documents.
##
## Presentation lives in ui/computer/*; this system owns the mailbox, the
## subtitle queue and the meta-horror text mutations.

signal inbox_changed()
signal unread_changed(count: int)
signal email_unlocked(email_id: String)
signal line_shown(text: String, source: String)
signal line_queue_drained()
signal document_read(doc_id: String)

const EMAIL_DIR := "res://data/emails"
const DOCUMENT_DIR := "res://data/documents"
const LINE_VISIBLE_TIME := 3.4

var _emails: Array[EmailResource] = []
var _by_id: Dictionary = {}
var _unlocked: Dictionary = {}
var _read: Dictionary = {}
var _mutated: Dictionary = {}
var _docs: Array[EmailResource] = []
var _doc_by_id: Dictionary = {}

var _queue: Array[Dictionary] = []
var _current: Dictionary = {}
var _timer: float = 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	load_database()
	SaveSystem.register(&"dialogue", self)


func load_database() -> void:
	_emails.clear()
	_by_id.clear()
	_docs.clear()
	_doc_by_id.clear()
	_scan(EMAIL_DIR, false)
	_scan(DOCUMENT_DIR, true)
	if _emails.is_empty():
		push_warning("DialogueSystem: no e-mails loaded")


func _scan(dir_path: String, as_document: bool) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	var files := dir.get_files()
	files.sort()
	for f: String in files:
		if not f.ends_with(".tres"):
			continue
		var res := load(dir_path.path_join(f))
		if res is not EmailResource:
			continue
		var mail := res as EmailResource
		if mail.id == "":
			continue
		if as_document:
			_docs.append(mail)
			_doc_by_id[mail.id] = mail
		else:
			_emails.append(mail)
			_by_id[mail.id] = mail
			if mail.read_by_default:
				_read[mail.id] = true


# --- mailbox ----------------------------------------------------------------

func unlock_email(email_id: String) -> void:
	if _by_id.is_empty():
		return
	if not _by_id.has(email_id):
		push_warning("DialogueSystem: unknown e-mail '%s'" % email_id)
		return
	if _unlocked.get(email_id, false):
		return
	_unlocked[email_id] = true
	_grant_flags(_by_id[email_id])
	email_unlocked.emit(email_id)
	inbox_changed.emit()
	_refresh_unread()


func get_inbox() -> Array[EmailResource]:
	var out: Array[EmailResource] = []
	for mail in _emails:
		if not bool(_unlocked.get(mail.id, false)):
			continue
		if mail.hidden and not bool(_mutated.get(mail.id, false)):
			continue
		out.append(mail)
	out.sort_custom(func(a: EmailResource, b: EmailResource) -> bool:
		if a.sorted_by_time and b.sorted_by_time:
			return a.chapter < b.chapter
		return a.id < b.id)
	return out


func get_email(email_id: String) -> EmailResource:
	if not _by_id.has(email_id):
		return null
	if not bool(_unlocked.get(email_id, false)):
		return null
	return _by_id[email_id]


func is_unlocked(email_id: String) -> bool:
	return bool(_unlocked.get(email_id, false))


func is_read(email_id: String) -> bool:
	return bool(_read.get(email_id, false))


func mark_read(email_id: String) -> void:
	if not _by_id.has(email_id):
		return
	if _read.get(email_id, false):
		return
	_read[email_id] = true
	# Reading is the trigger, not delivery: mail_05 asks the question, mail_10
	# starts the last test. Reached mails restored from a save grant here too.
	_grant_flags(_by_id[email_id])
	_refresh_unread()
	inbox_changed.emit()


func _grant_flags(mail: EmailResource) -> void:
	if mail == null or mail.grants_flag == &"":
		return
	StoryFlags.set_flag(mail.grants_flag, true)


func unread_count() -> int:
	var n := 0
	for mail in _emails:
		if not bool(_unlocked.get(mail.id, false)):
			continue
		if not bool(_read.get(mail.id, false)):
			n += 1
	return n


func _refresh_unread() -> void:
	unread_changed.emit(unread_count())


func email_body(mail: EmailResource) -> String:
	if mail == null:
		return ""
	var body := mail.body
	if bool(_mutated.get(mail.id, false)):
		body = _mutate_body(body, mail.id)
	return body


# --- meta-horror: the text rewrites itself ----------------------------------

func mutate_text(text_id: String) -> bool:
	if text_id == "":
		return false
	if not bool(Settings.get_value("text_mutation_enabled", true)):
		return false
	if _by_id.has(text_id):
		_mutated[text_id] = true
		_read.erase(text_id)
		inbox_changed.emit()
		_refresh_unread()
		queue_line("Текст на экране изменился, пока вы не смотрели.", "DialogueSystem")
		return true
	for line: Dictionary in _queue:
		if line.get("source", "") == text_id:
			line["text"] = _mutate_line(String(line.get("text", "")))
			return true
	if _current.get("source", "") == text_id:
		_current["text"] = _mutate_line(String(_current.get("text", "")))
		return true
	return false


func is_mutated(text_id: String) -> bool:
	return bool(_mutated.get(text_id, false))


func _mutate_body(body: String, seed_id: String) -> String:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(seed_id)
	var lines := body.split("\n")
	var out: PackedStringArray = PackedStringArray()
	for l: String in lines:
		if rng.randf() < 0.25:
			out.append(_mutate_line(l))
		else:
			out.append(l)
	out.append("")
	out.append("[ сообщение изменено · правка не авторская ]")
	return "\n".join(out)


func _mutate_line(text: String) -> String:
	var pool := [
		"ты читаешь это",
		"мы видим, куда ты смотришь",
		"уровень пройден",
		"тестировщик обнаружен",
		"LTL",
		"проверка продолжается",
	]
	return String(pool[randi() % pool.size()])


# --- subtitle lines ---------------------------------------------------------

func queue_line(text: String, source: String = "") -> void:
	if text.strip_edges() == "":
		return
	_queue.append({"text": text, "source": source})
	_pump_queue()


func say_now(text: String, source: String = "") -> void:
	_queue.clear()
	_current = {"text": text, "source": source}
	_timer = LINE_VISIBLE_TIME
	line_shown.emit(text, source)


func _pump_queue() -> void:
	if not _current.is_empty() or _queue.is_empty():
		return
	_current = _queue.pop_front()
	_timer = LINE_VISIBLE_TIME
	line_shown.emit(String(_current.get("text", "")), String(_current.get("source", "")))


func _process(delta: float) -> void:
	if _current.is_empty():
		return
	_timer -= delta
	if _timer <= 0.0:
		_current = {}
		if _queue.is_empty():
			line_queue_drained.emit()
		else:
			_pump_queue()


func current_line() -> String:
	return String(_current.get("text", ""))


# --- documents --------------------------------------------------------------

func get_documents() -> Array[EmailResource]:
	return _docs


func get_document(doc_id: String) -> EmailResource:
	return _doc_by_id.get(doc_id, null)


func read_document(doc_id: String) -> void:
	var doc := get_document(doc_id)
	if doc == null:
		return
	document_read.emit(doc_id)
	TaskSystem.notify_document_read(doc_id)


# --- persistence ------------------------------------------------------------

func get_save_state() -> Dictionary:
	return {
		"unlocked": _unlocked.keys(),
		"read": _read.keys(),
		"mutated": _mutated.keys(),
	}


func apply_save_state(data: Dictionary) -> void:
	_unlocked.clear()
	_read.clear()
	_mutated.clear()
	for k: Variant in data.get("unlocked", []):
		_unlocked[str(k)] = true
	for k: Variant in data.get("read", []):
		_read[str(k)] = true
	for k: Variant in data.get("mutated", []):
		_mutated[str(k)] = true
	inbox_changed.emit()
	_refresh_unread()
