extends Node
## Settings — user preferences, persisted separately from game progress.

signal settings_changed()

const SAVE_PATH := "user://settings.cfg"
const DEFAULTS := {
	"master_volume": 0.9,
	"music_volume": 0.6,
	"sfx_volume": 0.9,
	"ambience_volume": 0.8,
	"ui_volume": 0.8,
	"mouse_sensitivity": 0.002,
	"invert_y": false,
	"fov": 75.0,
	"head_bob_enabled": true,
	"grain_enabled": true,
	"scanlines_enabled": true,
	"film_grain_intensity": 0.35,
	"min_text_speed": 1.0,
	"show_subtitles": true,
	"touch_controls": true,
	"ui_scale": 1.0,
	"fullscreen": false,
	"screen_shake_enabled": true,
	"pause_anomaly_enabled": true,
	"text_mutation_enabled": true,
	"stingers_enabled": true,
}

var values: Dictionary = DEFAULTS.duplicate(true)
var _applied: Dictionary = {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	load_settings()
	settings_changed.connect(_on_changed)
	_apply_display()


func _on_changed() -> void:
	_apply_display()


## Window mode and interface scale belong to the settings that store them:
## keeping the apply here means no menu has to remember to push them.
func _apply_display() -> void:
	var window := get_tree().root
	if window == null:
		return
	var want_fullscreen := bool(get_value("fullscreen", false))
	var want_scale := clampf(float(get_value("ui_scale", 1.0)), 0.5, 2.0)
	# Every slider drag emits settings_changed, so only touch the window when a
	# display value really moved.
	if bool(_applied.get("fullscreen", not want_fullscreen)) == want_fullscreen \
			and is_equal_approx(float(_applied.get("ui_scale", -1.0)), want_scale):
		return
	_applied["fullscreen"] = want_fullscreen
	_applied["ui_scale"] = want_scale
	var mode := DisplayServer.window_get_mode()
	var is_fullscreen := mode == DisplayServer.WINDOW_MODE_FULLSCREEN \
		or mode == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN
	if want_fullscreen != is_fullscreen:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if want_fullscreen
			else DisplayServer.WINDOW_MODE_WINDOWED)
	window.content_scale_factor = want_scale


func get_value(key: String, fallback: Variant = null) -> Variant:
	if values.has(key):
		return values[key]
	if DEFAULTS.has(key):
		return DEFAULTS[key]
	return fallback


func set_value(key: String, value: Variant, save_immediately: bool = true) -> void:
	if not DEFAULTS.has(key):
		push_warning("Settings: unknown key '%s'" % key)
		return
	values[key] = value
	settings_changed.emit()
	if save_immediately:
		save_settings()


func reset_defaults() -> void:
	values = DEFAULTS.duplicate(true)
	settings_changed.emit()
	save_settings()


func save_settings() -> void:
	var cfg := ConfigFile.new()
	for key: Variant in values.keys():
		cfg.set_value("settings", str(key), values[key])
	var err := cfg.save(SAVE_PATH)
	if err != OK:
		push_warning("Settings: cannot save (%d)" % err)


func load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) != OK:
		return
	for key: Variant in DEFAULTS.keys():
		if cfg.has_section_key("settings", str(key)):
			values[key] = cfg.get_value("settings", str(key), DEFAULTS[key])
	settings_changed.emit()
