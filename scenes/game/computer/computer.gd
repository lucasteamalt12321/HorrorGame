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


# --- input routing -----------------------------------------------------------
#
# The desktop is a Control inside this monitor's SubViewport, and Godot does NOT
# deliver root viewport input to a 3D-embedded SubViewport: the desktop was
# visible on the screen mesh and completely dead to the mouse. The engine only
# processes events we push into the SubViewport ourselves, so the player path is
# root event -> screen quad -> SubViewport-local pixels -> push_input.
#
# The quad is measured from the mesh AABB instead of assuming an axis order: a
# PlaneMesh authored facing +Z and one facing +Y must both map correctly.

## True when the monitor is powered and able to take input.
func accepts_input() -> bool:
	return power_on and screen_viewport != null and not screen_viewport.gui_disable_input


## Routes one root-viewport mouse event onto the screen. Returns true when the
## event landed inside the visible screen area and was consumed.
func route_input(event: InputEvent) -> bool:
	if not accepts_input():
		return false
	if not (event is InputEventMouse):
		return false
	var uv := _screen_uv((event as InputEventMouse).position)
	if uv.x < 0.0:
		return false
	var local := _uv_to_subviewport(uv)
	var copy := (event as InputEventMouse).duplicate() as InputEventMouse
	copy.position = local
	copy.global_position = local
	screen_viewport.push_input(copy, true)
	return true


## Screen position of a point on the desktop, in root viewport pixels. The
## inverse of `route_input`.
func screen_position_for_uv(uv: Vector2) -> Vector2:
	var cam := _camera()
	if cam == null:
		return Vector2(-1.0, -1.0)
	return cam.unproject_position(screen_mesh.global_transform * _uv_to_local(uv))


## SubViewport pixel coordinates of a point on the desktop.
func subviewport_position_for_uv(uv: Vector2) -> Vector2:
	return _uv_to_subviewport(uv)


func _camera() -> Camera3D:
	var player := GameManager.get_player()
	if player != null:
		var cam := player.get_node_or_null("Head/Camera3D") as Camera3D
		if cam != null:
			return cam
	return get_viewport().get_camera_3d()


## Root viewport pixels -> 0..1 coordinates on the screen. -1 when the mouse ray
## misses the quad.
func _screen_uv(screen_pos: Vector2) -> Vector2:
	var cam := _camera()
	if cam == null or screen_mesh.mesh == null:
		return Vector2(-1.0, -1.0)
	var plane := _screen_plane(cam)
	var hit: Variant = plane.intersects_ray(cam.project_ray_origin(screen_pos),
		cam.project_ray_normal(screen_pos))
	if hit == null:
		return Vector2(-1.0, -1.0)
	var frame := _screen_frame()
	var local: Vector3 = screen_mesh.global_transform.affine_inverse() * (hit as Vector3)
	var center: Vector3 = frame["center"]
	var u_idx: int = frame["u"]
	var v_idx: int = frame["v"]
	var su: float = frame["su"]
	var sv: float = frame["sv"]
	if su <= 0.0 or sv <= 0.0:
		return Vector2(-1.0, -1.0)
	var uv := Vector2(
		(_comp(local, u_idx) - _comp(center, u_idx)) / su + 0.5,
		0.5 - (_comp(local, v_idx) - _comp(center, v_idx)) / sv)
	if uv.x < 0.0 or uv.x > 1.0 or uv.y < 0.0 or uv.y > 1.0:
		return Vector2(-1.0, -1.0)
	return uv


## The screen plane in world space, with its normal turned towards the camera so
## a ray from the player's eye always meets it from the front.
func _screen_plane(cam: Camera3D) -> Plane:
	var frame := _screen_frame()
	var thin: int = frame["n"]
	var local_normal := Vector3(0.0, 0.0, 0.0)
	local_normal = _with_comp(local_normal, thin, 1.0)
	var center: Vector3 = screen_mesh.global_transform * (frame["center"] as Vector3)
	var normal := (screen_mesh.global_transform.basis * local_normal).normalized()
	if normal.dot(cam.global_position - center) < 0.0:
		normal = -normal
	return Plane(normal, center)


## Local-space description of the screen quad, taken from the mesh bounds: the
## thinnest axis is the screen normal, the widest of the two remaining axes is
## the horizontal one. A monitor is a landscape surface, so that split is the
## only one the game needs.
func _screen_frame() -> Dictionary:
	var aabb := screen_mesh.mesh.get_aabb()
	var e := aabb.size
	var thin := 0
	if e.y < e.x and e.y <= e.z:
		thin = 1
	elif e.z < e.x and e.z < e.y:
		thin = 2
	var rest: Array[int] = []
	for i in 3:
		if i != thin:
			rest.append(i)
	var u_idx: int = rest[0]
	var v_idx: int = rest[1]
	if e[rest[1]] > e[rest[0]]:
		u_idx = rest[1]
		v_idx = rest[0]
	return {
		"center": aabb.get_center(),
		"n": thin,
		"u": u_idx,
		"v": v_idx,
		"su": e[u_idx],
		"sv": e[v_idx],
	}


func _comp(v: Vector3, i: int) -> float:
	match i:
		0:
			return v.x
		1:
			return v.y
		_:
			return v.z


func _with_comp(v: Vector3, i: int, value: float) -> Vector3:
	match i:
		0:
			v.x = value
		1:
			v.y = value
		_:
			v.z = value
	return v


func _uv_to_local(uv: Vector2) -> Vector3:
	var frame := _screen_frame()
	var center: Vector3 = frame["center"]
	var local := _with_comp(center, int(frame["u"]),
		_comp(center, int(frame["u"])) + (uv.x - 0.5) * float(frame["su"]))
	return _with_comp(local, int(frame["v"]),
		_comp(center, int(frame["v"])) + (0.5 - uv.y) * float(frame["sv"]))


func _uv_to_subviewport(uv: Vector2) -> Vector2:
	var vp := screen_viewport.size
	return Vector2(uv.x * float(vp.x), uv.y * float(vp.y))

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
