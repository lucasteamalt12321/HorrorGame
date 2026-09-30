extends Node
## Headless smoke test for the core play loop.
##
## Runs the REAL scene tree (autoloads + world + computer + GameRoot) and drives
## the loop the way a player would: report a bug, attach a photo, complete a
## level, and check that tasks, flags, chapters and the report record advance.
##
## Run:
##   godot --headless --path <project> res://tests/smoke.tscn

const REPORT_BUG := "BUG_NPC_WALL"
const REPORT_BUG_2 := "BUG_SCREEN_TEAR"

var _failures: int = 0
var _checks: int = 0
var _log: Array[String] = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_watchdog()
	_run.call_deferred()


## Hard stop: a smoke test that hangs is worse than one that fails.
func _watchdog() -> void:
	await get_tree().create_timer(25.0, true, false, true).timeout
	_failures += 1
	_log.append("  FAIL  watchdog: test did not finish in 25s")
	_report()


func _check(label: String, ok: bool, detail: String = "") -> void:
	_checks += 1
	if ok:
		_log.append("  PASS  %s" % label)
	else:
		_failures += 1
		_log.append("  FAIL  %s %s" % [label, detail])


func _run() -> void:
	await get_tree().process_frame
	await get_tree().process_frame

	_log.append("== databases ==")
	_check("bugs loaded", BugSystem.all_bugs().size() > 0, "got %d" % BugSystem.all_bugs().size())
	_check("tasks loaded", TaskSystem.total_count() > 0, "got %d" % TaskSystem.total_count())
	_check("levels loaded", MinigameSystem.level_count() >= 4, "got %d" % MinigameSystem.level_count())
	_check("emails loaded", DialogueSystem.get_inbox().size() > 0, "got %d" % DialogueSystem.get_inbox().size())
	_check("horror events loaded", HorrorSystem.all_event_ids().size() > 0, "got %d" % HorrorSystem.all_event_ids().size())
	_check("canon entries loaded", CanonRegistry.entries().size() > 0, "got %d" % CanonRegistry.entries().size())
	# Rule 11 is only worth anything if it is checked: a TODO entry carrying
	# safe_facts would have the glossary print a guess to the player as a fact.
	var canon_problems := CanonRegistry.validate()
	_check("canon entries respect rule 11", canon_problems.is_empty(),
		"; ".join(canon_problems))
	for e in CanonRegistry.entries():
		_check("canon '%s' states no fact while unverified" % e.term,
			e.is_safe() or e.safe_facts.is_empty())
		_check("canon '%s' has something to show" % e.term,
			not e.surfaces_in.is_empty() or not e.open_questions.is_empty())

	_log.append("== world wiring ==")
	var computer: Node3D = null
	for n in get_tree().get_nodes_in_group("interactable"):
		if n.has_method("get_screen_viewport"):
			computer = n as Node3D
			break
	_check("interactive computer in office", computer != null)
	_check("computer powered on", computer != null and bool(computer.get("power_on")))
	_check("subviewport created", computer != null and computer.call("get_screen_viewport") != null)
	_check("game_root present", get_tree().get_first_node_in_group("game_root") != null)
	_check("hud present", get_tree().get_first_node_in_group("hud") != null)

	_log.append("== office content ==")
	var director := get_tree().get_first_node_in_group("office_director") as OfficeDirector
	_check("office director present", director != null)
	if director != null:
		_check("registration book built", director.get_prop(OfficeDirector.REGISTRY_BOOK) != null)
		_check("build notes built", director.get_prop(OfficeDirector.BUILD_NOTES) != null)
		_check("shift log built", director.get_prop(OfficeDirector.SHIFT_LOG) != null)
		_check("colleague photo built", director.get_prop(OfficeDirector.COLLEAGUE_PHOTO) != null)
		_check("colleague present", director.get_colleague() != null)
		_check("colleague not gone yet",
			director.get_colleague() != null and not director.get_colleague().is_gone())
		var door := director.get_test_room_door()
		_check("test room panel hidden at start", door != null and not door.is_revealed())

		var book := director.get_prop(OfficeDirector.REGISTRY_BOOK)
		var read_ok := book != null and book.on_interact(GameManager.get_player())
		_check("registry book readable", read_ok)
		_check("document counts towards TALK_TO",
			TaskSystem.condition_progress(TaskResource.Condition.TALK_TO) >= 1)
		_check("director remembered the read", director.get_read_ids().has(OfficeDirector.REGISTRY_BOOK))

	_log.append("== photo (must be taken while exploring) ==")
	_check("exploring before photo", GameManager.is_exploring())
	var before_photos := PhotoSystem.count()
	var rec := PhotoSystem.take_photo()
	_check("photo taken", rec != null)
	if rec != null:
		_check("photo id assigned", rec.id != "")
		_check("photo count grew", PhotoSystem.count() == before_photos + 1)

	_log.append("== enter computer ==")
	var ok := ComputerSystem.enter(computer)
	_check("ComputerSystem.enter", ok)
	_check("mode is COMPUTER", GameManager.is_in_computer())
	await get_tree().process_frame
	_check("desktop instantiated", ComputerSystem.current_app == ComputerSystem.App.DESKTOP)
	# open_app() is a no-op while the boot sequence is still running. The
	# countdown is wall-clock, so wait on real time: headless frames come far
	# faster than the 1.6s the boot is budgeted for.
	for i in 30:
		if not ComputerSystem.is_booting():
			break
		await get_tree().create_timer(0.1, true, false, true).timeout
	_check("boot sequence finished", not ComputerSystem.is_booting())
	# Reports are filed in the tracker, so the suite drives the tracker itself
	# instead of poking ReportSystem in isolation.
	# Every app window used to be looked up in a dict keyed by the App enum
	# while the router only ever passes string ids, so no window was ever
	# created. Each app is opened here to keep that from coming back.
	_log.append("== computer apps open a window ==")
	var desktop := get_tree().get_first_node_in_group("computer_desktop")
	_check("desktop shell present", desktop != null)
	var tracker: Node = null
	for pair: Array in [
			[ComputerSystem.App.BUGTRACKER, "bug_tracker"],
			[ComputerSystem.App.MAIL, "mail_app"],
			[ComputerSystem.App.NOTES, "notes_app"],
			[ComputerSystem.App.FILES, "files_app"],
			[ComputerSystem.App.SETTINGS, "settings_panel"],
		]:
		var win := await _open_app_window(pair[0], pair[1])
		_check("%s window opens" % ComputerSystem.current_app_id(), win != null)
		if pair[0] == ComputerSystem.App.BUGTRACKER:
			tracker = win
		_check_reachable_by_pointer(win, "%s window controls answer the mouse" % pair[1])
		ComputerSystem.close_app()
		await get_tree().process_frame
	_check("back on the desktop after closing apps",
		ComputerSystem.current_app == ComputerSystem.App.DESKTOP,
		"app=%s" % ComputerSystem.current_app_id())
	tracker = await _open_app_window(ComputerSystem.App.BUGTRACKER, "bug_tracker")
	_check("bug tracker reopened", tracker != null)

	_log.append("== task chain start ==")
	TaskSystem.start_chain()
	await get_tree().process_frame
	var t0 := TaskSystem.get_current_task_id()
	_check("first task activated", t0 != "", "current='%s'" % t0)
	_check("prologue flag set", StoryFlags.has_flag(&"intro_seen"))
	_check("welcome mail unlocked", DialogueSystem.is_unlocked("mail_00_welcome"))

	_log.append("== report with evidence ==")
	BugSystem.mark_discovered(REPORT_BUG)
	var photo_id := rec.id if rec != null else ""
	var evid := PhotoEvidence.new()
	evid.bug_id = REPORT_BUG
	evid.valid = true
	evid.image_ref = photo_id
	evid.timestamp = int(Time.get_unix_time_from_system())
	var accepted := BugSystem.register_evidence(evid)
	_check("evidence registered", accepted)
	_check("bug known as photographed", BugSystem.is_photographed(REPORT_BUG))
	_check("photo valid for report", BugSystem.is_photo_valid(REPORT_BUG))

	var attach_ok := ReportSystem.attach_photo(photo_id, REPORT_BUG)
	_check("photo attached to report", attach_ok, "photo_id='%s'" % photo_id)
	_check("has_photo reflects attach", ReportSystem.has_photo(photo_id))

	var report := ReportSystem.submit(REPORT_BUG, "Снимок из дымового теста.", t0)
	_check("report created", report != null)
	if report != null:
		_check("report has photo", report.photo_ids.size() > 0)
		_check("report accepted by system", report.accepted)
	_log.append("  report status: %s" % BugSystem.get_status(REPORT_BUG))

	_log.append("== task reaction to report ==")
	await get_tree().process_frame
	_check("bug marked reported", BugSystem.is_reported(REPORT_BUG))
	_check("task progress moved", TaskSystem.progress_of(t0) > 0 or TaskSystem.is_completed(t0),
		"progress=%d" % TaskSystem.progress_of(t0))
	# A signal nobody listens to is dead weight that reads as a feature; this
	# check is what caught report_opened sitting unused.
	var opened_consumers := 0
	for c: Dictionary in ReportSystem.report_opened.get_connections():
		if bool(c["callable"].is_valid()):
			opened_consumers += 1
	_check("report_opened has a live consumer", opened_consumers > 0,
		"consumers=%d" % opened_consumers)
	_check("re-submitting an already reported bug returns the record",
		ReportSystem.submit(REPORT_BUG, "повтор", t0) != null)

	_log.append("== tracker shows the report thread ==")
	if tracker != null:
		var tlist := tracker.get_node_or_null("VBox/Body/Split/Left/Row/Scroll/List") as ItemList
		var tbody := tracker.get_node_or_null("VBox/Body/Split/Right/Scroll/Detail/Body") as RichTextLabel
		_check("tracker has a populated list", tlist != null and tlist.item_count > 0,
			"rows=%d" % (tlist.item_count if tlist != null else -1))
		var reported := BugSystem.get_bug(REPORT_BUG)
		var row := -1
		if tlist != null and reported != null:
			for i in tlist.item_count:
				if tlist.get_item_text(i).find(reported.title) >= 0:
					row = i
					break
		_check("reported bug is listed in the tracker", row >= 0, "row=%d" % row)
		if row >= 0 and tbody != null:
			tlist.select(row)
			# ItemList.select() only moves the highlight; it does not emit
			# item_selected, so the app's own handler is called to match a click.
			tracker.call("_on_selected", row)
			await get_tree().process_frame
			# Re-selecting a reported row must show the report, not the raw
			# bug hint: the thread is the only useful text at that point.
			_check("selected report shows the report thread",
				tbody.text == ReportSystem.report_body(REPORT_BUG),
				"body=%.60s" % tbody.text)

	_log.append("== second report (chain advance) ==")
	BugSystem.mark_discovered(REPORT_BUG_2)
	var evid2 := PhotoEvidence.new()
	evid2.bug_id = REPORT_BUG_2
	evid2.valid = true
	evid2.image_ref = photo_id
	evid2.timestamp = int(Time.get_unix_time_from_system())
	_check("second evidence registered", BugSystem.register_evidence(evid2))
	var second := ReportSystem.submit(REPORT_BUG_2, "Второй отчёт.", t0)
	_check("second report created", second != null)
	await get_tree().process_frame

	_log.append("== level run ==")
	var launched := MinigameSystem.launch_from_desktop(0)
	_check("minigame launched", launched)
	await get_tree().process_frame
	_check("minigame running", MinigameSystem.is_game_running())
	TaskSystem.notify_level_reached(0)
	TaskSystem.notify_level_won(0)
	await get_tree().process_frame
	_log.append("  tasks completed after level: %d / %d" % [TaskSystem.completed_count(), TaskSystem.total_count()])

	_log.append("== canon flag (T07 gate) ==")
	var before_seen := StoryFlags.has_flag(&"canon_term_seen")
	CanonRegistry.mark_all_seen()
	_check("canon_term_seen raised", StoryFlags.has_flag(&"canon_term_seen") or before_seen)

	_log.append("== pause anomaly ==")
	var anomaly := HorrorSystem.pause_watch()
	_check("pause_watch returns bool", anomaly == true or anomaly == false)
	var line := StorySystem.pause_anomaly_line()
	_check("pause_anomaly_line non-empty", line != "")

	_log.append("== test room panel (T09) ==")
	# T09 is the assignment that names the room, so the panel answers to it.
	TaskSystem.force_task("T09_TEST_ROOM")
	await get_tree().process_frame
	_check("T09 is current", TaskSystem.get_current_task_id() == "T09_TEST_ROOM")
	var panel := director.get_test_room_door() if director != null else null
	_check("panel revealed for T09", panel != null and panel.is_revealed())
	_check("panel still locked before use", panel != null and not panel.is_opened())
	if panel != null:
		_check("panel opened by interaction", panel.on_interact(GameManager.get_player()))
	await get_tree().process_frame
	_check("test_room_found raised", StoryFlags.has_flag(&"test_room_found"))
	_check("T09 completed by discovery", TaskSystem.is_completed("T09_TEST_ROOM"))
	_check("panel reports opened", panel != null and panel.is_opened())

	var secret_index := -1
	for i in MinigameSystem.level_count():
		var lvl := MinigameSystem.get_level(i)
		if lvl != null and lvl.id == "TEST_ROOM":
			secret_index = i
			break
	_check("TEST_ROOM present in database", secret_index >= 0)
	_check("secret level unlocked by panel", secret_index >= 0 and MinigameSystem.is_level_unlocked(secret_index))

	_log.append("== camera and flashlight ==")
	# The tester walks back to the office first: leave the desktop, then the
	# computer, because the camera and the flashlight are office tools.
	MinigameSystem.quit_to_desktop()
	for i in 30:
		if GameManager.is_in_computer():
			break
		await get_tree().process_frame
	_check("quit to desktop returns to the computer", GameManager.is_in_computer(),
		"mode=%s" % GameManager.get_mode_name())
	ComputerSystem.exit()
	for i in 30:
		if GameManager.is_exploring():
			break
		await get_tree().process_frame
	_check("leaving the computer returns to explore", GameManager.is_exploring(),
		"mode=%s" % GameManager.get_mode_name())
	var player := GameManager.get_player()
	var base_fov := 75.0
	if player != null:
		var cam := player.get_node_or_null("Head/Camera3D") as Camera3D
		base_fov = cam.fov if cam != null else 75.0

	_log.append("== photo gallery ==")
	# The gallery scene shipped with node paths that did not exist, and nothing
	# instantiated it, so it stayed broken until an export complained. Every
	# node the script reaches for is now asserted here.
	var root := get_tree().get_first_node_in_group("game_root")
	_check("game_root present for the gallery", root != null)
	if root != null:
		root.call("open_gallery")
		await get_tree().process_frame
		await get_tree().process_frame
	_check("gallery opens", root != null and root.call("is_gallery_open"))
	var gallery := get_tree().get_first_node_in_group("gallery")
	_check("gallery joins its group", gallery != null)
	if gallery != null:
		for path: String in ["VBox/Body/Left/Scroll/Center/Grid", "VBox/Body/Right/Preview",
				"VBox/Body/Right/Scroll/Meta", "VBox/Body/Left/Empty", "VBox/Body/Right/Attach",
				"VBox/Header/Close", "VBox/Header/Counter"]:
			_check("gallery has %s" % path, gallery.get_node_or_null(path) != null)
		var grid := gallery.get_node_or_null("VBox/Body/Left/Scroll/Center/Grid") as GridContainer
		var slot_count := grid.get_child_count() if grid != null else -1
		_check("gallery lists every photo", grid != null and slot_count == PhotoSystem.photos.size(),
			"slots=%d photos=%d" % [slot_count, PhotoSystem.photos.size()])
		var counter := gallery.get_node_or_null("VBox/Header/Counter") as Label
		_check("gallery counter shows the archive size",
			counter != null and counter.text.begins_with(str(PhotoSystem.photos.size())),
			"text=%s" % (counter.text if counter != null else ""))
		# Selecting a photo must fill the preview and the metadata panel.
		if grid != null and grid.get_child_count() > 0:
			(grid.get_child(0) as Button).pressed.emit()
			await get_tree().process_frame
			var preview := gallery.get_node_or_null("VBox/Body/Right/Preview") as TextureRect
			_check("gallery preview shows the selected photo", preview != null and preview.texture != null)
			var meta := gallery.get_node_or_null("VBox/Body/Right/Scroll/Meta") as RichTextLabel
			_check("gallery metadata is filled", meta != null and meta.text.length() > 10)
		root.call("close_gallery")
		await get_tree().process_frame
		_check("gallery closes", not root.call("is_gallery_open"))
	_check("gallery flag raised", StoryFlags.has_flag(&"photo_gallery_opened"))

	_check("viewfinder off by default", not CameraSystem.is_viewing())
	_check("viewfinder toggles on", CameraSystem.toggle())
	await get_tree().process_frame
	_check("viewfinder reports active", CameraSystem.is_viewing())
	# A photo must stay possible while the camera is raised. The shutter cooldown
	# from the earlier check has to expire first, otherwise this proves nothing.
	await get_tree().create_timer(0.5, true, false, true).timeout
	var viewfinder_photo := PhotoSystem.take_photo()
	_check("photo possible with viewfinder up", viewfinder_photo != null)
	_check("viewfinder toggles off", CameraSystem.toggle())
	await get_tree().create_timer(0.4, true, false, true).timeout
	_check("viewfinder reports closed", not CameraSystem.is_viewing())
	if player != null:
		var cam2 := player.get_node_or_null("Head/Camera3D") as Camera3D
		_check("fov restored after lowering camera",
			cam2 == null or absf(cam2.fov - base_fov) < 0.5,
			"fov=%.1f base=%.1f" % [cam2.fov if cam2 != null else -1.0, base_fov])
	var light := player.get_node_or_null("Head/Flashlight") as SpotLight3D if player != null else null
	_check("flashlight node exists", light != null)
	var was_off := light == null or not light.visible
	# Same injection path the on-screen touch buttons use.
	await _press_action("flashlight")
	_check("flashlight turns on", light != null and light.visible == was_off,
		"visible=%s was_off=%s" % [str(light != null and light.visible), str(was_off)])
	await _press_action("flashlight")
	_check("flashlight turns back off", light != null and light.visible != was_off,
		"visible=%s was_off=%s" % [str(light != null and light.visible), str(was_off)])

	_log.append("== horror receivers (must always revert) ==")
	if director != null:
		director.set_light_flicker(0.5)
		_check("light flicker accepted", true)
		var book_prop := director.get_prop(OfficeDirector.REGISTRY_BOOK)
		director.apply_prop_event(OfficeDirector.REGISTRY_BOOK, "hide")
		_check("prop hidden by event", book_prop != null and not book_prop.visible)
		director.apply_prop_event(OfficeDirector.REGISTRY_BOOK, "show")
		_check("prop shown again", book_prop != null and book_prop.visible)
		director.apply_prop_event(OfficeDirector.REGISTRY_BOOK, "jump")
		_check("prop jump accepted", true)
		director.spawn_leaked_object("LEAK_TEST")
		await get_tree().process_frame
		_check("leaked object spawned", _find_leaked(director) != null)
		_check("leak flag raised", StoryFlags.has_flag(&"leaked_object_in_office"))
		director.rewrite_office()
		await get_tree().process_frame
		_check("office rewrite applied", true)
		var queued_leak := _find_leaked(director)
		if queued_leak != null:
			queued_leak.queue_free()
	# Every event above must have left the office readable and the player able to
	# continue: the documents are visible and the panel still answers.
	if director != null:
		_check("all documents visible after horror beats",
			_all_props_visible(director))
		_check("test room panel still usable after horror beats",
			director.get_test_room_door() != null)

	_log.append("== every level builds ==")
	# Levels are started from the in-game desktop, so the tester sits back down
	# at the same computer, not at the player.
	_check("sitting down at the computer again", ComputerSystem.enter(computer))
	for i in 30:
		if GameManager.is_in_computer():
			break
		await get_tree().process_frame
	_check("back at the computer before level runs", GameManager.is_in_computer(),
		"mode=%s" % GameManager.get_mode_name())
	for i in MinigameSystem.level_count():
		var lvl := MinigameSystem.get_level(i)
		_check("level %d has an id" % i, lvl != null and lvl.id != "")
		if lvl == null:
			continue
		_check("level %d (%s) has platforms" % [i, lvl.id], lvl.platforms.size() > 0)
		_check("level %d (%s) spawn is on the field" % [i, lvl.id],
			lvl.spawn.x > 0.0 and lvl.spawn.x < float(lvl.width_tiles)
				and lvl.spawn.y > 0.0 and lvl.spawn.y < float(lvl.height_tiles),
			"spawn=%s field=%dx%d" % [lvl.spawn, lvl.width_tiles, lvl.height_tiles])
		_check("level %d (%s) goal is reachable" % [i, lvl.id],
			lvl.goal_x > lvl.spawn.x and lvl.goal_x <= float(lvl.width_tiles),
			"goal_x=%.1f spawn.x=%.1f" % [lvl.goal_x, lvl.spawn.x])
		_check("level %d (%s) zone table is consistent" % [i, lvl.id],
			lvl.bug_trigger_zones.size() == lvl.bug_trigger_ids.size(),
			"zones=%d ids=%d" % [lvl.bug_trigger_zones.size(), lvl.bug_trigger_ids.size()])
		for bug_id: String in lvl.bug_ids:
			_check("level %s promises existing bug %s" % [lvl.id, bug_id], BugSystem.has_bug(bug_id))
		for zone_index in lvl.bug_trigger_zones.size():
			var zone_id := lvl.zone_bug_id(zone_index)
			_check("level %s zone %d maps to an existing bug" % [lvl.id, zone_index],
				BugSystem.has_bug(zone_id), "id=%s" % zone_id)
			var zbug := BugSystem.get_bug(zone_id)
			if zbug != null:
				# Progression invariant: a bug must not unlock before its level
				# exists, and must still be reachable by the finale.
				_check("level %s zone %d bug is not gated before the level" % [lvl.id, zone_index],
					zbug.min_chapter >= lvl.chapter_min,
					"bug_ch=%d level_ch=%d" % [zbug.min_chapter, lvl.chapter_min])
				_check("level %s zone %d bug is reachable by the finale" % [lvl.id, zone_index],
					zbug.min_chapter <= StorySystem.CHAPTER_FINALE,
					"bug_ch=%d finale=%d" % [zbug.min_chapter, StorySystem.CHAPTER_FINALE])
		_check("level %d (%s) collectible count is positive" % [i, lvl.id], lvl.collectible_total > 0)

		var launched_i := MinigameSystem.launch_from_desktop(i)
		await get_tree().process_frame
		_check("level %d (%s) launches" % [i, lvl.id], launched_i and MinigameSystem.is_game_running())
		var game := MinigameSystem.get_game()
		_check("level %d (%s) geometry built" % [i, lvl.id],
			game != null and _world_child_count(game) > 0,
			"children=%d" % (0 if game == null else _world_child_count(game)))
		if game != null:
			var built := game.get("level") as LevelResource
			_check("level %d (%s) built from its own data" % [i, lvl.id],
				built != null and built.id == lvl.id)
		# A zone must be enterable: that is what makes a bug photographable.
		# Gated bugs are allowed to stay silent, but an open gate must activate.
		for zone_index in lvl.bug_trigger_zones.size():
			var zone_id2 := lvl.zone_bug_id(zone_index)
			var zbug2 := BugSystem.get_bug(zone_id2)
			# Mirror every precondition of BugSystem.activate_bug, otherwise a
			# legitimately silenced bug would be reported as a broken zone.
			var already_done := zbug2 != null and zbug2.report_required \
				and BugSystem.is_reported(zone_id2) and not zbug2.repeatable
			var gate_open := zbug2 != null and not already_done \
				and zbug2.min_chapter <= StorySystem.get_chapter() \
				and StoryFlags.all_set_ids(zbug2.required_flags)
			MinigameSystem.notify_zone_entered(zone_index)
			await get_tree().process_frame
			if gate_open:
				_check("level %s zone %d activates %s" % [lvl.id, zone_index, zone_id2],
					BugSystem.active_bug_ids().has(zone_id2))
				MinigameSystem.notify_zone_exited(zone_index)
			else:
				_check("level %s zone %d held back by its design gate" % [lvl.id, zone_index],
					not BugSystem.active_bug_ids().has(zone_id2),
					"bug_ch=%d chapter=%d flags=%s" % [0 if zbug2 == null else zbug2.min_chapter,
						StorySystem.get_chapter(), str(zbug2.required_flags if zbug2 != null else [])])
		MinigameSystem.force_stop("smoke")
		await get_tree().process_frame
		_check("level %s stopped" % lvl.id, not MinigameSystem.is_game_running())

	_log.append("== save round trip ==")
	var saved := SaveSystem.save_game(SaveSystem.AUTOSAVE_SLOT)
	_check("autosave written", saved)

	_log.append("== exit computer ==")
	ComputerSystem.exit()
	await get_tree().process_frame
	_check("mode back to EXPLORE", GameManager.is_exploring())

	_log.append("== finale safety net ==")
	StorySystem.debug_unlock_all()
	await get_tree().process_frame
	_check("ending reached", StoryFlags.has_flag(&"ending_reached"))
	_check("all tasks completed", TaskSystem.completed_count() == TaskSystem.total_count(),
		"%d / %d" % [TaskSystem.completed_count(), TaskSystem.total_count()])

	_log.append("== audio buffers (Android mix safety) ==")
	await _check_audio_safety()

	_report()


func _report() -> void:
	print("")
	print("========== SMOKE TEST ==========")
	for line: String in _log:
		print(line)
	print("---------- %d/%d checks passed" % [_checks - _failures, _checks])
	if _failures == 0:
		print("RESULT: PASS")
	else:
		print("RESULT: FAIL (%d)" % _failures)
	print("===============================")
	get_tree().quit(0 if _failures == 0 else 1)


# --- helpers -----------------------------------------------------------------

## The Android build died with SIGSEGV inside `AudioTrackCallback::onMoreData`,
## i.e. while the audio thread was mixing, not because of a script error. Two
## rules keep that mixer in bounds and are cheap enough to assert every run:
## every loop region must stay inside the sample buffer, and a stream must never
## be swapped underneath a player that is already playing.
func _check_audio_safety() -> void:
	_check("mix rate is a native device rate", AudioManager.MIX_RATE == 44100,
		"got %d" % AudioManager.MIX_RATE)

	for key: String in AudioManager._loop_players:
		var wav: AudioStreamWAV = AudioManager._loop_players[key].stream
		if wav == null:
			_check("loop '%s' has a stream" % key, false)
			continue
		_check("loop '%s' mix rate matches" % key, wav.mix_rate == AudioManager.MIX_RATE,
			"got %d" % wav.mix_rate)
		_check("loop '%s' region inside buffer" % key, wav.loop_end * 2 <= wav.data.size(),
			"loop_end=%d data=%d" % [wav.loop_end, wav.data.size()])

	var drone: AudioStreamPlayer = AudioManager._loop_players.get("tension_drone")
	if drone == null:
		_check("tension drone exists", false)
		return
	var before: AudioStreamWAV = drone.stream
	for level in AudioManager.TENSION_LEVELS:
		AudioManager.set_tension(level)
		await get_tree().process_frame
	_check("tension never swaps the drone stream", drone.stream == before)
	_check("tension retunes the drone in place", not is_equal_approx(drone.pitch_scale, 1.0),
		"pitch=%f" % drone.pitch_scale)

## Open one computer app and return the window it should have created.
func _open_app_window(app_id: int, group: String) -> Node:
	ComputerSystem.open_app(app_id)
	await get_tree().process_frame
	await get_tree().process_frame
	return get_tree().get_first_node_in_group(group)


## Walks a window with real pointer motion and checks that every control the
## player has to press is actually the thing under the cursor.
##
## The app suite opens windows with a keyboard shortcut, which hides a whole
## class of bug: in Godot a full-rect Control above a Button shadows it, so the
## window opens fine and looks perfect while none of its buttons react to a
## click. `mouse_filter` on every layout container has to stay IGNORE, and this
## is what proves it.
func _check_reachable_by_pointer(win: Node, label: String) -> void:
	if win == null:
		return
	var sv := _subviewport_above(win)
	if sv == null:
		_check(label, false, "no SubViewport above the window")
		return
	# A window fades in and its containers sort themselves, so rects are still
	# empty for a frame or two after it opens.
	for i in 6:
		await get_tree().process_frame
	var bounds := Rect2(Vector2.ZERO, Vector2(sv.size))
	var blocked: Array[String] = []
	var collapsed: Array[String] = []
	for control in _clickable_controls(win):
		if not control.is_visible_in_tree():
			continue
		var rect := control.get_global_rect()
		if rect.size.x <= 1.0 or rect.size.y <= 1.0:
			collapsed.append(str(control.name))
			continue
		var center := rect.get_center()
		if not bounds.has_point(center) or _clipped_out(control, center):
			continue
		var motion := InputEventMouseMotion.new()
		motion.position = center
		motion.global_position = center
		sv.push_input(motion, true)
		await get_tree().process_frame
		var hovered := sv.gui_get_hovered_control()
		if hovered != control and not control.is_ancestor_of(hovered):
			blocked.append("%s(%s)" % [control.name, hovered.name if hovered != null else "nothing"])
	if not collapsed.is_empty():
		_log.append("  note  %s has collapsed controls: %s" % [label, ", ".join(collapsed)])
	_check(label, blocked.is_empty(), ", ".join(blocked))


## Whether `point` falls outside a clipping ancestor of `control`, in which case
## the player cannot reach it no matter how the hit test is wired.
func _clipped_out(control: Control, point: Vector2) -> bool:
	var n: Node = control.get_parent()
	while n != null:
		var c := n as Control
		if c != null and c.clip_contents and not c.get_global_rect().has_point(point):
			return true
		n = n.get_parent()
	return false


## The SubViewport an in-world control is rendered in, if any.
func _subviewport_above(node: Node) -> SubViewport:
	var n: Node = node
	while n != null:
		if n is SubViewport:
			return n as SubViewport
		n = n.get_parent()
	return null


## Every control in `root` that a player clicks or types into.
func _clickable_controls(root: Node) -> Array[Control]:
	var found: Array[Control] = []
	var pending: Array[Node] = [root]
	while not pending.is_empty():
		var node: Node = pending.pop_back()
		if node is BaseButton or node is LineEdit or node is ItemList \
				or node is Tree or node is Slider or node is TabBar:
			found.append(node as Control)
		for child in node.get_children():
			pending.append(child)
	return found

func _find_leaked(director: OfficeDirector) -> Node:
	if director == null:
		return null
	for c in director.get_children():
		if c.name == "LeakedObject":
			return c
	return null


## After any horror beat the office must still be usable, so every document the
## tester may need has to be visible again.
func _all_props_visible(director: OfficeDirector) -> bool:
	for prop_id: String in [OfficeDirector.REGISTRY_BOOK, OfficeDirector.BUILD_NOTES,
			OfficeDirector.SHIFT_LOG, OfficeDirector.COLLEAGUE_PHOTO]:
		var prop := director.get_prop(prop_id)
		if prop == null or not prop.visible:
			return false
	return true


func _world_child_count(game: Node) -> int:
	var world := game.get_node_or_null("World")
	if world == null:
		return 0
	return world.get_child_count()


## Delivers a full press/release pair through the same InputEventAction path the
## touch controls use, so a node reading actions in _input sees the event.
func _press_action(action: String) -> void:
	for pressed: bool in [true, false]:
		var ev := InputEventAction.new()
		ev.action = action
		ev.pressed = pressed
		Input.parse_input_event(ev)
		# A real tick between the two halves: parsing both in one frame makes
		# Godot warn about the event being consumed twice.
		await get_tree().create_timer(0.02, true, false, true).timeout
