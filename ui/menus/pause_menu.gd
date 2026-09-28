extends Control
## PauseMenu — Esc overlay. The only one; there is no second pause screen.
##
## It hosts the meta-horror beat: after the registration book has been read
## (chapter >= 1) a paused session stops being private. `HorrorSystem.pause_watch`
## reports the anomaly and the menu reacts instead of the game.

@onready var resume: Button = $Center/Column/Resume
@onready var save_button: Button = $Center/Column/Save
@onready var load_button: Button = $Center/Column/Load
@onready var settings_button: Button = $Center/Column/Settings
@onready var menu_button: Button = $Center/Column/MainMenu
@onready var quit_button: Button = $Center/Column/Quit
@onready var status: Label = $Center/Column/Status
@onready var anomaly: Label = $Anomaly
@onready var settings_host: Control = $SettingsHost
@onready var slots: VBoxContainer = $Center/Column/Slots

var _settings_panel: Control = null
var _anomaly_timer: float = 0.0


func _ready() -> void:
	add_to_group("pause_menu")
	visible = false
	resume.pressed.connect(_on_resume)
	save_button.pressed.connect(_on_save)
	load_button.pressed.connect(_on_load)
	settings_button.pressed.connect(_on_settings)
	menu_button.pressed.connect(_on_main_menu)
	quit_button.pressed.connect(_on_quit)
	anomaly.visible = false
	_slots_refresh()


func open() -> void:
	visible = true
	settings_host.visible = false
	_slots_refresh()
	CursorWatcher.begin()
	_anomaly_check()
	get_viewport().set_input_as_handled()


func close() -> void:
	visible = false
	settings_host.visible = false
	if _settings_panel != null and is_instance_valid(_settings_panel):
		_settings_panel.queue_free()
		_settings_panel = null


func _process(delta: float) -> void:
	if not visible:
		return
	if _anomaly_timer > 0.0:
		_anomaly_timer -= delta
		anomaly.modulate.a = clampf(_anomaly_timer, 0.0, 1.0)
		if _anomaly_timer <= 0.0:
			anomaly.visible = false
	# Keep the overlay alive and interactive while the tree is paused.
	process_mode = Node.PROCESS_MODE_ALWAYS


func _anomaly_check() -> void:
	if not HorrorSystem.pause_watch():
		return
	StoryFlags.set_flag(&"saw_pause_anomaly", true)
	anomaly.text = StorySystem.pause_anomaly_line()
	anomaly.visible = true
	anomaly.modulate.a = 1.0
	_anomaly_timer = 6.0
	AudioManager.play_horror("glitch")
	# Chapter 5 promise: the pause menu is where the pointer can be taken away.
	if StoryFlags.has_flag(&"game_noticed_player"):
		StoryFlags.set_flag(&"cursor_followed", true)


func _slots_refresh() -> void:
	for c in slots.get_children():
		c.queue_free()
	for i in SaveSystem.SLOT_COUNT:
		var b := Button.new()
		b.text = "Слот %d — %s" % [i, "есть" if SaveSystem.has_slot(i) else "пусто"]
		b.add_theme_font_size_override("font_size", 11)
		b.focus_mode = Control.FOCUS_NONE
		b.disabled = not SaveSystem.has_slot(i)
		b.pressed.connect(_on_load_slot.bind(i))
		slots.add_child(b)


func _on_resume() -> void:
	AudioManager.play_ui("close")
	close()
	GameManager.set_paused(false)


func _on_save() -> void:
	AudioManager.play_ui("click")
	if SaveSystem.save_game(SaveSystem.AUTOSAVE_SLOT):
		status.text = "Сохранено."
	else:
		status.text = "Не удалось сохранить: %s" % SaveSystem.last_error
	_slots_refresh()


func _on_load() -> void:
	_slots_refresh()


func _on_load_slot(slot: int) -> void:
	AudioManager.play_ui("click")
	if SaveSystem.load_game(slot):
		close()
		GameManager.set_paused(false)
	else:
		status.text = "Сохранение не читается: %s" % SaveSystem.last_error


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


func _on_main_menu() -> void:
	AudioManager.play_ui("close")
	SaveSystem.save_game(SaveSystem.AUTOSAVE_SLOT)
	close()
	get_tree().paused = false
	get_tree().change_scene_to_file("res://ui/menus/main_menu.tscn")


func _on_quit() -> void:
	AudioManager.play_ui("close")
	SaveSystem.save_game(SaveSystem.AUTOSAVE_SLOT)
	get_tree().quit()
