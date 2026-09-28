extends Interactable
## The office computer. Root of the 3D → 2D chain:
##   Computer (3D) → SubViewport (render target) → Desktop UI + 2D game.
##
## The 2D game is never a separate window: it is rendered into `ScreenViewport`
## and displayed on the physical screen mesh.

signal power_changed(on: bool)

@export var screen_size: Vector2i = Vector2i(320, 240)
@export var power_on: bool = false
@export var boot_delay: float = 1.6
@export var flicker_intensity: float = 1.0
@export var screen_light_energy: float = 1.4
@export var startup_power: bool = true

@onready var screen_mesh: MeshInstance3D = $Screen
@onready var screen_light: OmniLight3D = $ScreenLight
@onready var screen_viewport: SubViewport = $ScreenViewport

var _material: ShaderMaterial
var _flicker_time: float = 0.0
var _flicker_left: float = 0.0
var _glitch_left: float = 0.0
var _glitch_amount: float = 0.0


func _ready() -> void:
	super()
	prompt_text = "Сесть за компьютер"
	focus_priority = 10
	focus_radius = 2.2
	screen_viewport.size = screen_size
	screen_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	screen_viewport.handle_input_locally = false
	_build_material()
	HorrorSystem.register_receiver(HorrorEventResource.Target.COMPUTER, self)
	HorrorSystem.register_receiver(HorrorEventResource.Target.MONITOR, self)
	if startup_power:
		call_deferred("power_on_screen", true)


func _build_material() -> void:
	var tex := ViewportTexture.new()
	tex.viewport_path = screen_viewport.get_path()
	_material = ShaderMaterial.new()
	var shader: Shader = load("res://shaders/monitor.gdshader")
	if shader != null:
		_material.shader = shader
	_material.set_shader_parameter("screen_texture", tex)
	_material.set_shader_parameter("power_on", 1.0 if power_on else 0.0)
	screen_mesh.material_override = _material
	if not bool(Settings.get_value("scanlines_enabled", true)):
		_material.set_shader_parameter("scanline_strength", 0.0)


# --- interaction ------------------------------------------------------------

func get_prompt() -> String:
	if ComputerSystem.is_active:
		return ""
	return prompt_text


func can_interact(_by: Node) -> bool:
	return super(_by) and not ComputerSystem.is_active


func on_interact(_by: Node) -> bool:
	if not super(_by):
		return false
	ComputerSystem.enter(self)
	return true


# --- monitor access ---------------------------------------------------------

func get_monitor_node() -> Node3D:
	return self


func get_screen_viewport() -> SubViewport:
	return screen_viewport


# --- power / horror ---------------------------------------------------------

func power_on_screen(on: bool) -> void:
	if power_on == on:
		return
	power_on = on
	power_changed.emit(on)
	_apply_power()


func _apply_power() -> void:
	if _material != null:
		_material.set_shader_parameter("power_on", 1.0 if power_on else 0.0)
	if screen_light != null:
		screen_light.light_energy = screen_light_energy if power_on else 0.0
		screen_light.visible = power_on
		ApplySettings()
		ApplyScanlines()


func ApplySettings() -> void:
	if _material == null:
		return
	_material.set_shader_parameter("noise_amount", 0.035 + 0.05 * float(HorrorSystem.get_tension()) / 5.0)
	_material.set_shader_parameter("vignette_strength", 0.3 + 0.2 * float(HorrorSystem.get_tension()) / 5.0)


func ApplyScanlines() -> void:
	if _material == null:
		return
	_material.set_shader_parameter("scanline_strength", 0.22 if bool(Settings.get_value("scanlines_enabled", true)) else 0.0)


func set_light_flicker(duration: float) -> void:
	_flicker_left = maxf(_flicker_left, duration)


func set_glitch(amount: float, duration: float = 0.4) -> void:
	_glitch_left = maxf(_glitch_left, duration)
	_glitch_amount = amount


func _process(delta: float) -> void:
	if _material == null:
		return
	if _flicker_left > 0.0:
		_flicker_left -= delta
		var on := randf() > 0.35
		_material.set_shader_parameter("power_on", 1.0 if on else 0.0)
		if screen_light != null:
			screen_light.light_energy = screen_light_energy * (0.8 if on else 0.2)
		if _flicker_left <= 0.0:
			_material.set_shader_parameter("power_on", 1.0 if power_on else 0.0)
			if screen_light != null:
				screen_light.light_energy = screen_light_energy if power_on else 0.0
	if _glitch_left > 0.0:
		_glitch_left -= delta
		_material.set_shader_parameter("glitch_amount", _glitch_amount * clampf(_glitch_left / 0.4, 0.0, 1.0))
		if _glitch_left <= 0.0:
			_material.set_shader_parameter("glitch_amount", 0.0)
