extends Node
## StorySystem — chapter progression and scripted story beats.
##
## Story logic lives HERE and nowhere else. Tasks raise flags, bugs raise flags;
## this system translates the resulting state into chapters, e-mails, tension
## levels and queued horror events.

signal chapter_changed(chapter: int, title: String)
signal beat_played(beat_id: String)
signal finale_started()
signal ending_reached(ending_id: String)

const CHAPTER_PROLOGUE := 0
const CHAPTER_FINALE := 10

## chapter -> {title, tension, emails, flags, events}
const CHAPTERS := {
	0: {
		"title": "Пролог. Первый рабочий день",
		"tension": 0,
		"emails": ["mail_00_welcome"],
		"flags": ["intro_seen"],
		"events": [],
	},
	1: {
		"title": "Глава 1. Обычные баги",
		"tension": 1,
		"emails": ["mail_01_assignment", "mail_01_reply"],
		"flags": [],
		"events": ["evt_ch1_light_flicker", "evt_ch1_offscreen_step"],
	},
	2: {
		"title": "Глава 2. Невозможный NPC",
		"tension": 2,
		"emails": ["mail_02_npc"],
		"flags": [],
		"events": ["evt_ch2_npc_behavior", "evt_ch2_object_jump"],
	},
	3: {
		"title": "Глава 3. Изменяющиеся фотографии",
		"tension": 2,
		"emails": ["mail_03_photo"],
		"flags": ["photo_gallery_opened"],
		"events": ["evt_ch3_photo_mutation"],
	},
	4: {
		"title": "Глава 4. LTL",
		"tension": 3,
		"emails": ["mail_04_ltl"],
		"flags": ["ltl_mentioned_in_build"],
		"events": ["evt_ch4_text_mutation", "evt_ch4_heartbeat"],
	},
	5: {
		"title": "Глава 5. Игра замечает игрока",
		"tension": 3,
		"emails": ["mail_05_watch"],
		"flags": ["game_noticed_player"],
		"events": ["evt_ch5_cursor_follow", "evt_ch5_minigame_leak"],
	},
	6: {
		"title": "Глава 6. TEST_ROOM",
		"tension": 4,
		"emails": ["mail_06_test_room"],
		"flags": ["entered_test_room"],
		"events": ["evt_ch6_office_rewrite", "evt_ch6_object_appear"],
	},
	7: {
		"title": "Глава 7. Связь с игровой вселенной",
		"tension": 4,
		"emails": ["mail_07_canon"],
		"flags": ["canon_term_seen"],
		"events": ["evt_ch7_report_mutation"],
	},
	8: {
		"title": "Глава 8. Разработчики перестали отвечать",
		"tension": 5,
		"emails": ["mail_08_silence"],
		"flags": ["developers_stopped_replying", "office_emptied"],
		"events": ["evt_ch8_offscreen", "evt_ch8_object_disappear"],
	},
	9: {
		"title": "Глава 9. Нарушение границы",
		"tension": 5,
		"emails": ["mail_09_breach"],
		"flags": ["boundary_breached", "leaked_object_in_office"],
		"events": ["evt_ch9_screamer", "evt_ch9_2d_leak"],
	},
	10: {
		"title": "Финал. Кто кого тестирует",
		"tension": 5,
		"emails": ["mail_10_final"],
		"flags": ["final_test_started"],
		"events": ["evt_final_office_rewrite"],
	},
}

var chapter: int = CHAPTER_PROLOGUE
var _played_beats: Dictionary = {}
var _pending_chapter_events: PackedStringArray = PackedStringArray()


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	SaveSystem.register(&"story", self)
	TaskSystem.task_completed.connect(_on_task_completed)
	TaskSystem.task_accepted.connect(_on_task_accepted)
	StoryFlags.flag_changed.connect(_on_flag_changed)
	begin_prologue.call_deferred()


## Story flags are the only channel other systems use to nudge the narrative.
## Keeping the reactions here means no system has to know about the others.
func _on_flag_changed(flag: StringName, value: Variant) -> void:
	if not bool(value):
		return
	match flag:
		&"canon_term_seen":
			# Reading the glossary is one of several ways the extra level becomes
			# reachable; the panel in the office is the one the tester is sent to.
			MinigameSystem.unlock_secret_level()
		&"photo_gallery_opened":
			# Opening the archive for the first time is what the game "notices".
			DialogueSystem.queue_line("[ кто-то ещё смотрит архив ]", "StorySystem")
		&"first_bug_reported":
			DialogueSystem.queue_line("Отчёт принят. Продолжайте по списку.", "StorySystem")
		&"ending_reached":
			reach_ending()


func get_chapter() -> int:
	return chapter


func chapter_title() -> String:
	return String(CHAPTERS.get(chapter, {}).get("title", ""))


func set_chapter(value: int) -> void:
	value = clampi(value, CHAPTER_PROLOGUE, CHAPTER_FINALE)
	if value == chapter:
		return
	chapter = value
	_apply_chapter()


## Applies the current chapter's emails, flags, tension and queued events.
## Split out from `set_chapter` because the prologue must be applied even though
## `chapter` already equals CHAPTER_PROLOGUE at boot.
func _apply_chapter() -> void:
	var data: Dictionary = CHAPTERS.get(chapter, {})
	for email_id: String in data.get("emails", []):
		DialogueSystem.unlock_email(email_id)
	for flag: String in data.get("flags", []):
		StoryFlags.set_flag(StringName(flag), true)
	var tension := int(data.get("tension", 0))
	HorrorSystem.set_tension(tension)
	for event_id: String in data.get("events", []):
		HorrorSystem.queue_event(event_id, 2.0 + randf() * 4.0)
	chapter_changed.emit(chapter, chapter_title())
	beat_played.emit("chapter_%d" % chapter)


## Applies the prologue without a chapter transition. Deferred because the
## prologue touches DialogueSystem / HorrorSystem, which finish their own load
## in the same autoload batch.
func begin_prologue() -> void:
	chapter = CHAPTER_PROLOGUE
	_apply_chapter()


func advance_chapter() -> void:
	set_chapter(chapter + 1)


func is_chapter_reached(value: int) -> bool:
	return chapter >= value


func _on_task_accepted(task_id: String) -> void:
	var t: TaskResource = TaskSystem.get_task(task_id)
	if t != null:
		set_chapter(maxi(chapter, t.chapter))


func _on_task_completed(task_id: String) -> void:
	var t: TaskResource = TaskSystem.get_task(task_id)
	if t == null:
		return
	play_beat("complete_%s" % task_id)
	# Chapter follows the highest assignment already handed out.
	if t.chapter > chapter:
		set_chapter(t.chapter + 1 if _has_task_in_chapter(t.chapter) else t.chapter)
	SaveSystem.save_game()


func _has_task_in_chapter(ch: int) -> bool:
	for id in TaskSystem.all_task_ids():
		var t: TaskResource = TaskSystem.get_task(id)
		if t != null and t.chapter == ch and not TaskSystem.is_completed(id):
			return true
	return false


func play_beat(beat_id: String) -> bool:
	if _played_beats.has(beat_id):
		return false
	_played_beats[beat_id] = true
	beat_played.emit(beat_id)
	return true


func beat_played_before(beat_id: String) -> bool:
	return _played_beats.has(beat_id)


## Text shown by the pause overlay when HorrorSystem.pause_watch() fires.
## Escalates with the chapter, and says nothing that is not already established
## on screen: no external-canon claims, no new nouns.
func pause_anomaly_line() -> String:
	if chapter >= CHAPTER_FINALE:
		return "смена не закрыта"
	if StoryFlags.has_flag(&"ending_reached"):
		return "вы закрыли смену. меню всё ещё открыто."
	if chapter >= 8:
		return "вы нажали паузу. смена — не ваша."
	if chapter >= 6:
		return "кто-то ещё смотрит, пока вы не двигаетесь"
	if chapter >= 4:
		return "вы не двигаетесь. камера — да."
	if chapter >= 2:
		return "пока вы стоите, уровень продолжается"
	return "пауза — это тоже тест"


# --- finale -----------------------------------------------------------------

func start_finale() -> void:
	if StoryFlags.has_flag(&"ending_reached"):
		return
	StoryFlags.set_flag(&"final_test_started", true)
	set_chapter(CHAPTER_FINALE)
	SaveSystem.save_game()
	finale_started.emit()


func reach_ending(ending_id: String = "ending_tester") -> void:
	if StoryFlags.has_flag(&"ending_reached"):
		return
	StoryFlags.set_flag(&"ending_reached", true)
	SaveSystem.save_game()
	ending_reached.emit(ending_id)


## Safety net for QA: walks the whole chain so the finale can be reached without
## playing 40 minutes. Never called from gameplay code — only from the debug
## panel and from tests.
func debug_unlock_all() -> void:
	for flag: Variant in StoryFlags.FLAG_DEFINITIONS.keys():
		StoryFlags.set_flag(StringName(flag), true)
	MinigameSystem.unlock_secret_level()
	for ch: int in [CHAPTER_PROLOGUE, 1, 2, 3, 4, 5, 6, 7, 8, 9, CHAPTER_FINALE]:
		if ch in CHAPTERS:
			set_chapter(ch)
	for id: String in TaskSystem.all_task_ids():
		TaskSystem.force_task(id)
		TaskSystem.complete_now("debug")
	reach_ending()


# --- persistence ------------------------------------------------------------

func get_save_state() -> Dictionary:
	return {
		"chapter": chapter,
		"beats": Array(_played_beats.keys()),
	}


func apply_save_state(data: Dictionary) -> void:
	chapter = int(data.get("chapter", CHAPTER_PROLOGUE))
	_played_beats.clear()
	for b: Variant in data.get("beats", []):
		_played_beats[str(b)] = true
	var data2: Dictionary = CHAPTERS.get(chapter, {})
	for email_id: String in data2.get("emails", []):
		DialogueSystem.unlock_email(email_id)
	HorrorSystem.set_tension(int(data2.get("tension", 0)))
	chapter_changed.emit(chapter, chapter_title())
