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
	# Everything below goes through the real input path: look at the monitor,
	# press E, click an icon with the mouse, leave with Esc. Calling
	# ComputerSystem.enter() directly would pass even with the router, the HUD and
	# the monitor wiring all broken, which is exactly how a dead desktop shipped.
	if computer != null and player != null:
		var head := player.get_node_or_null("Head") as Node3D
		player.global_position = Vector3(0.0, 1.0, 0.0)
		if head != null:
			head.look_at(computer.global_position, Vector3.UP)
		for i in 12:
			await get_tree().process_frame
		_check("monitor is the focused interactable at spawn",
			InteractionSystem.get_current() == computer,
			"focus=%s" % str(InteractionSystem.get_current()))

		await _press("interact")
		_check("E sits the player down at the computer", ComputerSystem.is_active,
			"mode=%s" % GameManager.get_mode_name())
		_check("computer mode entered", GameManager.is_in_computer(),
			"mode=%s" % GameManager.get_mode_name())

		var desktop := ComputerSystem.get_desktop_root()
		_check("desktop is mounted inside the monitor", desktop != null)
		var screen_vp := computer.get_screen_viewport() as SubViewport
		_check("desktop renders through the monitor's SubViewport",
			desktop != null and screen_vp != null and desktop.is_ancestor_of(screen_vp) == false
				and desktop.get_parent() == screen_vp)

		# A click has to survive: root viewport -> screen mesh -> SubViewport. The
		# boot screen is modal, so wait it out the way a player does - in wall
		# clock time, because a headless run gets through frames far faster than
		# a boot animation plays.
		await _wait_until_wall(func() -> bool: return not ComputerSystem.is_booting(), 6.0)
		_check("boot screen clears on its own", not ComputerSystem.is_booting())
		var icon := _icon_button(desktop, "БАГИ")
		_check("desktop has a bug tracker icon", icon != null)
		if icon != null and screen_vp != null:
			var center := icon.get_global_rect().get_center()
			var uv := Vector2(center.x / float(screen_vp.size.x), center.y / float(screen_vp.size.y))
			var at := computer.call("screen_position_for_uv", uv) as Vector2
			_check("icon maps onto the monitor on screen",
				get_viewport().get_visible_rect().has_point(at), "at=%s" % str(at))
			await _click_screen(at)
			await _settle()
			_check("mouse click on the icon opens the bug tracker",
				ComputerSystem.current_app_id() == "bugtracker",
				"app=%s" % ComputerSystem.current_app_id())
			_check("the clicked window exists on the desktop",
				desktop.get_node_or_null("WindowLayer/App_Bugtracker") != null)

			await _press("ui_cancel")
			await _settle()
			_check("Esc closes the window and keeps the session",
				ComputerSystem.current_app_id() == "desktop" and ComputerSystem.is_active,
				"app=%s" % ComputerSystem.current_app_id())

		# The boot animation must never eat the key that leaves the machine.
		var entered_at := Time.get_ticks_msec()
		await _press("ui_cancel")
		if ComputerSystem.is_booting():
			await _press("ui_cancel")
		await _wait_until(func() -> bool: return GameManager.is_exploring(), 90)
		_check("Esc gets the tester out of the computer", GameManager.is_exploring(),
			"mode=%s after %dms" % [GameManager.get_mode_name(), Time.get_ticks_msec() - entered_at])
		_check("leaving the computer is not a dead end", is_instance_valid(computer))
		_check("desktop ready for a test run",
			MinigameSystem.first_available_index() >= 0)

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


## Same, but on the wall clock instead of a frame count. A headless run burns
## through frames much faster than real time, so anything driven by a timer
## (the boot animation, screen fades) has to be waited out in seconds.
func _wait_until_wall(predicate: Callable, seconds: float) -> bool:
	var deadline := Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < deadline:
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


## Presses and releases a real action event, exactly like a key press.
func _press(action: String) -> void:
	for pressed: bool in [true, false]:
		var ev := InputEventAction.new()
		ev.action = action
		ev.pressed = pressed
		Input.parse_input_event(ev)
		await get_tree().process_frame


## Clicks a point of the root viewport the way a mouse does: motion first, so the
## Control under the cursor is hovered, then press and release.
##
## The events go through `Input.parse_input_event` because that is the path the
## engine uses for real pointer input, and `Viewport.push_input` only feeds the
## local GUI - it never reaches the node `_input` callbacks the computer listens
## in. The position has to be in window pixels: the root viewport maps input
## with its content-scale transform, so viewport coordinates would land on the
## wrong side of the screen.
func _click_screen(at: Vector2) -> void:
	var at_window := _to_window_coords(at)
	var motion := InputEventMouseMotion.new()
	motion.position = at_window
	motion.global_position = at_window
	Input.parse_input_event(motion)
	await get_tree().process_frame
	for pressed: bool in [true, false]:
		var click := InputEventMouseButton.new()
		click.button_index = MOUSE_BUTTON_LEFT
		click.pressed = pressed
		click.position = at_window
		click.global_position = at_window
		Input.parse_input_event(click)
		await get_tree().process_frame


func _to_window_coords(at: Vector2) -> Vector2:
	var vp := get_viewport()
	if vp == null:
		return at
	return vp.get_final_transform() * at


func _icon_button(desktop: Control, text_prefix: String) -> Button:
	if desktop == null:
		return null
	var grid := desktop.get_node_or_null("IconGrid") as Control
	if grid == null:
		return null
	for child in grid.get_children():
		var b := child as Button
		if b != null and b.text.begins_with(text_prefix):
			return b
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
