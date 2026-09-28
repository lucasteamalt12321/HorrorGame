extends Node
## MinigameSystem — owns the game under test.
##
## The 2D game is instantiated INSIDE the monitor's SubViewport: it is part of
## the game world, never a separate OS window. This system only routes commands
## (start/stop/level select) and exposes read-only state for PhotoSystem,
## TaskSystem and HorrorSystem.

signal game_started(level_index: int, level_id: String)
signal game_stopped(reason: String)
signal level_started(level_index: int, level_id: String)
signal level_completed(level_index: int)
signal level_failed(level_index: int)
signal state_changed()
signal secret_level_unlocked(level_index: int)

const LEVEL_DIR := "res://data/levels"
const GAME_SCENE := "res://minigame/minigame.tscn"
const SECRET_LEVEL_ID := "TEST_ROOM"

var _levels: Array[LevelResource] = []
var _by_id: Dictionary = {}
var _game: Node = null
var _unlocked: Dictionary = {}
var _active_index: int = -1
var _running: bool = false
var _last_stop_reason: String = ""


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	SaveSystem.register(&"minigame", self)
	load_levels()


# --- level database ---------------------------------------------------------

func load_levels() -> void:
	_levels.clear()
	_by_id.clear()
	var dir := DirAccess.open(LEVEL_DIR)
	if dir == null:
		push_warning("MinigameSystem: cannot open %s" % LEVEL_DIR)
		return
	var files := dir.get_files()
	files.sort()
	for f: String in files:
		if not f.ends_with(".tres"):
			continue
		var res := load(LEVEL_DIR.path_join(f))
		if res is LevelResource and (res as LevelResource).id != "":
			_levels.append(res)
			_by_id[res.id] = res
	_levels.sort_custom(func(a: LevelResource, b: LevelResource) -> bool: return a.id < b.id)
	for i in _levels.size():
		_unlocked[_levels[i].id] = not _levels[i].is_secret


func get_levels() -> Array[LevelResource]:
	return _levels


func level_count() -> int:
	return _levels.size()


func get_level(index: int) -> LevelResource:
	if index < 0 or index >= _levels.size():
		return null
	return _levels[index]


func get_level_by_id(level_id: String) -> LevelResource:
	return _by_id.get(level_id, null)


func is_level_unlocked(index: int) -> bool:
	var l := get_level(index)
	if l == null:
		return false
	return bool(_unlocked.get(l.id, false))


func available_level_indices() -> PackedInt32Array:
	var out := PackedInt32Array()
	for i in _levels.size():
		if is_level_unlocked(i):
			out.append(i)
	return out


func build_list() -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	for i in _levels.size():
		var l := _levels[i]
		rows.append({
			"index": i,
			"id": l.id,
			"name": l.display_name,
			"unlocked": bool(_unlocked.get(l.id, false)),
			"secret": l.is_secret,
		})
	return rows


func unlock_secret_level() -> bool:
	for i in _levels.size():
		if _levels[i].id == SECRET_LEVEL_ID and not bool(_unlocked.get(_levels[i].id, false)):
			_unlocked[_levels[i].id] = true
			secret_level_unlocked.emit(i)
			DialogueSystem.queue_line("В сборке появилась папка, которой не было.", "MinigameSystem")
			return true
	return false


# --- lifecycle --------------------------------------------------------------

func _container() -> Node:
	var vp := ComputerSystem.get_screen_viewport()
	if vp == null:
		return null
	return vp.get_node_or_null("GameHost")


func is_game_running() -> bool:
	return _running and is_instance_valid(_game)


func get_game() -> Node:
	return _game if is_instance_valid(_game) else null


func get_active_level_index() -> int:
	return _active_index


func launch_from_desktop(level_index: int = -1) -> bool:
	if is_game_running():
		return true
	if level_index < 0:
		level_index = first_available_index()
	if level_index < 0:
		AudioManager.play_computer("error")
		return false
	var host := _container()
	if host == null:
		push_warning("MinigameSystem: no GameHost in the monitor SubViewport")
		return false
	if _game != null and is_instance_valid(_game):
		_game.queue_free()
		_game = null
	var packed := load(GAME_SCENE) as PackedScene
	if packed == null:
		push_warning("MinigameSystem: cannot load %s" % GAME_SCENE)
		return false
	_game = packed.instantiate()
	host.add_child(_game)
	_running = true
	if _game.has_signal("level_started"):
		_game.connect("level_started", _on_level_started)
		if _game.has_signal("level_completed"):
			_game.connect("level_completed", _on_level_completed)
		if _game.has_signal("level_failed"):
			_game.connect("level_failed", _on_level_failed)
		if _game.has_signal("hud_state_changed"):
			_game.connect("hud_state_changed", func(_s: Dictionary) -> void: state_changed.emit())
	GameManager.set_mode(GameManager.Mode.MINIGAME)
	_start_level(level_index)
	game_started.emit(level_index, get_level(level_index).id if get_level(level_index) else "")
	AudioManager.set_loop_gain("computer_hum", -24.0, 1.0)
	AudioManager.set_loop_gain("music_calm", -40.0, 1.0)
	return true


func first_available_index() -> int:
	for i in _levels.size():
		if is_level_unlocked(i):
			return i
	return 0 if _levels.size() > 0 else -1


func _start_level(index: int) -> void:
	var l := get_level(index)
	if l == null or _game == null:
		return
	_active_index = index
	if _game.has_method("load_level"):
		_game.call("load_level", index)
	level_started.emit(index, l.id)
	state_changed.emit()


func restart_level() -> void:
	if not is_game_running():
		return
	_deactivate_level_bugs()
	if _game.has_method("restart"):
		_game.call("restart")
		AudioManager.play_game2d("coin")
	state_changed.emit()


func go_to_level(index: int) -> bool:
	if not is_game_running():
		return launch_from_desktop(index)
	if not is_level_unlocked(index):
		AudioManager.play_computer("error")
		return false
	_start_level(index)
	return true


func force_stop(reason: String = "quit") -> void:
	if _game != null and is_instance_valid(_game):
		_game.queue_free()
	_game = null
	var was_running := _running
	_running = false
	_active_index = -1
	_last_stop_reason = reason
	AudioManager.set_loop_gain("computer_hum", -30.0, 0.8)
	AudioManager.set_loop_gain("music_calm", -34.0, 1.2)
	if was_running:
		game_stopped.emit(reason)
		if GameManager.mode == GameManager.Mode.MINIGAME:
			GameManager.set_mode(GameManager.Mode.COMPUTER)


func quit_to_desktop() -> void:
	force_stop("desktop")
	ComputerSystem.stack_push(ComputerSystem.App.DESKTOP)


func _on_level_started(index: int, level_id: String) -> void:
	AudioManager.play_game2d("coin")
	state_changed.emit()


func _on_level_completed(index: int) -> void:
	AudioManager.play_game2d("win")
	TaskSystem.notify_level_won(index)
	TaskSystem.notify_level_reached(mini(index + 1, level_count() - 1))
	state_changed.emit()


func _on_level_failed(index: int) -> void:
	AudioManager.play_game2d("death")
	TaskSystem.notify_died_on_level(index)
	state_changed.emit()


# --- bug interaction --------------------------------------------------------

func notify_zone_entered(zone_index: int) -> void:
	var l := get_level(_active_index)
	if l == null:
		return
	var bug_id := l.zone_bug_id(zone_index)
	if bug_id == "":
		return
	if BugSystem.activate_bug(bug_id):
		AudioManager.play_game2d("bug")
		DialogueSystem.queue_line("[ запись лога: аномалия ]", "MinigameSystem")


func notify_zone_exited(zone_index: int) -> void:
	var l := get_level(_active_index)
	if l == null:
		return
	var bug_id := l.zone_bug_id(zone_index)
	if bug_id != "":
		BugSystem.deactivate_bug(bug_id)


func _deactivate_level_bugs() -> void:
	for bug_id in l_bugs_of_active_level():
		BugSystem.deactivate_bug(bug_id)


func l_bugs_of_active_level() -> PackedStringArray:
	var l := get_level(_active_index)
	if l == null:
		return PackedStringArray()
	return l.bug_ids


## PhotoSystem asks "what is on the screen right now, and is it photographable?"
func describe_active_bug() -> Dictionary:
	var out := {"bug_id": "", "valid": false, "ndc": Vector2.ZERO}
	if not is_game_running() or _active_index < 0:
		return out
	var l := get_level(_active_index)
	if l == null:
		return out
	for bug_id in l.bug_ids:
		if BugSystem.get_status(bug_id) != "active":
			continue
		var bug := BugSystem.get_bug(bug_id)
		if bug == null:
			continue
		out["bug_id"] = bug_id
		if bug.kind == BugResource.Kind.UNPHOTOGRAPHABLE:
			out["valid"] = false
			return out
		var ndc := _bug_screen_ndc(bug_id)
		out["ndc"] = ndc
		out["valid"] = absf(ndc.x) <= 0.92 and absf(ndc.y) <= 0.92
		return out
	return out


func _bug_screen_ndc(bug_id: String) -> Vector2:
	if _game != null and _game.has_method("bug_marker_ndc"):
		return _game.call("bug_marker_ndc", bug_id)
	return Vector2(9, 9)


func trigger_npc_event(event_id: String) -> void:
	if is_game_running() and _game.has_method("npc_event"):
		_game.call("npc_event", event_id)
	elif _active_index >= 0:
		# The anomaly is registered even when the game is not running, so the
		# player can still document it from the log.
		DialogueSystem.queue_line("Отчёт о наблюдении: %s" % event_id, "HorrorSystem")


# --- read-only state for the UI ---------------------------------------------

func get_hud_state() -> Dictionary:
	if not is_game_running() or _game == null or not _game.has_method("get_hud_state"):
		return {}
	return _game.call("get_hud_state")


func last_stop_reason() -> String:
	return _last_stop_reason


# --- persistence ------------------------------------------------------------

func get_save_state() -> Dictionary:
	var unlocked_ids: Array[String] = []
	for k: Variant in _unlocked.keys():
		if bool(_unlocked[k]):
			unlocked_ids.append(str(k))
	var progress := {}
	if is_game_running() and _game.has_method("get_progress"):
		progress = _game.call("get_progress")
	return {
		"unlocked": unlocked_ids,
		"progress": progress,
		"secret_found": StoryFlags.has_flag(&"secret_level_found"),
	}


func apply_save_state(data: Dictionary) -> void:
	load_levels()
	for id: Variant in data.get("unlocked", []):
		_unlocked[str(id)] = true
	if bool(data.get("secret_found", false)):
		_unlocked[SECRET_LEVEL_ID] = true
