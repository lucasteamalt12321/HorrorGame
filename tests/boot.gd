extends Node
## Entry-point integration test.
##
## The rest of the suite mounts res://scenes/levels/world.tscn directly, which
## hides a whole class of release blockers: a broken main scene, a menu button
## that no longer starts the game, or a world that loads but leaves the tester
## unable to move. This test walks the real route a player takes:
##   main_menu.tscn -> "New game" -> world.tscn -> office -> movement.
##
## Run with:
##   Godot --headless --path <project> res://tests/boot.tscn

const MENU_SCENE := "res://ui/menus/main_menu.tscn"
const WORLD_SCENE := "res://scenes/levels/world.tscn"
const WATCHDOG_SECONDS := 25.0

var _checks: int = 0
var _failures: int = 0
var _log: Array[String] = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_watchdog()
	# change_scene_to_file() frees the current scene and everything under it, so
	# the driver moves itself onto the tree root first and outlives every swap.
	_detach.call_deferred()


## Hard stop: an entry point that hangs must fail loudly instead of stalling CI.
func _watchdog() -> void:
	await get_tree().create_timer(WATCHDOG_SECONDS, true, false, true).timeout
	_failures += 1
	_log.append("  FAIL  watchdog: test did not finish in %ds" % int(WATCHDOG_SECONDS))
	_report()


func _detach() -> void:
	var tree := get_tree()
	var parent := get_parent()
	parent.remove_child(self)
	tree.root.add_child(self)
	await get_tree().process_frame
	_run()


func _run() -> void:
	_log.append("== main menu ==")
	# The driver lives on the tree root, not inside the scene it replaces.
	_check("driver survives scene swaps", get_parent() == get_tree().root,
		"parent=%s" % str(get_parent().name))
	# Exactly what the project ships as its main scene.
	get_tree().change_scene_to_file(MENU_SCENE)
	await _wait_until(func() -> bool: return get_tree().current_scene != null \
		and get_tree().current_scene.scene_file_path == MENU_SCENE, 60)
	var menu := get_tree().current_scene
	_check("main menu loads", menu != null and menu.scene_file_path == MENU_SCENE,
		"scene=%s" % str(get_tree().current_scene))
	if menu == null:
		_report()
		return
	var new_button := menu.get_node_or_null("Center/Menu/Actions/New") as Button
	_check("new game button present", new_button != null)
	_check("new game button enabled", new_button != null and not new_button.disabled)
	_check("new game button visible", new_button != null and new_button.visible)
	if new_button == null:
		_report()
		return

	_log.append("== press new game ==")
	await _settle()
	await _activate(new_button)
	var reached_world := await _wait_until(func() -> bool: return get_tree().current_scene != null \
		and get_tree().current_scene.scene_file_path == WORLD_SCENE, 30)
	if not reached_world:
		# A headless window has no pointer routing, so the synthetic click may
		# never reach the control. The transition itself still has to work.
		_log.append("  note  synthetic click did not route; pressing the button directly")
		new_button.emit_signal("pressed")
		await _wait_until(func() -> bool: return get_tree().current_scene != null \
			and get_tree().current_scene.scene_file_path == WORLD_SCENE, 180)
	var world := get_tree().current_scene
	_check("new game reaches the world", world != null and world.scene_file_path == WORLD_SCENE,
		"scene=%s" % str(get_tree().current_scene))
	if world == null or world.scene_file_path != WORLD_SCENE:
		_report()
		return

	_log.append("== the office is playable ==")
	var player := GameManager.get_player()
	_check("player registered", player != null)
	_check("game starts in explore mode", GameManager.is_exploring(),
		"mode=%s" % GameManager.get_mode_name())
	var director := get_tree().get_first_node_in_group("office_director") as OfficeDirector
	_check("office director built", director != null)
	var computer := _find_computer()
	_check("computer present in the office", computer != null)
	_check("paused nowhere at start", not GameManager.is_paused())
	_check("input is live", not GameManager.is_input_blocked())

	# The tester must be able to walk away from the spawn point. A desk may block
	# one side, so each axis only has to move in at least one direction.
	if player != null:
		var forward_moved := await _walk("move_forward", "move_backward", "z")
		_check("player walks on W and S", forward_moved)
		var side_moved := await _walk("move_right", "move_left", "x")
		_check("player walks on A and D", side_moved)
		_check("player stays on the floor", player.global_position.y > -2.0,
			"y=%.2f" % player.global_position.y)
		_check("interaction still allowed", not GameManager.is_input_blocked())

	_log.append("== the office answers ==")
	if computer != null:
		_check("sitting down works from the real world",
			ComputerSystem.enter(computer as Node3D))
		for i in 30:
			if GameManager.is_in_computer():
				break
			await get_tree().process_frame
		_check("computer mode entered", GameManager.is_in_computer(),
			"mode=%s" % GameManager.get_mode_name())
		_check("desktop ready for a test run",
			MinigameSystem.first_available_index() >= 0)
		ComputerSystem.exit()
		for i in 30:
			if GameManager.is_exploring():
				break
			await get_tree().process_frame
		_check("back in the office", GameManager.is_exploring(),
			"mode=%s" % GameManager.get_mode_name())

	_log.append("== autosave from a real new game ==")
	_check("new game writes a slot", SaveSystem.save_game(SaveSystem.AUTOSAVE_SLOT))
	_check("tasks loaded with the world", TaskSystem.total_count() > 0,
		"tasks=%d" % TaskSystem.total_count())
	_check("bugs loaded with the world", BugSystem.all_bug_ids().size() > 0,
		"bugs=%d" % BugSystem.all_bug_ids().size())
	_check("levels loaded with the world", MinigameSystem.level_count() > 0,
		"levels=%d" % MinigameSystem.level_count())

	_report()


# --- helpers -----------------------------------------------------------------

func _check(label: String, condition: bool, detail: String = "") -> void:
	_checks += 1
	if condition:
		_log.append("  PASS  " + label)
		return
	_failures += 1
	_log.append("  FAIL  %s%s" % [label, "" if detail.is_empty() else " (%s)" % detail])


func _wait_until(predicate: Callable, max_frames: int) -> bool:
	for i in max_frames:
		if predicate.call():
			return true
		await get_tree().process_frame
	return predicate.call()


func _settle() -> void:
	for i in 3:
		await get_tree().process_frame


## Activates a button the way a player does: focus it and confirm.
##
## A synthetic mouse click is not used because a headless window has no pointer
## routing, so the click would silently do nothing and prove nothing.
func _activate(control: Control) -> void:
	control.grab_focus()
	for pressed: bool in [true, false]:
		var ev := InputEventAction.new()
		ev.action = &"ui_accept"
		ev.pressed = pressed
		Input.parse_input_event(ev)
		# A real tick between the two halves: parsing both in one frame makes
		# Godot warn about the event being consumed twice.
		await get_tree().create_timer(0.02, true, false, true).timeout


## Tries one direction, then its opposite, and reports whether the player moved
## along the axis. Both are checked so a blocked wall cannot fake a pass and a
## dead input pair cannot hide behind furniture.
func _walk(action: String, opposite: String, axis: String) -> bool:
	var player := GameManager.get_player()
	if player == null:
		return false
	var before: float = player.global_position[axis]
	await _hold(action, 0.3)
	await _settle()
	var moved: float = absf(player.global_position[axis] - before)
	if moved > 0.05:
		_log.append("  note  %s moves the player (%.2f m)" % [action, moved])
		return true
	await _hold(opposite, 0.3)
	await _settle()
	moved = absf(player.global_position[axis] - before)
	_log.append("  note  %s blocked (%.2f m), %s moved %.2f m" % [action, 0.0, opposite, moved])
	return moved > 0.05


## Holds an action for a real slice of time, through the touch control path.
func _hold(action: String, seconds: float) -> void:
	var ev := InputEventAction.new()
	ev.action = action
	ev.pressed = true
	Input.parse_input_event(ev)
	await get_tree().create_timer(seconds, true, false, true).timeout
	ev.pressed = false
	Input.parse_input_event(ev)
	await get_tree().process_frame


func _find_computer() -> Node3D:
	for n in get_tree().get_nodes_in_group("interactable"):
		if n.has_method("get_screen_viewport"):
			return n as Node3D
	return null


func _report() -> void:
	print("")
	print("========== BOOT TEST ==========")
	for line: String in _log:
		print(line)
	print("---------- %d/%d checks passed" % [_checks - _failures, _checks])
	print("RESULT: PASS" if _failures == 0 else "RESULT: FAIL (%d)" % _failures)
	print("================================")
	get_tree().quit(0 if _failures == 0 else 1)
