extends Node
## TaskSystem — assignments, their completion rules and the chain that carries
## the story forward. Owns NO story prose: it only raises flags that StorySystem
## and HorrorSystem listen to.

signal task_accepted(task_id: String)
signal task_progress(task_id: String, current: int, target: int)
signal task_completed(task_id: String)
signal task_failed(task_id: String, reason: String)
signal tasks_loaded(count: int)
signal chapter_hint_changed(hint: String)

const TASK_DIR := "res://data/tasks"

var _tasks: Dictionary = {}          ## id -> TaskResource
var _order: Array[String] = []
var _state: Dictionary = {}          ## id -> {state, progress}
var _current_id: String = ""
var _completed: int = 0
var _progress: Dictionary = {}       ## condition_kind -> count
var _documents_read: Dictionary = {} ## document/object id -> true (TALK_TO)

## Runtime counters fed by other systems.
var _photos_taken: int = 0
var _level_reached: int = -1
var _level_won: int = -1
var _died_on_level: int = -1
var _test_room_entered: bool = false
## Guards against a chain of assignments collapsing inside a single frame: a
## freshly activated task always needs at least one fresh event before it can
## complete on its own.
var _activated_frame: int = -1


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	SaveSystem.register(&"tasks", self)
	load_tasks()
	ReportSystem.report_submitted.connect(_on_report_submitted)
	PhotoSystem.photo_taken.connect(_on_photo_taken)
	StoryFlags.flag_changed.connect(_on_flag_changed)


func load_tasks() -> void:
	_tasks.clear()
	_order.clear()
	_state.clear()
	var dir := DirAccess.open(TASK_DIR)
	if dir == null:
		push_warning("TaskSystem: cannot open %s" % TASK_DIR)
		tasks_loaded.emit(0)
		return
	var files := dir.get_files()
	files.sort()
	for f: String in files:
		if not f.ends_with(".tres"):
			continue
		var res := load(TASK_DIR.path_join(f))
		if res is TaskResource and (res as TaskResource).id != "":
			_tasks[res.id] = res
			_order.append(res.id)
	_order.sort_custom(func(a: String, b: String) -> bool:
		var ta: TaskResource = _tasks[a]
		var tb: TaskResource = _tasks[b]
		if ta.order == tb.order:
			return a < b
		return ta.order < tb.order)
	for id: String in _order:
		_state[id] = {"state": TaskResource.State.LOCKED, "progress": 0}
	tasks_loaded.emit(_tasks.size())
	if _tasks.is_empty():
		push_warning("TaskSystem: no tasks loaded")


# --- accessors --------------------------------------------------------------

func get_task(task_id: String) -> TaskResource:
	return _tasks.get(task_id, null)


func all_task_ids() -> PackedStringArray:
	return PackedStringArray(_order)


func get_current_task() -> TaskResource:
	return _tasks.get(_current_id, null)


func get_current_task_id() -> String:
	return _current_id


func get_state(task_id: String) -> int:
	return int(_state.get(task_id, {}).get("state", TaskResource.State.LOCKED))


func is_active(task_id: String) -> bool:
	return get_state(task_id) == TaskResource.State.ACTIVE


func is_completed(task_id: String) -> bool:
	return get_state(task_id) == TaskResource.State.COMPLETED


func progress_of(task_id: String) -> int:
	return int(_state.get(task_id, {}).get("progress", 0))


func completed_count() -> int:
	return _completed


func total_count() -> int:
	return _tasks.size()


func current_hint() -> String:
	var t := get_current_task()
	if t == null:
		return ""
	var p := progress_of(_current_id)
	var c := t.condition_amount()
	if c > 0:
		return "%s (%d/%d)" % [t.brief if t.brief != "" else t.title, mini(p, c), c]
	return t.brief if t.brief != "" else t.title


# --- flow -------------------------------------------------------------------

func start_chain() -> void:
	if not _current_id.is_empty():
		return
	var first := _first_locked()
	if first != "":
		_activate(first)


func _first_locked() -> String:
	for id: String in _order:
		if get_state(id) == TaskResource.State.LOCKED:
			return id
	return ""


func _activate(task_id: String) -> void:
	var t: TaskResource = _tasks.get(task_id)
	if t == null:
		return
	# A closed assignment never reopens. Reactivating one would replay its story
	# beats and its `next_task_id` hand-off, so the chain moves past it instead.
	if is_completed(task_id):
		_state[task_id]["state"] = TaskResource.State.COMPLETED
		var nxt := _first_locked()
		if nxt != "" and nxt != task_id:
			_activate(nxt)
		return
	_state[task_id]["state"] = TaskResource.State.ACTIVE
	_state[task_id]["progress"] = 0
	_current_id = task_id
	_activated_frame = Engine.get_process_frames()
	# Unlocking the next assignment does not activate it: the player must close
	# the current one, which keeps chapter pacing under control.
	if t.reply_email_id != "":
		DialogueSystem.unlock_email(t.reply_email_id)
	task_accepted.emit(task_id)
	chapter_hint_changed.emit(current_hint())


func force_task(task_id: String) -> void:
	# QA hook: it must reach a closed assignment too, otherwise the finale
	# safety net cannot verify the ending after a real playthrough.
	if not _tasks.has(task_id):
		return
	if is_completed(task_id):
		_state[task_id]["state"] = TaskResource.State.ACTIVE
	_activate(task_id)


## QA / debug hook: closes the active assignment right now. Deliberately public
## but unused by gameplay code — it exists so the finale can be reached from a
## test without replaying the whole chain.
func complete_now(reason: String = "debug") -> void:
	_complete_current(reason)


func _complete_current(reason: String = "") -> void:
	if _current_id.is_empty():
		return
	var t: TaskResource = _tasks.get(_current_id)
	var id := _current_id
	# Guard: a task can only be closed once. Without this, a task that both
	# auto-completes and is closed by the chain would inflate the counter.
	if is_completed(id):
		_current_id = ""
		return
	_state[id]["state"] = TaskResource.State.COMPLETED
	_completed = mini(_completed + 1, _tasks.size())
	# Close the slot first: anything that reacts below (flags, signals) must not
	# be able to complete the same assignment twice.
	_current_id = ""
	task_completed.emit(id)
	if t != null:
		for f: String in t.grants_flag:
			StoryFlags.set_flag(StringName(f), true)
		if t.reply_email_id != "":
			DialogueSystem.unlock_email(t.reply_email_id)
		if t.sets_tension >= 0:
			HorrorSystem.set_tension(t.sets_tension)
		if t.next_task_id != "" and _tasks.has(t.next_task_id) and not is_completed(t.next_task_id):
			_activate(t.next_task_id)
			return
		var nxt := _first_locked()
		if nxt != "":
			_activate(nxt)


func abandon_current(reason: String) -> void:
	if _current_id.is_empty():
		return
	_state[_current_id]["state"] = TaskResource.State.FAILED
	task_failed.emit(_current_id, reason)
	var nxt := _first_locked()
	if nxt == "":
		_current_id = ""
		return
	_activate(nxt)


# --- condition evaluation ---------------------------------------------------

func notify_bug_reported(bug_id: String, task_id: String = "") -> void:
	if not _current_id.is_empty():
		_progress[TaskResource.Condition.REPORT_BUGS] = int(_progress.get(TaskResource.Condition.REPORT_BUGS, 0)) + 1
	_evaluate("bug_reported:%s" % bug_id)


func notify_level_reached(index: int) -> void:
	_level_reached = index
	_progress[TaskResource.Condition.REACH_LEVEL] = index
	_evaluate("level_reached:%d" % index)


func notify_level_won(index: int) -> void:
	_level_won = index
	_progress[TaskResource.Condition.WIN_LEVEL] = index
	_evaluate("level_won:%d" % index)


func notify_died_on_level(index: int) -> void:
	_died_on_level = index
	_progress[TaskResource.Condition.DIE_ON_LEVEL] = index
	_evaluate("died:%d" % index)


func notify_test_room_entered() -> void:
	_test_room_entered = true
	_progress[TaskResource.Condition.ENTER_TEST_ROOM] = 1
	_evaluate("test_room")


func notify_photo_taken() -> void:
	_photos_taken += 1
	_progress[TaskResource.Condition.PHOTOGRAPH_ANY] = _photos_taken
	_evaluate("photo")


func _on_photo_taken(_record: PhotoRecord) -> void:
	notify_photo_taken()


func notify_story_flag(flag: StringName) -> void:
	_evaluate("flag:%s" % flag)


func notify_document_read(doc_id: String) -> void:
	if doc_id == "":
		return
	# The same document can be re-read; only distinct objects count.
	if not _documents_read.has(doc_id):
		_documents_read[doc_id] = true
		_progress[TaskResource.Condition.TALK_TO] = _documents_read.size()
	_evaluate("doc:%s" % doc_id)


## Raw counter behind a condition kind (documents read, photos taken, levels
## won). Read by the HUD and by the smoke test; it is not a task completion.
func condition_progress(kind: int) -> int:
	return int(_progress.get(kind, 0))


func _on_report_submitted(rec: BugReportRecord) -> void:
	# The counting already happened in notify_bug_reported(); this re-evaluation
	# exists so a report filed while a *different* task was active still lets
	# the chain re-check its requirements exactly once.
	if rec == null:
		return
	_evaluate("report_submitted:%s" % rec.bug_id)


func _on_flag_changed(flag: StringName, value: Variant) -> void:
	if bool(value):
		notify_story_flag(flag)


func _evaluate(reason: String) -> void:
	var t := get_current_task()
	if t == null:
		return
	if not is_active(_current_id):
		# The current assignment is already closed (or never opened): a stale
		# event must not reopen or re-complete it.
		return
	if _activated_frame == Engine.get_process_frames():
		# Task became active during this very frame: wait for a real event.
		return
	if t.auto_complete:
		_complete_current()
		return
	var kind := t.condition_kind()
	if kind < 0:
		if t.required_flag != &"" and StoryFlags.has_flag(t.required_flag):
			_complete_current()
		return

	var current := _condition_value(kind)
	var target := t.condition_amount()
	if kind == TaskResource.Condition.STORY_FLAG and t.required_flag != &"":
		if not StoryFlags.has_flag(t.required_flag):
			return
		_complete_current()
		return
	if kind == TaskResource.Condition.REPORT_BUGS and not t.required_bug_ids.is_empty():
		var all := true
		for bug_id in t.required_bug_ids:
			if not BugSystem.is_reported(bug_id):
				all = false
				break
		_progress[kind] = _count_reported_from(t)
		current = _progress[kind]
		if not all:
			_emit_progress(t, current, t.required_bug_ids.size())
			return
		_complete_current()
		return
	if kind == TaskResource.Condition.WIN_LEVEL and t.target_level >= 0:
		if _level_won < t.target_level:
			_emit_progress(t, maxi(0, _level_won), t.target_level)
			return
		_complete_current()
		return
	if kind == TaskResource.Condition.REACH_LEVEL and t.target_level >= 0:
		if _level_reached < t.target_level:
			_emit_progress(t, maxi(0, _level_reached), t.target_level)
			return
		_complete_current()
		return
	if kind == TaskResource.Condition.DIE_ON_LEVEL and t.target_level >= 0:
		if _died_on_level != t.target_level:
			return
		_complete_current()
		return

	if kind == TaskResource.Condition.ENTER_TEST_ROOM:
		# T09 must not close on activation: the tester has to actually find the
		# 2D copy of the office, and that is only reported by notify_test_room_entered().
		_progress[kind] = 1 if _test_room_entered else 0
		current = _progress[kind]
		if not _test_room_entered:
			_emit_progress(t, 0, 1)
			return
		_complete_current()
		return
	if kind == TaskResource.Condition.TALK_TO:
		# The document/objects read so far; each interactable calls
		# notify_document_read() exactly once per distinct object.
		current = int(_progress.get(kind, 0))
		if current < target:
			_emit_progress(t, current, target)
			return
		_complete_current()
		return
	if target > 0 and current < target:
		_emit_progress(t, current, target)
		return
	_complete_current()


func _count_reported_from(t: TaskResource) -> int:
	var n := 0
	for bug_id in t.required_bug_ids:
		if BugSystem.is_reported(bug_id):
			n += 1
	return n


func _condition_value(kind: int) -> int:
	match kind:
		TaskResource.Condition.REPORT_BUGS:
			return int(_progress.get(kind, 0))
		TaskResource.Condition.REACH_LEVEL:
			return maxi(0, int(_progress.get(kind, -1)))
		TaskResource.Condition.WIN_LEVEL:
			return maxi(0, int(_progress.get(kind, -1)))
		TaskResource.Condition.DIE_ON_LEVEL:
			return int(_progress.get(kind, -1))
		TaskResource.Condition.ENTER_TEST_ROOM:
			return int(_progress.get(kind, 0))
		TaskResource.Condition.PHOTOGRAPH_ANY:
			return int(_progress.get(kind, 0))
		TaskResource.Condition.ENTER_TEST_ROOM:
			return 1 if _test_room_entered else 0
		TaskResource.Condition.TALK_TO:
			return int(_progress.get(kind, 0))
		_:
			return 0


func _emit_progress(t: TaskResource, current: int, target: int) -> void:
	_state[_current_id]["progress"] = current
	task_progress.emit(_current_id, current, target)
	chapter_hint_changed.emit(current_hint())


# --- persistence ------------------------------------------------------------

func get_save_state() -> Dictionary:
	var st := {}
	for id: String in _state.keys():
		st[id] = {
			"state": int(_state[id]["state"]),
			"progress": int(_state[id]["progress"]),
		}
	return {
		"current_id": _current_id,
		"completed": _completed,
		"state": st,
		"counters": {
			"photos": _photos_taken,
			"level_reached": _level_reached,
			"level_won": _level_won,
			"died_on_level": _died_on_level,
			"test_room": _test_room_entered,
			"documents": _documents_read.keys(),
		},
	}


func apply_save_state(data: Dictionary) -> void:
	load_tasks()
	var st: Dictionary = data.get("state", {})
	for id: String in st.keys():
		if _state.has(id) and typeof(st[id]) == TYPE_DICTIONARY:
			_state[id] = {
				"state": int(st[id].get("state", TaskResource.State.LOCKED)),
				"progress": int(st[id].get("progress", 0)),
			}
	_current_id = String(data.get("current_id", ""))
	_completed = int(data.get("completed", 0))
	var c: Dictionary = data.get("counters", {})
	_photos_taken = int(c.get("photos", 0))
	_level_reached = int(c.get("level_reached", -1))
	_level_won = int(c.get("level_won", -1))
	_died_on_level = int(c.get("died_on_level", -1))
	_test_room_entered = bool(c.get("test_room", false))
	_documents_read.clear()
	_progress[TaskResource.Condition.TALK_TO] = 0
	for doc_id: Variant in c.get("documents", []):
		_documents_read[String(doc_id)] = true
	_progress[TaskResource.Condition.TALK_TO] = _documents_read.size()
	chapter_hint_changed.emit(current_hint())
