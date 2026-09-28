extends Node
## BugSystem — the registry of every bug in the game under test.
##
## Owns: the bug database, per-bug runtime state (hidden / active / discovered /
## photographed / reported), activation windows and the evidence ledger.
## Does NOT own: photography (PhotoSystem), report filing (ReportSystem),
## story consequences (StorySystem reads signals).

signal bug_activated(bug_id: String)
signal bug_disappeared(bug_id: String)
signal bug_discovered(bug_id: String)
signal bug_photographed(bug_id: String, photo_id: String)
signal bug_reported(bug_id: String)
signal bug_ignored(bug_id: String)
signal database_loaded(count: int)

const BUG_DIR := "res://data/bugs"
const REACTION_WARNING := 6.0

## id -> BugResource
var _db: Dictionary = {}
## id -> state dictionary
var _state: Dictionary = {}

var _active_window_timers: Dictionary = {}
var _reaction_timers: Dictionary = {}
var _activation_counter: int = 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	SaveSystem.register(&"bugs", self)
	load_database()


func _process(delta: float) -> void:
	_tick_windows(delta)


# --- database ---------------------------------------------------------------

func load_database() -> void:
	_db.clear()
	_state.clear()
	var dir := DirAccess.open(BUG_DIR)
	if dir == null:
		push_warning("BugSystem: cannot open %s" % BUG_DIR)
		database_loaded.emit(0)
		return
	var files := dir.get_files()
	files.sort()
	for f: String in files:
		if not f.ends_with(".tres"):
			continue
		var res := load(BUG_DIR.path_join(f))
		if res is BugResource and (res as BugResource).id != "":
			_db[res.id] = res
			_state[res.id] = _fresh_state()
	database_loaded.emit(_db.size())
	if _db.is_empty():
		push_warning("BugSystem: database is empty")


func _fresh_state() -> Dictionary:
	return {
		"status": "hidden",        ## hidden | active | discovered | photographed | reported
		"activations": 0,
		"first_seen_msec": 0,
		"photo_ids": PackedStringArray(),
		"report_submitted": false,
		"ignored": false,
	}


func has_bug(bug_id: String) -> bool:
	return _db.has(bug_id)


func get_bug(bug_id: String) -> BugResource:
	return _db.get(bug_id, null)


func all_bugs() -> Array[BugResource]:
	var out: Array[BugResource] = []
	for k: String in _db.keys():
		out.append(_db[k])
	out.sort_custom(func(a: BugResource, b: BugResource) -> bool: return a.id < b.id)
	return out


func all_bug_ids() -> PackedStringArray:
	var out := PackedStringArray()
	for k: String in _db.keys():
		out.append(k)
	return out


func get_state(bug_id: String) -> Dictionary:
	return _state.get(bug_id, _fresh_state())


func get_status(bug_id: String) -> String:
	return String(get_state(bug_id).get("status", "hidden"))


func is_known(bug_id: String) -> bool:
	return get_status(bug_id) != "hidden"


func is_discovered(bug_id: String) -> bool:
	var s := get_status(bug_id)
	return s in ["discovered", "photographed", "reported"]


func is_photographed(bug_id: String) -> bool:
	var s := get_status(bug_id)
	return s in ["photographed", "reported"]


func is_reported(bug_id: String) -> bool:
	return get_status(bug_id) == "reported"


func is_photo_valid(bug_id: String) -> bool:
	var st := get_state(bug_id)
	var photos: PackedStringArray = st.get("photo_ids", PackedStringArray())
	return not photos.is_empty()


func discovered_count() -> int:
	var n := 0
	for k: String in _db.keys():
		if is_discovered(k):
			n += 1
	return n


func reported_count() -> int:
	var n := 0
	for k: String in _db.keys():
		if is_reported(k):
			n += 1
	return n


func discovered_ids() -> PackedStringArray:
	var out := PackedStringArray()
	for k: String in _db.keys():
		if is_discovered(k):
			out.append(k)
	out.sort()
	return out


func reported_ids() -> PackedStringArray:
	var out := PackedStringArray()
	for k: String in _db.keys():
		if is_reported(k):
			out.append(k)
	out.sort()
	return out


# --- activation -------------------------------------------------------------

## Called by the 2D game (BugTrigger), the office (HorrorSystem) or story beats.
func activate_bug(bug_id: String, duration_override: float = -1.0) -> bool:
	var bug := get_bug(bug_id)
	if bug == null:
		push_warning("BugSystem.activate_bug: unknown id '%s'" % bug_id)
		return false
	if bug.report_required and is_reported(bug_id) and not bug.repeatable:
		return false
	if _activation_is_blocked(bug):
		return false

	var st := get_state(bug_id)
	st["status"] = "active"
	st["activations"] = int(st.get("activations", 0)) + 1
	if int(st.get("first_seen_msec", 0)) == 0:
		st["first_seen_msec"] = Time.get_ticks_msec()
	_state[bug_id] = st
	_activation_counter += 1

	var duration: float = duration_override if duration_override >= 0.0 else bug.active_window
	if duration > 0.0:
		_active_window_timers[bug_id] = duration
	if bug.reaction_window > 0.0:
		_reaction_timers[bug_id] = bug.reaction_window
	bug_activated.emit(bug_id)
	return true


func _activation_is_blocked(bug: BugResource) -> bool:
	if ChapterManager_chapter() < bug.min_chapter:
		return true
	if not bug.required_flags.is_empty() and not StoryFlags.all_set_ids(bug.required_flags):
		return true
	return false


func deactivate_bug(bug_id: String) -> void:
	if get_status(bug_id) != "active":
		return
	_active_window_timers.erase(bug_id)
	_reaction_timers.erase(bug_id)
	var st := get_state(bug_id)
	if st["status"] == "active":
		st["status"] = "discovered"
		_state[bug_id] = st
	bug_disappeared.emit(bug_id)


func _tick_windows(delta: float) -> void:
	if _active_window_timers.is_empty() and _reaction_timers.is_empty():
		return
	for key: String in _active_window_timers.keys().duplicate():
		var t: float = _active_window_timers[key] - delta
		if t <= 0.0:
			_active_window_timers.erase(key)
			deactivate_bug(key)
		else:
			_active_window_timers[key] = t
	for key: String in _reaction_timers.keys().duplicate():
		var t2: float = _reaction_timers[key] - delta
		if t2 <= 0.0:
			_reaction_timers.erase(key)
			# Missed window: still discovered, but no evidence.
			if get_status(key) == "active":
				var st := get_state(key)
				st["status"] = "discovered"
				_state[key] = st
			bug_ignored.emit(key)
		else:
			_reaction_timers[key] = t2


func reaction_time_left(bug_id: String) -> float:
	return float(_reaction_timers.get(bug_id, 0.0))


func active_bug_ids() -> PackedStringArray:
	var out := PackedStringArray()
	for k: String in _db.keys():
		if get_status(k) == "active":
			out.append(k)
	out.sort()
	return out


## Bugs that the level designer said can live on this level index.
func bugs_for_level(level_index: int) -> PackedStringArray:
	var out := PackedStringArray()
	for k: String in _db.keys():
		var b: BugResource = _db[k]
		if b.level_index == level_index:
			out.append(k)
	out.sort()
	return out


func activation_counter() -> int:
	return _activation_counter


# --- discovery / evidence ---------------------------------------------------

func mark_discovered(bug_id: String) -> void:
	if not _db.has(bug_id):
		return
	var st := get_state(bug_id)
	if st["status"] == "hidden":
		st["status"] = "discovered"
		_state[bug_id] = st
		bug_discovered.emit(bug_id)


func register_evidence(evidence: PhotoEvidence) -> bool:
	if evidence == null or evidence.bug_id == "":
		return false
	if not _db.has(evidence.bug_id):
		return false
	var bug := get_bug(evidence.bug_id)
	if bug == null:
		return false
	if bug.kind == BugResource.Kind.UNPHOTOGRAPHABLE:
		# Cannot be captured on purpose: the log is the only evidence.
		mark_discovered(evidence.bug_id)
		return false

	var st := get_state(evidence.bug_id)
	var photos: PackedStringArray = st.get("photo_ids", PackedStringArray())
	var photo_id := evidence.image_ref.trim_prefix("photo:")
	if not photos.has(photo_id):
		photos.append(photo_id)
	st["photo_ids"] = photos
	st["status"] = "photographed"
	_state[evidence.bug_id] = st
	bug_photographed.emit(evidence.bug_id, photo_id)
	return true


func photo_ids_for(bug_id: String) -> PackedStringArray:
	return get_state(bug_id).get("photo_ids", PackedStringArray())


func mark_reported(bug_id: String) -> void:
	var st := get_state(bug_id)
	st["status"] = "reported"
	st["report_submitted"] = true
	_state[bug_id] = st
	bug_reported.emit(bug_id)


func is_photo_needed(bug_id: String) -> bool:
	var b := get_bug(bug_id)
	if b == null:
		return false
	if b.kind == BugResource.Kind.UNPHOTOGRAPHABLE:
		return false
	return b.photo_required and not is_photo_valid(bug_id)


func is_report_needed(bug_id: String) -> bool:
	var b := get_bug(bug_id)
	if b == null:
		return false
	return b.report_required and not is_reported(bug_id)


# --- chapter helper (kept here to avoid a second source of truth) ------------

func ChapterManager_chapter() -> int:
	if has_node("/root/StorySystem"):
		return StorySystem.get_chapter()
	return 0


# --- persistence ------------------------------------------------------------

func get_save_state() -> Dictionary:
	var out := {}
	for k: String in _state.keys():
		var st: Dictionary = _state[k]
		var photos: PackedStringArray = st.get("photo_ids", PackedStringArray())
		out[k] = {
			"status": String(st.get("status", "hidden")),
			"activations": int(st.get("activations", 0)),
			"first_seen_msec": int(st.get("first_seen_msec", 0)),
			"photo_ids": Array(photos),
			"report_submitted": bool(st.get("report_submitted", false)),
			"ignored": bool(st.get("ignored", false)),
		}
	return {
		"discovered": Array(discovered_ids()),
		"reported": Array(reported_ids()),
		"state": out,
		"activation_counter": _activation_counter,
	}


func apply_save_state(data: Dictionary) -> void:
	load_database()
	var st_blob: Dictionary = data.get("state", {})
	for k: String in st_blob.keys():
		if not _state.has(k) or typeof(st_blob[k]) != TYPE_DICTIONARY:
			continue
		var src: Dictionary = st_blob[k]
		var photos := PackedStringArray()
		for p: Variant in src.get("photo_ids", []):
			photos.append(str(p))
		_state[k] = {
			"status": String(src.get("status", "hidden")),
			"activations": int(src.get("activations", 0)),
			"first_seen_msec": int(src.get("first_seen_msec", 0)),
			"photo_ids": photos,
			"report_submitted": bool(src.get("report_submitted", false)),
			"ignored": bool(src.get("ignored", false)),
		}
	_activation_counter = int(data.get("activation_counter", 0))
