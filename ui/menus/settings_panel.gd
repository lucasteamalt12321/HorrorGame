extends PanelContainer
## SettingsPanel — one settings implementation, used by BOTH the pause menu
## (3D) and the in-computer window. Rule 4: no duplicated settings screens.

@onready var close: Button = $VBox/Header/Close
@onready var rows: VBoxContainer = $VBox/Scroll/Rows
@onready var hint: Label = $VBox/Hint

var _sliders: Dictionary = {}
var _checks: Dictionary = {}
var _built: bool = false


func _ready() -> void:
	add_to_group("settings_panel")
	var s := StyleBoxFlat.new()
	s.bg_color = Color(0.05, 0.06, 0.09, 0.98)
	s.border_color = Color(0.2, 0.34, 0.46, 1)
	s.set_border_width_all(1)
	s.set_content_margin_all(6)
	add_theme_stylebox_override("panel", s)
	close.pressed.connect(_on_close)
	Settings.settings_changed.connect(_sync)
	_ensure_built()


func _ensure_built() -> void:
	if _built:
		return
	_built = true
	_add_slider("Громкость", "master_volume", 0.0, 1.0, 0.01)
	_add_slider("Музыка", "music_volume", 0.0, 1.0, 0.01)
	_add_slider("Эмбиент", "ambience_volume", 0.0, 1.0, 0.01)
	_add_slider("Звуки", "sfx_volume", 0.0, 1.0, 0.01)
	_add_slider("Интерфейс", "ui_volume", 0.0, 1.0, 0.01)
	_add_slider("Чувствительность мыши", "mouse_sensitivity", 0.0005, 0.006, 0.0001)
	_add_slider("Поле зрения", "fov", 60.0, 100.0, 1.0)
	_add_slider("Скорость текста", "min_text_speed", 0.4, 3.0, 0.1)
	_add_slider("Масштаб интерфейса", "ui_scale", 0.75, 1.5, 0.05)
	_add_check("Покачивание камеры", "head_bob_enabled")
	_add_check("Тряска камеры", "screen_shake_enabled")
	_add_check("Зерно и развёртка", "grain_enabled")
	_add_check("Субтитры", "show_subtitles")
	_add_check("Полноэкранный режим", "fullscreen")
	_add_check("Сенсорное управление", "touch_controls")
	_sync()


func _add_slider(label_text: String, key: String, lo: float, hi: float, step: float) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	var l := Label.new()
	l.text = label_text
	l.custom_minimum_size = Vector2(150, 0)
	l.add_theme_font_size_override("font_size", 7)
	row.add_child(l)
	var s := HSlider.new()
	s.min_value = lo
	s.max_value = hi
	s.step = step
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.custom_minimum_size = Vector2(120, 12)
	s.value = float(Settings.get_value(key, lo))
	s.value_changed.connect(func(v: float) -> void:
		Settings.set_value(key, v)
		AudioManager.play_ui("tick"))
	row.add_child(s)
	var value_label := Label.new()
	value_label.text = _fmt(s.value, hi - lo)
	value_label.custom_minimum_size = Vector2(48, 0)
	value_label.add_theme_font_size_override("font_size", 7)
	row.add_child(value_label)
	s.value_changed.connect(func(v: float) -> void: value_label.text = _fmt(v, hi - lo))
	rows.add_child(row)
	_sliders[key] = [s, value_label]


func _add_check(label_text: String, key: String) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	var c := CheckBox.new()
	c.text = label_text
	c.button_pressed = bool(Settings.get_value(key, false))
	c.add_theme_font_size_override("font_size", 7)
	c.toggled.connect(func(on: bool) -> void:
		Settings.set_value(key, on)
		AudioManager.play_ui("click"))
	row.add_child(c)
	rows.add_child(row)
	_checks[key] = c


func _fmt(v: float, span: float) -> String:
	if span <= 1.5:
		return "%.2f" % v
	return "%.0f" % v


func _sync() -> void:
	for key: String in _sliders.keys():
		var entry: Array = _sliders[key]
		var s := entry[0] as HSlider
		var l := entry[1] as Label
		if s == null:
			continue
		var v := float(Settings.get_value(key, s.value))
		if not is_equal_approx(s.value, v):
			s.set_value_no_signal(v)
		if l != null:
			l.text = _fmt(v, s.max_value - s.min_value)
	for key: String in _checks.keys():
		var c := _checks[key] as CheckBox
		if c != null:
			c.set_pressed_no_signal(bool(Settings.get_value(key, false)))


func _on_close() -> void:
	AudioManager.play_ui("close")
	if is_inside_tree():
		var p := get_parent()
		while p != null and not (p is CanvasLayer or p is Control):
			p = p.get_parent()
		queue_free()


func reset_defaults() -> void:
	Settings.reset_defaults()
	_sync()
