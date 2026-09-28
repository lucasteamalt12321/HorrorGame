extends Control
## MainMenu — entry point. Owns nothing but navigation and the title screen
## atmosphere; settings live in the shared settings panel.

const WORLD_SCENE := "res://scenes/levels/world.tscn"

@onready var slots: VBoxContainer = $Center/Menu/Slots
@onready var new_button: Button = $Center/Menu/Actions/New
@onready var continue_button: Button = $Center/Menu/Actions/Continue
@onready var settings_button: Button = $Center/Menu/Actions/Settings
@onready var quit_button: Button = $Center/Menu/Actions/Quit
@onready var version_label: Label = $Bottom/Version
@onready var settings_host: Control = $SettingsHost
@onready var subtitle: Label = $Center/Title/Subtitle
@onready var flicker: ColorRect = $Flicker

var _settings_panel: Control = null
var _t: float = 0.0


func _ready() -> void:
	add_to_group("main_menu")
	new_button.pressed.connect(_on_new)
	continue_button.pressed.connect(_on_continue)
	settings_button.pressed.connect(_on_settings)
	quit_button.pressed.connect(_on_quit)
	version_label.text = "сборка %s · рендер %s" % [
		ProjectSettings.get_setting("application/config/version", "dev"),
		ProjectSettings.get_setting("rendering/renderer/rendering_method", "—")
	]
	_refresh_slots()
	subtitle.text = _random_subtitle()
	AudioManager.set_tension(0)
	AudioManager.set_loop_gain("music_calm", -30.0, 2.0)
	AudioManager.play_horror("whisper")


func _random_subtitle() -> String:
	var lines := [
		"Тестировщик QA-07. Смена 1.",
		"Сборка 0.7.13. Проект: NINE CIRCLES.",
		"Не закрывайте приложения во время тестирования.",
		"Если что-то выглядит неправильно — это баг.",
	]
	return String(lines[randi() % lines.size()])


func _process(delta: float) -> void:
	_t += delta
	# Slow, almost subliminal brightness drift.
	flicker.modulate.a = 0.03 + 0.03 * sin(_t * 1.7) + 0.02 * sin(_t * 7.3)


func _refresh_slots() -> void:
	for c in slots.get_children():
		c.queue_free()
	continue_button.disabled = not SaveSystem.has_slot(SaveSystem.AUTOSAVE_SLOT)
	for i in SaveSystem.SLOT_COUNT:
		var b := Button.new()
		b.text = "Слот %d — %s" % [i, _slot_label(i)]
		b.add_theme_font_size_override("font_size", 10)
		b.focus_mode = Control.FOCUS_NONE
		b.pressed.connect(_on_load_slot.bind(i))
		slots.add_child(b)


func _slot_label(i: int) -> String:
	if not SaveSystem.has_slot(i):
		return "пусто"
	var f := FileAccess.open(SaveSystem.slot_path(i), FileAccess.READ)
	if f == null:
		return "повреждён"
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if typeof(parsed) != TYPE_DICTIONARY:
		return "повреждён"
	var d: Dictionary = parsed
	var chapter := int(d.get("providers", {}).get("story", {}).get("chapter", 0))
	return "глава %d · %s" % [chapter, _time_of(int(d.get("playtime", 0.0)))]


func _time_of(seconds: int) -> String:
	return "%02d:%02d" % [seconds / 60, seconds % 60]


func _on_new() -> void:
	AudioManager.play_ui("click")
	SaveSystem.delete_slot(SaveSystem.AUTOSAVE_SLOT)
	_start_world()


func _on_continue() -> void:
	_on_load_slot(SaveSystem.AUTOSAVE_SLOT)


func _on_load_slot(slot: int) -> void:
	AudioManager.play_ui("click")
	if not SaveSystem.load_game(slot):
		AudioManager.play_computer("error")
		subtitle.text = "Сохранение не читается: %s" % SaveSystem.last_error
		return
	_start_world()


func _start_world() -> void:
	get_tree().change_scene_to_file(WORLD_SCENE)


func _on_settings() -> void:
	AudioManager.play_ui("open")
	if _settings_panel != null and is_instance_valid(_settings_panel):
		return
	var packed := load("res://ui/menus/settings_panel.tscn") as PackedScene
	if packed == null:
		return
	_settings_panel = packed.instantiate()
	settings_host.visible = true
	settings_host.add_child(_settings_panel)


func _on_quit() -> void:
	AudioManager.play_ui("close")
	SaveSystem.save_game(SaveSystem.AUTOSAVE_SLOT)
	get_tree().quit()
