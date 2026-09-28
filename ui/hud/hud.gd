extends Control
## HUD — everything the player sees in the 3D world.
##
## Pure presentation: it reads systems and forwards intents. It never decides
## game rules.

@onready var crosshair: Control = $Crosshair
@onready var prompt: PanelContainer = $Prompt
@onready var prompt_label: Label = $Prompt/Label
@onready var objective: PanelContainer = $Objective
@onready var objective_text: RichTextLabel = $Objective/Text
@onready var chapter_card: PanelContainer = $ChapterCard
@onready var chapter_label: Label = $ChapterCard/Text
@onready var subtitle: PanelContainer = $Subtitle
@onready var subtitle_label: Label = $Subtitle/Label
@onready var flash_rect: ColorRect = $Flash
@onready var photo_badge: PanelContainer = $PhotoBadge
@onready var photo_badge_label: Label = $PhotoBadge/Label
@onready var hint_label: Label = $Hint
@onready var vignette: ColorRect = $Vignette

var _chapter_time: float = 0.0
var _subtitle_time: float = 0.0
var _flash_time: float = 0.0
var _objective_visible: bool = true
var _prompt_visible: bool = false
var _viewfinder: Control = null
var _viewfinder_blink: float = 0.0


func _ready() -> void:
	add_to_group("hud")
	add_to_group("photo_flash_layer")
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	process_mode = Node.PROCESS_MODE_ALWAYS

	InteractionSystem.focus_changed.connect(_on_focus)
	TaskSystem.chapter_hint_changed.connect(_on_hint)
	TaskSystem.task_accepted.connect(func(id: String) -> void: _show_objective(id))
	TaskSystem.task_completed.connect(func(_id: String) -> void: _on_hint(""))
	StorySystem.chapter_changed.connect(_on_chapter)
	DialogueSystem.line_shown.connect(_on_line)
	DialogueSystem.line_queue_drained.connect(_clear_line)
	PhotoSystem.photo_taken.connect(_on_photo)
	CameraSystem.viewfinder_changed.connect(_on_viewfinder)
	Settings.settings_changed.connect(_apply_settings)
	_apply_settings()
	_on_hint("")
	flash_rect.modulate.a = 0.0
	_build_viewfinder()


func _apply_settings() -> void:
	subtitle.visible = bool(Settings.get_value("show_subtitles", true))
	var tension := float(HorrorSystem.get_tension()) / 5.0
	vignette.color = Color(0, 0, 0, 0.12 + 0.2 * tension)


func _process(delta: float) -> void:
	var exploring := GameManager.mode == GameManager.Mode.EXPLORE
	crosshair.visible = exploring and not CameraSystem.is_viewing()
	hint_label.visible = exploring
	objective.visible = exploring and _objective_visible and _has_hint()

	if _viewfinder != null and _viewfinder.visible:
		_viewfinder_blink += delta
		var dot := _viewfinder.get_node_or_null("RecDot") as ColorRect
		if dot != null:
			dot.visible = fmod(_viewfinder_blink, 1.2) < 0.6

	if _chapter_time > 0.0:
		_chapter_time -= delta
		chapter_card.modulate.a = clampf(_chapter_time, 0.0, 1.0)
		if _chapter_time <= 0.0:
			chapter_card.visible = false
	if _subtitle_time > 0.0:
		_subtitle_time -= delta
		if _subtitle_time <= 0.0:
			subtitle.visible = false
	if _flash_time > 0.0:
		_flash_time -= delta
		flash_rect.modulate.a = clampf(_flash_time / 0.18, 0.0, 1.0) * 0.85
		if _flash_time <= 0.0:
			flash_rect.modulate.a = 0.0
	_apply_pointer()


func _apply_pointer() -> void:
	# HUD never captures input; it only reflects mode.
	if GameManager.is_exploring() and not OS.has_feature("mobile"):
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)


# --- slots ------------------------------------------------------------------

func _on_focus(target: Interactable, prompt_text: String) -> void:
	if target == null or prompt_text.is_empty():
		_prompt_visible = false
		prompt.visible = false
		return
	_prompt_visible = true
	prompt.visible = true
	prompt_label.text = "[%s] %s" % [target.prompt_key, prompt_text]


func _show_objective(task_id: String) -> void:
	var t := TaskSystem.get_task(task_id)
	if t == null:
		return
	_objective_visible = true
	_on_hint("%s — %s" % [t.id, TaskSystem.current_hint()])


func _on_hint(text: String) -> void:
	objective_text.text = text.strip_edges()


func _has_hint() -> bool:
	return objective_text.text.strip_edges() != ""


func _on_chapter(chapter: int, title: String) -> void:
	chapter_label.text = "%d\n%s" % [chapter, title.to_upper()]
	chapter_card.visible = true
	_chapter_time = 5.0
	chapter_card.modulate.a = 1.0
	AudioManager.play_horror("drone_hit")


func _on_line(text: String, _source: String) -> void:
	if not bool(Settings.get_value("show_subtitles", true)):
		return
	subtitle.visible = true
	subtitle_label.text = text
	_subtitle_time = DialogueSystem.LINE_VISIBLE_TIME
	AudioManager.play_ui("type")


func _clear_line() -> void:
	subtitle.visible = false


func _on_photo(record: PhotoRecord) -> void:
	flash()
	photo_badge.visible = true
	if record.valid and record.bug_id != "":
		photo_badge_label.text = "Снимок принят: %s" % record.bug_id
		photo_badge.add_theme_color_override("font_color", Color(0.5, 0.95, 0.6, 1))
	elif record.bug_id != "":
		photo_badge_label.text = "Аномалия вне кадра"
		photo_badge.add_theme_color_override("font_color", Color(0.95, 0.75, 0.4, 1))
	else:
		photo_badge_label.text = "Снимок %s · %d в архиве" % [record.id, PhotoSystem.count()]
		photo_badge.add_theme_color_override("font_color", Color(0.8, 0.85, 0.95, 1))
	photo_badge.modulate.a = 1.0
	var t := get_tree().create_timer(2.2)
	t.timeout.connect(func() -> void:
		if is_instance_valid(photo_badge):
			photo_badge.modulate.a = 0.0)


func flash() -> void:
	_flash_time = 0.18
	flash_rect.modulate.a = 0.85
	AudioManager.play_sfx("click", -6.0)


func toggle_objective() -> void:
	_objective_visible = not _objective_visible


func set_prompt_visible(value: bool) -> void:
	prompt.visible = value and _prompt_visible


# --- viewfinder --------------------------------------------------------------

## The frame is built in code because it is pure chrome: four corner brackets and
## a recording dot. No gameplay decision is taken here.
func _build_viewfinder() -> void:
	_viewfinder = Control.new()
	_viewfinder.name = "Viewfinder"
	_viewfinder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_viewfinder.set_anchors_preset(Control.PRESET_FULL_RECT)
	_viewfinder.visible = false
	add_child(_viewfinder)

	var shade := ColorRect.new()
	shade.name = "Shade"
	shade.color = Color(0, 0, 0, 0.28)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_viewfinder.add_child(shade)

	for corner: String in ["TL", "TR", "BL", "BR"]:
		var bracket := ColorRect.new()
		bracket.name = "Bracket%s" % corner
		bracket.color = Color(0.85, 0.87, 0.92, 0.75)
		bracket.mouse_filter = Control.MOUSE_FILTER_IGNORE
		bracket.anchor_left = 0.0 if corner.begins_with("L") else 1.0
		bracket.anchor_right = 0.0 if corner.begins_with("L") else 1.0
		bracket.anchor_top = 0.0 if corner.begins_with("T") else 1.0
		bracket.anchor_bottom = 0.0 if corner.begins_with("T") else 1.0
		bracket.offset_left = -150.0 if corner.begins_with("L") else -4.0
		bracket.offset_right = 4.0 if corner.begins_with("L") else 150.0
		bracket.offset_top = -4.0 if corner.begins_with("T") else -110.0
		bracket.offset_bottom = 110.0 if corner.begins_with("T") else 4.0
		_viewfinder.add_child(bracket)

	var dot := ColorRect.new()
	dot.name = "RecDot"
	dot.color = Color(0.9, 0.2, 0.18, 0.9)
	dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dot.set_anchors_preset(Control.PRESET_CENTER)
	dot.offset_left = -180.0
	dot.offset_right = -168.0
	dot.offset_top = -4.0
	dot.offset_bottom = 4.0
	_viewfinder.add_child(dot)


func _on_viewfinder(active: bool) -> void:
	if _viewfinder == null:
		return
	_viewfinder.visible = active
	_viewfinder_blink = 0.0
	if active:
		AudioManager.play_ui("type")
