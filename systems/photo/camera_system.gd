extends Node
## CameraSystem — the physical act of raising the camera to your eye.
##
## PhotoSystem owns the evidence a capture produces; this system owns the
## viewfinder the tester looks through. They are deliberately separate: raising
## the camera must never be a requirement for taking a shot, and the horror beat
## "the frame is not a frame" needs its own owner.
##
## The viewfinder is additive: pressing LMB always takes a photograph, the right
## mouse button raises and lowers the camera. Nothing here can lock the player
## out of progress, and closing the viewfinder always restores the FOV.

signal viewfinder_changed(active: bool)

const ZOOM := 0.58
## How fast the lens pulls in, and how far the aim steadies while raised.
@export var zoom_speed: float = 9.0
@export var steady_look: float = 0.45
## Tension at which the frame starts to breathe on its own.
@export var drift_tension: int = 3

var _active: bool = false
var _blend: float = 0.0
var _open_time: float = 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	GameManager.mode_changed.connect(_on_mode_changed)
	HorrorSystem.tension_level_changed.connect(_on_tension_changed)


func _process(delta: float) -> void:
	var target := 1.0 if _active else 0.0
	if is_equal_approx(_blend, target):
		return
	_blend = move_toward(_blend, target, zoom_speed * delta)
	var player := GameManager.get_player()
	if player != null and player.has_method("set_fov_scale"):
		player.call("set_fov_scale", lerpf(1.0, ZOOM, _blend))
	if player != null and player.has_method("set_look_scale"):
		player.call("set_look_scale", lerpf(1.0, steady_look, _blend))
	if _active:
		_open_time += delta
	else:
		_open_time = 0.0


func is_viewing() -> bool:
	return _active


## Raises or lowers the camera. Returns false when the mode forbids it.
func toggle() -> bool:
	if not _can_view():
		return false
	_active = not _active
	AudioManager.play_ui("click" if not _active else "open")
	if not _active:
		_restore_look()
	viewfinder_changed.emit(_active)
	return true


func _can_view() -> bool:
	if get_tree().paused:
		return false
	return GameManager.mode == GameManager.Mode.EXPLORE or GameManager.is_in_computer()


## Any mode change or pause must put the lens back, otherwise the FOV multiplier
## would survive into the next scene and the player would play half-blind.
func _on_mode_changed(new_mode: GameManager.Mode, _old_mode: GameManager.Mode) -> void:
	if not _active:
		return
	if new_mode != GameManager.Mode.EXPLORE and new_mode != GameManager.Mode.COMPUTER:
		_active = false
		_blend = 0.0
		_restore_look()
		viewfinder_changed.emit(false)


func _on_tension_changed(level: int) -> void:
	if not _active:
		return
	if level >= drift_tension:
		AudioManager.play_horror("whisper")
		DialogueSystem.queue_line("Видоискатель держит ровно. Слишком ровно.", "CameraSystem")


func _restore_look() -> void:
	var player := GameManager.get_player()
	if player != null and player.has_method("set_look_scale"):
		player.call("set_look_scale", 1.0)
