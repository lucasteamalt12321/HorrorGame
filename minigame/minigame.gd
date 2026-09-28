extends Node2D
## MinigameRoot — the whole game under test.
##
## Lives inside the monitor's SubViewport. Builds its levels from
## `LevelResource` data (no hand-placed nodes), routes the tasks, and exposes
## read-only state to MinigameSystem / PhotoSystem / TaskSystem.

signal level_started(index: int, level_id: String)
signal level_completed(index: int)
signal level_failed(index: int)
signal hud_state_changed(state: Dictionary)

const TILE := 16
const VIEW_SIZE := Vector2(320, 240)
const CAMERA_LERP := 6.0
const RESPAWN_DELAY := 0.9
const LIVES_MAX := 3

@export var levels_dir: String = "res://data/levels"
@export var camera_height: float = 0.0
@export var allow_secret_levels: bool = true

var lives: int = LIVES_MAX
var collectibles: int = 0
var level_index: int = -1
var level: LevelResource = null
var message: String = ""
var message_time: float = 0.0
var completed_levels: Dictionary = {}

var player: MinigamePlayer
var camera: Camera2D
var world: Node2D
var hud: CanvasLayer
var hud_root: Control

var _enemies: Array[MinigameEnemy] = []
var _pickups: Array[MinigamePickup] = []
var _effects: Array[BugEffect] = []
var _zones: Array[Area2D] = []
var _active_zone: int = -1
var _goal: Node2D = null
var _goal_rect: Rect2 = Rect2()
var _respawn_timer: float = 0.0
var _finished: bool = false
var _elapsed: float = 0.0
var _rng := RandomNumberGenerator.new()
var _scratch: Label


func _ready() -> void:
	_rng.randomize()
	_world_root()
	_build_hud()
	TaskSystem.task_progress.connect(func(_a: String, _c: int, _t: int) -> void: hud_state_changed.emit(get_hud_state()))

func _world_root() -> void:
	world = Node2D.new()
	world.name = "World"
	add_child(world)
	camera = Camera2D.new()
	camera.name = "Camera"
	camera.enabled = true
	camera.position_smoothing_enabled = false
	camera.zoom = Vector2.ONE
	add_child(camera)
	camera.make_current()


func _build_hud() -> void:
	hud = CanvasLayer.new()
	hud.name = "HUD"
	add_child(hud)
	hud_root = Control.new()
	hud_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	hud_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(hud_root)

	var panel := ColorRect.new()
	panel.color = Color(0, 0, 0, 0.45)
	panel.position = Vector2(4, 4)
	panel.size = Vector2(150, 26)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud_root.add_child(panel)

	_scratch = Label.new()
	_scratch.position = Vector2(8, 7)
	_scratch.add_theme_font_size_override("font_size", 6)
	_scratch.add_theme_color_override("font_color", Color(0.85, 0.95, 1.0))
	_scratch.add_theme_constant_override("outline_size", 2)
	_scratch.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	hud_root.add_child(_scratch)

	var msg := Label.new()
	msg.name = "Message"
	msg.position = Vector2(4, VIEW_SIZE.y - 34)
	msg.size = Vector2(VIEW_SIZE.x - 8, 20)
	msg.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	msg.add_theme_font_size_override("font_size", 6)
	msg.add_theme_color_override("font_color", Color(1, 0.95, 0.6))
	msg.add_theme_constant_override("outline_size", 3)
	msg.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	msg.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hud_root.add_child(msg)


# --- level construction -----------------------------------------------------

func load_level(index: int) -> void:
	if index < 0 or index >= MinigameSystem.level_count():
		push_warning("MinigameRoot.load_level: bad index %d" % index)
		return
	var res := MinigameSystem.get_level(index)
	if res == null:
		return
	level_index = index
	level = res
	lives = LIVES_MAX
	collectibles = 0
	_elapsed = 0.0
	_finished = false
	_active_zone = -1
	_clear_world()
	_build_platforms(res)
	_build_pickups(res)
	_build_enemies(res)
	_build_goal(res)
	_build_player(res)
	_build_zones(res)
	_apply_build_notes(res)
	_snap_camera()
	hud_state_changed.emit(get_hud_state())
	level_started.emit(index, res.id)
	TaskSystem.notify_level_reached(index)


func _clear_world() -> void:
	_enemies.clear()
	_pickups.clear()
	_effects.clear()
	_zones.clear()
	_goal = null
	if player != null and is_instance_valid(player):
		player.queue_free()
	player = null
	for c in world.get_children():
		world.remove_child(c)
		c.free()


func _build_platforms(res: LevelResource) -> void:
	for r: Rect2 in res.platforms:
		var body := StaticBody2D.new()
		body.name = "Platform"
		body.position = r.position * TILE
		body.collision_layer = 1
		body.collision_mask = 0
		var size := r.size * TILE
		var shape := RectangleShape2D.new()
		shape.size = size
		var col := CollisionShape2D.new()
		col.shape = shape
		col.position = size * 0.5
		body.add_child(col)

		var visual := ColorRect.new()
		visual.size = size
		visual.color = _platform_color(r)
		body.add_child(visual)
		var top := ColorRect.new()
		top.size = Vector2(size.x, 3)
		top.color = Color(0.35, 0.55, 0.4)
		body.add_child(top)
		world.add_child(body)


func _platform_color(r: Rect2) -> Color:
	if r.size.x >= float(res_width_tiles()) - 1.0:
		return Color(0.18, 0.2, 0.24)
	if r.size.x <= 2.0:
		return Color(0.24, 0.22, 0.3)
	return Color(0.2, 0.22, 0.28)


func res_width_tiles() -> int:
	return level.width_tiles if level != null else 64


func _build_pickups(res: LevelResource) -> void:
	for p: Vector2 in res.pickup_positions:
		var pk := MinigamePickup.new()
		pk.position = p * TILE
		world.add_child(pk)
		pk.collected.connect(_on_pickup_collected)
		_pickups.append(pk)


func _build_enemies(res: LevelResource) -> void:
	for i in res.enemy_kinds.size():
		var kind_string := res.enemy_kinds[i]
		var e := MinigameEnemy.new()
		e.kind = _enemy_kind(kind_string)
		e.origin = res.enemy_positions[i] * TILE
		e.position = e.origin
		e.patrol_range = res.enemy_ranges[i] if i < res.enemy_ranges.size() else 3.0
		world.add_child(e)
		e.touched_player.connect(_on_enemy_touched)
		_enemies.append(e)


func _enemy_kind(s: String) -> int:
	match s:
		"chaser": return MinigameEnemy.Kind.CHASER
		"flyer": return MinigameEnemy.Kind.FLYER
		"npc": return MinigameEnemy.Kind.IDLE_NPC
		_: return MinigameEnemy.Kind.WALKER


func _ground_y_at(tile_x: float) -> float:
	## Returns the top surface (world pixels) of the highest platform covering
	## the given tile column, or the bottom of the level if there is none.
	var best := INF
	for r: Rect2 in level.platforms:
		if tile_x < r.position.x or tile_x >= r.position.x + r.size.x:
			continue
		best = minf(best, r.position.y)
	return best * TILE if best < INF else float(level.height_tiles) * TILE


func _build_goal(res: LevelResource) -> void:
	var ground := _ground_y_at(res.goal_x)
	_goal = Node2D.new()
	_goal.name = "Goal"
	_goal.position = Vector2(res.goal_x * TILE, ground)
	world.add_child(_goal)
	var pole := ColorRect.new()
	pole.size = Vector2(3, 34)
	pole.position = Vector2(0, -34)
	pole.color = Color(0.7, 0.7, 0.75)
	_goal.add_child(pole)
	var flag := ColorRect.new()
	flag.size = Vector2(14, 9)
	flag.position = Vector2(2, -32)
	flag.color = Color(0.9, 0.25, 0.3)
	_goal.add_child(flag)
	# The trigger column reaches from the goal flag down to the fall plane, so
	# the player only has to touch the flag area to complete the level.
	_goal_rect = Rect2(_goal.position.x - 6.0, _goal.position.y - 40.0, 20.0, 40.0 + 20.0)


func _build_player(res: LevelResource) -> void:
	player = MinigamePlayer.new()
	player.lives = LIVES_MAX
	player.position = res.spawn * TILE
	world.add_child(player)
	player.died.connect(_on_player_died)
	player.jumped.connect(func() -> void: AudioManager.play_game2d("jump"))
	for e in _enemies:
		e.player = player


func _build_zones(res: LevelResource) -> void:
	for i in res.bug_trigger_zones.size():
		var z := res.bug_trigger_zones[i]
		var area := Area2D.new()
		area.name = "BugZone%d" % i
		area.position = z.position * TILE
		var shape := RectangleShape2D.new()
		shape.size = z.size * TILE
		var col := CollisionShape2D.new()
		col.shape = shape
		col.position = z.size * TILE * 0.5
		area.add_child(col)
		area.monitoring = true
		world.add_child(area)
		_zones.append(area)
		area.body_entered.connect(_on_zone_body_entered.bind(i))
		area.body_exited.connect(_on_zone_body_exited.bind(i))


func _apply_build_notes(res: LevelResource) -> void:
	if res.build_note.strip_edges() != "":
		show_message(res.build_note, 3.0)


# --- loop -------------------------------------------------------------------

func _process(delta: float) -> void:
	if message_time > 0.0:
		message_time -= delta
		if message_time <= 0.0:
			message = ""
	_update_hud()

	if _respawn_timer > 0.0:
		_respawn_timer -= delta
		if _respawn_timer <= 0.0 and level != null:
			_respawn()


func _physics_process(delta: float) -> void:
	if level == null or player == null or not is_instance_valid(player):
		return
	if _finished:
		return
	_elapsed += delta
	_follow_player(delta)
	_check_goal()
	_check_fall()


func _follow_player(delta: float) -> void:
	var target := player.global_position + Vector2(0, camera_height)
	camera.global_position = camera.global_position.lerp(target, clampf(delta * CAMERA_LERP, 0.0, 1.0))
	camera.global_position.x = clampf(camera.global_position.x, VIEW_SIZE.x * 0.5, res_width_tiles() * TILE - VIEW_SIZE.x * 0.5)


func _check_goal() -> void:
	if not player.alive:
		return
	if _goal_rect.has_point(player.global_position):
		_complete_level()


func _check_fall() -> void:
	if player.global_position.y > _fall_plane():
		_on_player_died("fall")


## Below the level the player has fallen out of the build; a non-positive
## kill_plane_y in the data means "use the level height instead".
func _fall_plane() -> float:
	if level == null:
		return 0.0
	if level.kill_plane_y > 0.0:
		return level.kill_plane_y * TILE
	return (level.height_tiles + 3.0) * TILE


func _complete_level() -> void:
	if _finished:
		return
	_finished = true
	completed_levels[level.id] = true
	show_message("УРОВЕНЬ ПРОЙДЕН", 2.0)
	level_completed.emit(level_index)
	hud_state_changed.emit(get_hud_state())


func restart() -> void:
	if level_index >= 0:
		load_level(level_index)


# --- events -----------------------------------------------------------------

func _on_pickup_collected(_p: MinigamePickup) -> void:
	collectibles += 1
	AudioManager.play_game2d("coin")
	hud_state_changed.emit(get_hud_state())


func _on_enemy_touched() -> void:
	if player != null and is_instance_valid(player):
		player.kill("enemy")


func _on_player_died(_cause: String) -> void:
	if _finished:
		return
	lives -= 1
	_begin_respawn()
	if lives <= 0:
		_finished = true
		show_message("ТЕСТЕР УДАЛЁН", 3.0)
		level_failed.emit(level_index)
		hud_state_changed.emit(get_hud_state())


func _begin_respawn() -> void:
	_respawn_timer = RESPAWN_DELAY
	AudioManager.play_game2d("death")
	show_message("ПОПЫТКА %d" % lives, 1.0)
	hud_state_changed.emit(get_hud_state())


func _respawn() -> void:
	if level == null or player == null:
		return
	player.revive(level.spawn * TILE)
	_snap_camera()


func _snap_camera() -> void:
	if player != null:
		camera.global_position = player.global_position + Vector2(0, camera_height)


func _on_zone_body_entered(body: Node2D, zone_index: int) -> void:
	if not body.is_in_group("minigame_player"):
		return
	_active_zone = zone_index
	MinigameSystem.notify_zone_entered(zone_index)
	_spawn_effect(zone_index)


func _on_zone_body_exited(body: Node2D, zone_index: int) -> void:
	if not body.is_in_group("minigame_player"):
		return
	if _active_zone == zone_index:
		_active_zone = -1
	MinigameSystem.notify_zone_exited(zone_index)


func _spawn_effect(zone_index: int) -> void:
	if level == null:
		return
	var bug_id := level.zone_bug_id(zone_index)
	if bug_id == "" or BugSystem.get_status(bug_id) != "active":
		return
	var bug := BugSystem.get_bug(bug_id)
	if bug == null:
		return
	var effect := BugEffect.new()
	var rect: Rect2 = level.bug_trigger_zones[zone_index]
	effect.position = rect.position * TILE + rect.size * TILE * 0.5
	world.add_child(effect)
	var target := _pick_target_for_bug(bug)
	effect.configure(bug, target, level)
	_effects.append(effect)


func _pick_target_for_bug(bug: BugResource) -> Node2D:
	match bug.kind:
		BugResource.Kind.NPC_THROUGH_WALL, BugResource.Kind.NPC_WATCHES:
			for e in _enemies:
				if e.kind == MinigameEnemy.Kind.WALKER or e.kind == MinigameEnemy.Kind.IDLE_NPC:
					return e
			return _enemies[0] if not _enemies.is_empty() else player
		BugResource.Kind.FLOATING_PICKUP, BugResource.Kind.WRONG_SPAWN:
			return _pickups[0] if not _pickups.is_empty() else null
		BugResource.Kind.INVISIBLE_ENEMY, BugResource.Kind.BROKEN_PATROL:
			return _enemies[0] if not _enemies.is_empty() else null
		_:
			return _enemies[0] if not _enemies.is_empty() else player


# --- external commands ------------------------------------------------------

func show_message(text: String, duration: float = 2.0) -> void:
	message = text
	message_time = duration
	hud_state_changed.emit(get_hud_state())


func npc_event(event_id: String) -> void:
	match event_id:
		"evt_ch2_npc_behavior":
			for e in _enemies:
				if e.kind == MinigameEnemy.Kind.IDLE_NPC:
					e.set_look_at_camera(true)
					show_message("Он смотрит на вас.", 2.5)
					break
			if _enemies.is_empty():
				show_message("Никого не было в кадре.", 2.0)
		_:
			pass


func bug_marker_ndc(bug_id: String) -> Vector2:
	for e in _effects:
		if e.bug_id != bug_id or not is_instance_valid(e):
			continue
		var world_pos := e.marker_world_position()
		var screen := camera.global_position + (world_pos - camera.global_position)
		return Vector2(
			clampf(screen.x / VIEW_SIZE.x * 2.0 - 1.0, -1.5, 1.5),
			clampf(-screen.y / VIEW_SIZE.y * 2.0 + 1.0, -1.5, 1.5)
		)
	return Vector2(9, 9)


func set_frozen(value: bool) -> void:
	if player != null and is_instance_valid(player):
		player.frozen = value
	for e in _enemies:
		e.set_frozen(value)
	_finished = value


# --- state ------------------------------------------------------------------

func _update_hud() -> void:
	if _scratch == null:
		return
	var total := level.collectible_total if level != null else 0
	_scratch.text = "ЖИЗНИ %d   ДАННЫЕ %d/%d" % [maxi(lives, 0), collectibles, total]
	var msg_label := hud_root.get_node_or_null("Message") as Label
	if msg_label != null:
		msg_label.text = message


func get_hud_state() -> Dictionary:
	return {
		"level_index": level_index,
		"level_id": level.id if level != null else "",
		"level_name": level.display_name if level != null else "",
		"lives": maxi(lives, 0),
		"collectibles": collectibles,
		"collectible_total": level.collectible_total if level != null else 0,
		"message": message,
		"finished": _finished,
		"elapsed": _elapsed,
		"active_bugs": BugSystem.active_bug_ids(),
	}


func get_progress() -> Dictionary:
	return {
		"completed_levels": completed_levels.keys(),
		"lives": lives,
		"last_level_index": level_index,
	}
