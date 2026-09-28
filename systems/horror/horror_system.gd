extends Node
## HorrorSystem — tension levels and scripted horror beats.
##
## Two sources of events only:
##  * STORY events queued by StorySystem when a chapter opens;
##  * AMBIENT events that respect tension, cooldowns and a screamer budget.
## Nothing here can lock the player out of progress: every event is a one-shot
## cosmetic/audio beat with a guaranteed revert.

signal tension_level_changed(level: int)
signal event_fired(event_id: String, kind: int)
signal event_skipped(event_id: String, reason: String)
signal screamer_requested(event_id: String)
signal pause_anomaly(event_id: String)

const EVENT_DIR := "res://data/horror"
const TENSION_MAX := 5

@export var ambient_min_interval: PackedFloat32Array = PackedFloat32Array([90.0, 75.0, 60.0, 48.0, 34.0, 22.0])
@export var max_screamers: int = 3
@export var shake_decay: float = 6.0
## Chance that opening the pause menu triggers the meta-horror beat.
@export_range(0.0, 1.0) var pause_anomaly_chance: float = 0.35
## Minimum seconds between two pause anomalies, so the menu stays usable.
@export var pause_anomaly_cooldown: float = 240.0
## Failed roll cooldown: the beat stays possible but does not nag every pause.
@export var pause_anomaly_retry: float = 90.0

var _events: Dictionary = {}     ## id -> HorrorEventResource
var _cooldowns: Dictionary = {}  ## id -> remaining seconds
var _queue: Array[Dictionary] = []
var _fired: Dictionary = {}
var _receivers: Dictionary = {}  ## target(int) -> Object
var _ambient_timer: float = 0.0
var _pause_watch_cd: float = 0.0
var _shake: Vector2 = Vector2.ZERO
var _shake_power: float = 0.0
var _shake_decay_rate: float = 6.0
var _screamer_budget: int = 3
var tension: int = 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	SaveSystem.register(&"horror", self)
	load_events()
	_screamer_budget = max_screamers
	_ambient_timer = 40.0


func _process(delta: float) -> void:
	_tick_cooldowns(delta)
	_tick_queue(delta)
	_tick_ambient(delta)
	_tick_shake(delta)
	if _pause_watch_cd > 0.0:
		_pause_watch_cd = maxf(0.0, _pause_watch_cd - delta)


# --- pause watch -------------------------------------------------------------

## Meta-horror gate for the pause overlay. The prologue pause is private: from
## the first chapter on, opening the menu can be noticed. Returns true only when
## the caller should show the anomaly, and rate-limits itself so the menu stays
## usable for the player.
func pause_watch() -> bool:
	if not bool(Settings.get_value("pause_anomaly_enabled", true)):
		return false
	if tension < 1:
		return false
	if _pause_watch_cd > 0.0:
		return false
	if randf() > pause_anomaly_chance:
		_pause_watch_cd = pause_anomaly_retry
		return false
	_pause_watch_cd = pause_anomaly_cooldown
	return true


# --- database ---------------------------------------------------------------

func load_events() -> void:
	_events.clear()
	var dir := DirAccess.open(EVENT_DIR)
	if dir == null:
		push_warning("HorrorSystem: cannot open %s" % EVENT_DIR)
		return
	var files := dir.get_files()
	files.sort()
	for f: String in files:
		if not f.ends_with(".tres"):
			continue
		var res := load(EVENT_DIR.path_join(f))
		if res is HorrorEventResource and (res as HorrorEventResource).id != "":
			_events[res.id] = res


func get_event(event_id: String) -> HorrorEventResource:
	return _events.get(event_id, null)


func all_event_ids() -> PackedStringArray:
	var out := PackedStringArray()
	for k: String in _events.keys():
		out.append(k)
	out.sort()
	return out


# --- tension ----------------------------------------------------------------

func set_tension(level: int) -> void:
	var v := clampi(level, 0, TENSION_MAX)
	if v == tension:
		return
	tension = v
	AudioManager.set_tension(v)
	tension_level_changed.emit(v)


func get_tension() -> int:
	return tension


func shake(power: float, duration: float) -> void:
	if not bool(Settings.get_value("screen_shake_enabled", true)):
		return
	_shake_power = maxf(_shake_power, power)
	_shake_decay_rate = 1.0 / maxf(0.05, duration)


func get_shake_offset() -> Vector2:
	if _shake_power <= 0.0:
		return Vector2.ZERO
	return _shake


func _tick_shake(delta: float) -> void:
	if _shake_power <= 0.0:
		_shake = Vector2.ZERO
		return
	_shake = Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * _shake_power
	_shake_power = maxf(0.0, _shake_power - _shake_decay_rate * delta)
	if _shake_power <= 0.001:
		_shake_power = 0.0
		_shake = Vector2.ZERO


# --- receivers --------------------------------------------------------------

func register_receiver(target: int, node: Object) -> void:
	_receivers[target] = node


func get_receiver(target: int) -> Object:
	return _receivers.get(target, null)


func clear_receiver(target: int) -> void:
	_receivers.erase(target)


# --- queue ------------------------------------------------------------------

func queue_event(event_id: String, delay: float = -1.0) -> bool:
	var ev := get_event(event_id)
	if ev == null:
		push_warning("HorrorSystem.queue_event: unknown '%s'" % event_id)
		return false
	if ev.one_shot and _fired.has(event_id):
		return false
	var d: float = ev.delay if delay < 0.0 else delay
	_queue.append({"id": event_id, "at": d})
	return true


func queue_list(ids: PackedStringArray, base_delay: float = 2.0, step: float = 3.0) -> void:
	for i in ids.size():
		queue_event(ids[i], base_delay + step * i)


func clear_queue() -> void:
	_queue.clear()


func pending_count() -> int:
	return _queue.size()


func _tick_queue(delta: float) -> void:
	if _queue.is_empty():
		return
	var keep: Array[Dictionary] = []
	for item: Dictionary in _queue:
		item["at"] = float(item["at"]) - delta
		if float(item["at"]) > 0.0:
			keep.append(item)
			continue
		var ev := get_event(String(item["id"]))
		if ev == null:
			continue
		if not _can_fire(ev):
			event_skipped.emit(ev.id, "conditions")
			continue
		_fire(ev)
	_queue = keep


func _tick_cooldowns(delta: float) -> void:
	if _cooldowns.is_empty():
		return
	for k: String in _cooldowns.keys().duplicate():
		var v: float = _cooldowns[k] - delta
		if v <= 0.0:
			_cooldowns.erase(k)
		else:
			_cooldowns[k] = v


func _can_fire(ev: HorrorEventResource) -> bool:
	if ev.one_shot and _fired.has(ev.id):
		return false
	if float(_cooldowns.get(ev.id, 0.0)) > 0.0:
		return false
	if ev.min_tension > 0 and tension < ev.min_tension:
		return false
	if ev.max_tension < TENSION_MAX and tension > ev.max_tension:
		return false
	if ev.required_flag != &"" and not StoryFlags.has_flag(ev.required_flag):
		return false
	if ev.requires_mode != 0 and int(GameManager.mode) != ev.requires_mode:
		return false
	if ev.is_screamer and _screamer_budget <= 0:
		return false
	if ev.chance < 1.0 and randf() > ev.chance:
		return false
	return true


func fire_now(event_id: String) -> bool:
	var ev := get_event(event_id)
	if ev == null:
		return false
	if not _can_fire(ev):
		event_skipped.emit(event_id, "conditions")
		return false
	_fire(ev)
	return true


func _fire(ev: HorrorEventResource) -> void:
	_fired[ev.id] = true
	if ev.cooldown > 0.0:
		_cooldowns[ev.id] = ev.cooldown
	if ev.is_screamer and ev.consumes_budget:
		_screamer_budget = maxi(0, _screamer_budget - 1)
	if ev.sets_flag != &"":
		StoryFlags.set_flag(ev.sets_flag, true)
	if ev.sets_tension >= 0:
		set_tension(ev.sets_tension)

	match ev.kind:
		HorrorEventResource.Kind.LIGHT_FLICKER:
			var r := get_receiver(ev.target)
			if r != null and r.has_method("set_light_flicker"):
				r.call("set_light_flicker", ev.duration)
		HorrorEventResource.Kind.AUDIO_STING:
			AudioManager.play_horror(ev.audio_key if ev.audio_key != "" else "sting")
		HorrorEventResource.Kind.OFFSCREEN_EVENT:
			_play_offscreen(ev)
		HorrorEventResource.Kind.OBJECT_DISAPPEAR:
			_prop(ev, "hide")
		HorrorEventResource.Kind.OBJECT_APPEAR:
			_prop(ev, "show")
		HorrorEventResource.Kind.OBJECT_JUMP:
			_prop(ev, "jump")
		HorrorEventResource.Kind.OFFICE_REWRITE:
			var r2 := get_receiver(ev.target)
			if r2 != null and r2.has_method("rewrite_office"):
				r2.call("rewrite_office")
		HorrorEventResource.Kind.TEXT_MUTATION:
			DialogueSystem.mutate_text(ev.text_id)
		HorrorEventResource.Kind.NPC_BEHAVIOR:
			MinigameSystem.trigger_npc_event(ev.id)
		HorrorEventResource.Kind.GAME_2D_LEAK:
			var r3 := get_receiver(HorrorEventResource.Target.OFFICE_PROP)
			if r3 != null and r3.has_method("spawn_leaked_object"):
				r3.call("spawn_leaked_object", ev.prop_id)
		HorrorEventResource.Kind.SCREAMER:
			screamer_requested.emit(ev.id)
			AudioManager.play_horror("screamer")
			shake(1.0, 0.6)
		HorrorEventResource.Kind.PAUSE_ANOMALY:
			StoryFlags.set_flag(&"saw_pause_movement", true)
			pause_anomaly.emit(ev.id)
		HorrorEventResource.Kind.CAMERA_MUTATION:
			var n := PhotoSystem.mutate_all_photos(1)
			StoryFlags.set_flag(&"photo_changed", true)
			if n > 0:
				DialogueSystem.queue_line("Фотографии выглядят иначе, чем вы их снимали.", "HorrorSystem")
		HorrorEventResource.Kind.REPORT_MUTATION:
			var reports := ReportSystem.all_reports()
			if reports.size() > 0:
				ReportSystem.mutate_report(reports[reports.size() - 1].bug_id)
				DialogueSystem.queue_line("Файл отчёта изменился, пока вы на него не смотрели.", "HorrorSystem")
		HorrorEventResource.Kind.SECRET_LEVEL:
			MinigameSystem.unlock_secret_level()
			StoryFlags.set_flag(&"secret_level_found", true)
			DialogueSystem.queue_line("В списке сборки появился уровень, которого не было.", "HorrorSystem")

	if ev.subtitle != "":
		DialogueSystem.queue_line(ev.subtitle, ev.id)
	event_fired.emit(ev.id, int(ev.kind))


func _prop(ev: HorrorEventResource, action: String) -> void:
	var r := get_receiver(ev.target)
	if r == null or not r.has_method("apply_prop_event"):
		return
	r.call("apply_prop_event", ev.prop_id, action)


func _play_offscreen(ev: HorrorEventResource) -> void:
	var player := GameManager.get_player()
	if player == null:
		return
	var basis := player.global_transform.basis
	# Behind the player, out of the current view frustum.
	var behind := -basis.z * 2.5 + basis.x * randf_range(-1.5, 1.5) - basis.y * 0.3
	var pos: Vector3 = player.global_position + behind
	AudioManager.play_3d(ev.audio_key if ev.audio_key != "" else "whisper", pos, ev.audio_volume_db)
	shake(0.12, 0.3)


# --- ambient ----------------------------------------------------------------

func _tick_ambient(delta: float) -> void:
	if tension <= 0:
		return
	_ambient_timer -= delta
	if _ambient_timer > 0.0:
		return
	var idx: int = clampi(tension - 1, 0, ambient_min_interval.size() - 1)
	_ambient_timer = ambient_min_interval[idx] * randf_range(0.75, 1.35)
	if AudioManager.stinger_weight() <= 0.0:
		return
	# Pick a small, non-screamer ambient event that the current tension allows.
	var pool: Array[HorrorEventResource] = []
	for k: String in _events.keys():
		var ev: HorrorEventResource = _events[k]
		if ev.is_screamer:
			continue
		if ev.kind == HorrorEventResource.Kind.AUDIO_STING and not String(ev.id).begins_with("amb_"):
			continue
		if tension < ev.min_tension or tension > ev.max_tension:
			continue
		if float(_cooldowns.get(ev.id, 0.0)) > 0.0:
			continue
		pool.append(ev)
	if pool.is_empty():
		return
	var picked: HorrorEventResource = pool[randi() % pool.size()]
	if randf() > AudioManager.stinger_weight():
		return
	if _can_fire(picked):
		_fire(picked)


# --- persistence ------------------------------------------------------------

func get_save_state() -> Dictionary:
	return {
		"tension": tension,
		"fired": Array(_fired.keys()),
		"cooldowns": _cooldowns.duplicate(),
		"screamer_budget": _screamer_budget,
	}


func apply_save_state(data: Dictionary) -> void:
	tension = clampi(int(data.get("tension", 0)), 0, TENSION_MAX)
	_fired.clear()
	for f: Variant in data.get("fired", []):
		_fired[str(f)] = true
	_cooldowns.clear()
	var cd: Dictionary = data.get("cooldowns", {})
	for k: Variant in cd.keys():
		_cooldowns[str(k)] = float(cd[k])
	_screamer_budget = int(data.get("screamer_budget", max_screamers))
	AudioManager.set_tension(tension)
