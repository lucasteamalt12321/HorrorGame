extends Node
## GameRoot — the single session owner for a play session.
##
## Rule 5/6/7: the HUD, the gallery and the pause menu are instantiated here
## instead of being duplicated in every scene. World scenes stay "dumb": they
## contain geometry and the systems, never UI wiring.

const HUD_SCENE := "res://ui/hud/hud.tscn"
const GALLERY_SCENE := "res://ui/photo/gallery.tscn"
const PAUSE_SCENE := "res://ui/menus/pause_menu.tscn"
const OVERLAY_SHADER := "res://shaders/post_overlay.gdshader"

@onready var ui_root: CanvasLayer = $UIRoot
@onready var post: ColorRect = $PostOverlay

var hud: Control = null
var gallery: Control = null
var pause_menu: Control = null
var _post_material: ShaderMaterial = null
var _tension_level: int = 0


func _ready() -> void:
	add_to_group("game_root")
	process_mode = Node.PROCESS_MODE_ALWAYS
	_post_material = ShaderMaterial.new()
	_post_material.shader = load(OVERLAY_SHADER)
	post.material = _post_material
	_apply_post_settings()
	Settings.settings_changed.connect(_apply_post_settings)
	_spawn_ui()
	HorrorSystem.tension_level_changed.connect(_on_tension)
	GameManager.paused_changed.connect(_on_paused)


# --- UI lifecycle -----------------------------------------------------------

func _spawn_ui() -> void:
	hud = (load(HUD_SCENE) as PackedScene).instantiate()
	ui_root.add_child(hud)


func open_gallery() -> void:
	if gallery != null and is_instance_valid(gallery):
		return
	StoryFlags.set_flag(&"photo_gallery_opened", true)
	gallery = (load(GALLERY_SCENE) as PackedScene).instantiate()
	ui_root.add_child(gallery)
	AudioManager.play_ui("open")
	GameManager.set_pointer_visible(false)
	_hud_visibility(false)


func close_gallery() -> void:
	if gallery != null and is_instance_valid(gallery):
		gallery.queue_free()
	gallery = null
	GameManager.set_pointer_visible(true)
	_hud_visibility(true)
	AudioManager.play_ui("close")


func is_gallery_open() -> bool:
	return gallery != null and is_instance_valid(gallery)


func toggle_gallery() -> void:
	if is_gallery_open():
		close_gallery()
	else:
		open_gallery()


func open_pause() -> void:
	if pause_menu == null or not is_instance_valid(pause_menu):
		pause_menu = (load(PAUSE_SCENE) as PackedScene).instantiate()
		ui_root.add_child(pause_menu)
	pause_menu.call("open")
	GameManager.set_pointer_visible(true)
	_hud_visibility(false)


func close_pause() -> void:
	if pause_menu != null and is_instance_valid(pause_menu):
		pause_menu.call("close")


func _hud_visibility(value: bool) -> void:
	if hud != null and is_instance_valid(hud):
		hud.visible = value


# --- global input -----------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") or event.is_action_pressed("pause"):
		if is_gallery_open():
			close_gallery()
		elif get_tree().paused:
			close_pause()
			GameManager.set_paused(false)
		elif GameManager.is_exploring():
			open_pause()
			GameManager.set_paused(true)
		elif GameManager.is_in_computer():
			ComputerSystem.close_top()
		get_viewport().set_input_as_handled()
		return

	if not GameManager.is_exploring():
		return

	if event.is_action_pressed("gallery"):
		toggle_gallery()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("camera_viewfinder"):
		if not is_gallery_open():
			CameraSystem.toggle()
	elif event.is_action_pressed("photo"):
		if not is_gallery_open():
			var rec := PhotoSystem.take_photo()
			if rec == null:
				AudioManager.play_computer("error")
	elif event.is_action_pressed("objective_toggle"):
		if hud != null and hud.has_method("toggle_objective"):
			hud.call("toggle_objective")


# --- post processing --------------------------------------------------------

func _apply_post_settings() -> void:
	if _post_material == null:
		return
	# The overlay also carries the vignette and the meta-horror distortion, so
	# switching the grain off must not switch the whole pass off. Only when the
	# grain, the scanlines and the vignette are all off is the pass pointless.
	var grain := bool(Settings.get_value("grain_enabled", true))
	var scanlines := bool(Settings.get_value("scanlines_enabled", true))
	var vignette := 0.35 + 0.09 * _tension_level
	_post_material.set_shader_parameter("grain_enabled", 1.0 if grain else 0.0)
	_post_material.set_shader_parameter("grain_intensity",
		float(Settings.get_value("film_grain_intensity", 0.35)))
	_post_material.set_shader_parameter("scanline_enabled",
		1.0 if scanlines else 0.0)
	_post_material.set_shader_parameter("vignette_strength", vignette)
	# The picture only starts to come apart once the tension is high.
	_post_material.set_shader_parameter("distortion",
		0.0 if _tension_level < 3 else 0.004 * (_tension_level - 2))
	post.visible = grain or scanlines or vignette > 0.0


func _on_tension(level: int) -> void:
	_tension_level = level
	_apply_post_settings()
	if hud != null and hud.has_method("_apply_settings"):
		hud.call("_apply_settings")


func _on_paused(value: bool) -> void:
	if value:
		return
	# Unpausing must never leave stale music layers running.
	AudioManager.set_loop_gain("music_calm", -8.0 if is_gallery_open() else -30.0, 0.4)


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		SaveSystem.save_game(SaveSystem.AUTOSAVE_SLOT)
