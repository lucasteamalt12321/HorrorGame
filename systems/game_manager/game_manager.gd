extends Node

enum Mode { EXPLORE, COMPUTER, MINIGAME, BLOCKED }

signal mode_changed(new_mode: Mode, old_mode: Mode)

var mode: Mode = Mode.EXPLORE

func set_mode(new_mode: Mode) -> void:
	if new_mode == mode:
		return
	var old_mode := mode
	mode = new_mode
	mode_changed.emit(mode, old_mode)
	_update_mouse_mode()

func is_exploring() -> bool:
	return mode == Mode.EXPLORE

func _ready() -> void:
	_update_mouse_mode()

func _input(event: InputEvent) -> void:
	if _is_mobile():
		return
	if event.is_action_pressed("ui_cancel") and is_exploring():
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

func _update_mouse_mode() -> void:
	if _is_mobile():
		return
	if is_exploring():
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	else:
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

func _is_mobile() -> bool:
	return OS.has_feature("mobile") or OS.has_feature("android") or OS.has_feature("ios")