extends Control
## DesktopShell — the operating system inside the monitor.
##
## It only routes: every window is a separate scene whose script reads the
## relevant system. No game rules live here (rule 5).

# Keyed by the string app ids ComputerSystem announces on app_changed, not by
# the App enum: _on_app_changed() only ever sees the string, and a dict lookup
# with the wrong key type silently means "no window, no warning".
const APP_SCENES := {
	"bugtracker": "res://ui/computer/apps/bug_tracker.tscn",
	"mail": "res://ui/computer/apps/mail_app.tscn",
	"notes": "res://ui/computer/apps/notes_app.tscn",
	"files": "res://ui/computer/apps/files_app.tscn",
	"settings": "res://ui/menus/settings_panel.tscn",
}
const APP_TITLES := {
	"desktop": "Рабочий стол",
	"bugtracker": "Баг-трекер",
	"mail": "Почта",
	"notes": "Заметки",
	"files": "Файлы сборки",
	"settings": "Настройки",
	"game": "NINE CIRCLES — сборка 0.7.13",
}
const APP_ICONS := {
	"game": "ИГРА",
	"bugtracker": "БАГИ",
	"mail": "ПОЧТА",
	"notes": "ЗАМЕТКИ",
	"files": "ФАЙЛЫ",
	"settings": "НАСТР.",
}

@onready var icon_grid: GridContainer = $IconGrid
@onready var window_layer: Control = $WindowLayer
@onready var boot_overlay: ColorRect = $BootOverlay
@onready var boot_label: Label = $BootOverlay/BootLabel
@onready var title_label: Label = $Taskbar/TaskbarRow/Title
@onready var status_label: Label = $Taskbar/TaskbarRow/Status
@onready var clock_label: Label = $Taskbar/TaskbarRow/Clock
@onready var toast: Label = $Toast

var _windows: Dictionary = {}
var _toast_time: float = 0.0
var _boot_dots: float = 0.0


func _ready() -> void:
	add_to_group("computer_desktop")
	mouse_filter = Control.MOUSE_FILTER_PASS
	_build_icons()
	ComputerSystem.app_changed.connect(_on_app_changed)
	ComputerSystem.enter_requested.connect(_on_enter)
	ComputerSystem.exited.connect(_on_exit)
	DialogueSystem.line_shown.connect(_on_line)
	DialogueSystem.unread_changed.connect(func(_n: int) -> void: _refresh_icons())
	StorySystem.chapter_changed.connect(func(_c: int, t: String) -> void: title_label.text = "QA-STATION 01 · %s" % t.to_upper())
	DialogueSystem.unlock_email("mail_00_welcome")
	_refresh_icons()


func _build_icons() -> void:
	for child in icon_grid.get_children():
		child.queue_free()
	var order := [
		ComputerSystem.App.GAME,
		ComputerSystem.App.BUGTRACKER,
		ComputerSystem.App.MAIL,
		ComputerSystem.App.NOTES,
		ComputerSystem.App.FILES,
		ComputerSystem.App.SETTINGS,
	]
	for app: int in order:
		var b := Button.new()
		b.text = String(APP_ICONS.get(String(ComputerSystem.APP_IDS[app]), "?"))
		b.custom_minimum_size = Vector2(52, 34)
		b.focus_mode = Control.FOCUS_NONE
		b.add_theme_font_size_override("font_size", 6)
		b.pressed.connect(_on_icon_pressed.bind(app))
		b.mouse_entered.connect(func() -> void: AudioManager.play_ui("hover"))
		icon_grid.add_child(b)


func _refresh_icons() -> void:
	var unread := DialogueSystem.unread_count()
	if unread > 0:
		for child in icon_grid.get_children():
			var b := child as Button
			if b != null and b.text.begins_with("ПОЧТА"):
				b.text = "ПОЧТА %d" % unread
	_refresh_status()


func _refresh_status() -> void:
	if not is_inside_tree():
		return
	if MinigameSystem.is_game_running():
		var st := MinigameSystem.get_hud_state()
		status_label.text = "В ИГРЕ: %s" % st.get("level_name", "")
		status_label.add_theme_color_override("font_color", Color(0.95, 0.75, 0.4, 1))
	elif ComputerSystem.is_booting():
		status_label.text = "ЗАГРУЗКА"
		status_label.add_theme_color_override("font_color", Color(0.7, 0.8, 0.95, 1))
	else:
		status_label.text = "ГОТОВ"
		status_label.add_theme_color_override("font_color", Color(0.4, 0.85, 0.55, 1))


func _process(delta: float) -> void:
	# ComputerSystem owns the length of the boot; the desktop only shows it. Two
	# independent timers used to drift apart, and for a moment the boot screen was
	# gone while the system still refused to open anything, or the other way round.
	boot_overlay.visible = ComputerSystem.is_booting()
	if boot_overlay.visible:
		_boot_dots += delta
		var dots := ".".repeat(1 + int(_boot_dots * 3.0) % 3)
		boot_label.text = "QA-STATION 01\nPOST ...\nЗагрузка профиля тестировщика%s" % dots
	if _toast_time > 0.0:
		_toast_time -= delta
		if _toast_time <= 0.0:
			toast.text = ""
	var total := int(GameManager.total_playtime)
	clock_label.text = "%02d:%02d" % [total / 60, total % 60]
	_refresh_status()


# --- routing ----------------------------------------------------------------

func _on_icon_pressed(app: int) -> void:
	if app == ComputerSystem.App.GAME:
		launch_game()
		return
	ComputerSystem.open_app(app)


func launch_game() -> void:
	if MinigameSystem.is_game_running():
		ComputerSystem.stack_push(ComputerSystem.App.GAME)
		show_toast("Игра уже запущена")
		return
	ComputerSystem.open_app(ComputerSystem.App.GAME)


func _on_enter(_computer: Node3D) -> void:
	_boot_dots = 0.0
	show_toast("Сессия восстановлена")
	_refresh_icons()


func _on_exit() -> void:
	_close_all_windows()
	_boot_dots = 0.0
	toast.text = ""


func _on_app_changed(app_id: String) -> void:
	for key: Variant in _windows.keys():
		var w: Control = _windows[key]
		if is_instance_valid(w):
			w.visible = str(key) == app_id
	title_label.text = "QA-STATION 01 · %s" % String(APP_TITLES.get(app_id, app_id.to_upper()))
	if app_id == "game":
		_hide_windows()
	elif app_id != "desktop":
		_ensure_window(app_id)


func _ensure_window(app_id: String) -> void:
	if _windows.has(app_id) and is_instance_valid(_windows[app_id]):
		_windows[app_id].visible = true
		return
	if not APP_SCENES.has(app_id):
		return
	var packed := load(String(APP_SCENES[app_id])) as PackedScene
	if packed == null:
		push_error("Desktop: cannot load app '%s' (scene '%s')" % [app_id, APP_SCENES[app_id]])
		return
	var win: Control = packed.instantiate()
	if win == null:
		push_error("Desktop: app '%s' did not instantiate" % app_id)
		return
	win.name = "App_" + app_id.capitalize()
	win.set_anchors_preset(Control.PRESET_FULL_RECT)
	win.visible = true
	window_layer.add_child(win)
	_windows[app_id] = win


func _hide_windows() -> void:
	for app: Variant in _windows.keys():
		var w: Control = _windows[app]
		if is_instance_valid(w):
			w.visible = false


func _close_all_windows() -> void:
	for app: Variant in _windows.keys():
		var w: Control = _windows[app]
		if is_instance_valid(w):
			w.queue_free()
	_windows.clear()


func show_toast(text: String, duration: float = 2.4) -> void:
	toast.text = text
	_toast_time = duration


func _on_line(text: String, _source: String) -> void:
	show_toast(text, 3.0)
