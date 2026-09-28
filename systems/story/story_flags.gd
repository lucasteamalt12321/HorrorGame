extends Node
## StoryFlags — the single source of truth for story state.
##
## No system stores story logic locally. Systems READ flags; they only set them
## through `set_flag`, which emits `flag_changed` so the rest of the game
## (horror, story, audio, UI) can react. Rule 8 of the brief.

signal flag_changed(flag: StringName, value: Variant)
signal any_flag_changed()

const FLAG_DEFINITIONS := {
	# --- prologue / chapter 1 ---
	&"intro_seen": false,
	&"task_01_given": false,
	&"first_bug_reported": false,
	&"first_reply_received": false,
	# --- chapter 2: impossible NPC ---
	&"met_unknown_npc": false,
	&"npc_watched_player": false,
	# --- chapter 3: mutating photographs ---
	&"photo_changed": false,
	&"photo_gallery_opened": false,
	# --- chapter 4: LTL ---
	&"found_ltl": false,
	&"ltl_mentioned_in_build": false,
	# --- chapter 5: the game notices the player ---
	&"game_noticed_player": false,
	&"cursor_followed": false,
	&"developers_stopped_replying": false,
	# --- chapter 6: TEST_ROOM ---
	&"entered_test_room": false,
	&"saw_office_in_game": false,
	&"test_room_exit_hidden": false,
	# --- chapter 7: canon ---
	&"canon_term_seen": false,
	&"canon_question_sent": false,
	# --- chapter 8 ---
	&"office_emptied": false,
	&"colleague_photo_found": false,
	# --- chapter 9: boundary violation ---
	&"boundary_breached": false,
	&"leaked_object_in_office": false,
	&"player_avatar_seen": false,
	# --- finale ---
	&"final_test_started": false,
	&"ending_reached": false,
	# --- meta ---
	&"saw_pause_movement": false,
	&"saw_pause_anomaly": false,
	&"npc_moved_while_paused": false,
	&"report_file_mutated": false,
	&"secret_level_found": false,
	&"htn_unlocked": false,
}

var _flags: Dictionary = {}
var _loaded: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	reset()


func reset() -> void:
	_flags = FLAG_DEFINITIONS.duplicate(true)
	_loaded = false


func load_dict(data: Dictionary) -> void:
	reset()
	for key: Variant in data.keys():
		var flag := StringName(str(key))
		if _flags.has(flag):
			_flags[flag] = _coerce(_flags[flag], data[key])
	_loaded = true
	any_flag_changed.emit()


func to_dict() -> Dictionary:
	return _flags.duplicate(true)


func has_flag(flag: StringName) -> bool:
	return bool(_flags.get(flag, false))


func get_flag(flag: StringName, default_value: Variant = false) -> Variant:
	return _flags.get(flag, default_value)


func set_flag(flag: StringName, value: Variant = true) -> void:
	var coerced: Variant = _coerce(_flags.get(flag, false), value)
	if _flags.get(flag) == coerced:
		return
	_flags[flag] = coerced
	flag_changed.emit(flag, coerced)
	any_flag_changed.emit()


func all_set(flags: Array) -> bool:
	for f: Variant in flags:
		if not has_flag(StringName(str(f))):
			return false
	return true


func all_set_ids(ids: PackedStringArray) -> bool:
	return all_set(Array(ids))


func count_set() -> int:
	var n := 0
	for k: Variant in _flags.keys():
		if bool(_flags[k]):
			n += 1
	return n


func _coerce(current: Variant, value: Variant) -> Variant:
	if current is bool:
		return bool(value)
	if current is int or current is float:
		return value
	if current is String:
		return str(value)
	return value
