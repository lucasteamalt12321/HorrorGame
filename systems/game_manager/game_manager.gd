extends Node
## GameManager — root coordinator.
##
## Owns ONLY: control modes, input routing, mouse/pointer state, pause,
## scene root reference and session-level counters used by meta-horror.
## Owns NO content, NO story logic, NO gameplay rules.

signal mode_changed(new_mode: Mode, old_mode: Mode)
signal paused_changed(is_paused: bool)
signal player_registered(player: Node)

enum Mode {
	EXPLORE,   ## Free movement in the 3D office.
	COMPUTER,  ## Player is "inside" the computer: desktop OS shell is active.
	MINIGAME,  ## The 2D game under test is running inside the monitor.
	BLOCKED,   ## Cutscene / horror event / modal UI — no gameplay input.
}

const MODE_NAMES := {
	Mode.EXPLORE: "explore",
	Mode.COMPUTER: "computer",
	Mode.MINIGAME: "minigame",
	Mode.BLOCKED: "blocked",
}

@export var log_mode_changes: bool = false

var mode: Mode = Mode.EXPLORE
var player: Node3D = null

## Incremented every time the player pauses. Meta-horror reads this counter.
var pause_count: int = 0
## Wall-clock seconds of uninterrupted play since the last pause.
var time_since_pause: float = 0.0
var total_playtime: float = 0.0
var session_start_msec: int = 0

var _last_mode: Mode = Mode.EXPLORE
var _is_paused: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_last_mode = mode
	session_start_msec = Time.get_ticks_msec()


func _process(delta: float) -> void:
	if not _is_paused:
		total_playtime += delta
		time_since_pause += delta


# --- mode -------------------------------------------------------------------

func set_mode(new_mode: Mode) -> void:
	if new_mode == mode:
		return
	var old_mode := mode
	mode = new_mode
	if log_mode_changes:
		print("[GameManager] mode: %s -> %s" % [MODE_NAMES[old_mode], MODE_NAMES[new_mode]])
	mode_changed.emit(mode, old_mode)
	_apply_pointer_mode()


func get_mode_name() -> String:
	return String(MODE_NAMES.get(mode, "unknown"))


func is_exploring() -> bool:
	return mode == Mode.EXPLORE and not _is_paused


func is_in_computer() -> bool:
	return mode == Mode.COMPUTER or mode == Mode.MINIGAME


func is_minigame_running() -> bool:
	return mode == Mode.MINIGAME


func is_input_blocked() -> bool:
	return mode == Mode.BLOCKED or _is_paused


func restore_previous_mode() -> void:
	set_mode(_last_mode if _last_mode != mode else Mode.EXPLORE)


# --- pause ------------------------------------------------------------------

func set_paused(value: bool) -> void:
	if _is_paused == value:
		return
	_is_paused = value
	get_tree().paused = value
	if value:
		pause_count += 1
		time_since_pause = 0.0
	paused_changed.emit(_is_paused)
	_apply_pointer_mode()


func is_paused() -> bool:
	return _is_paused


func toggle_pause() -> void:
	set_paused(not _is_paused)


# --- player -----------------------------------------------------------------

func register_player(node: Node3D) -> void:
	player = node
	player_registered.emit(node)


func get_player() -> Node3D:
	if is_instance_valid(player):
		return player
	return get_tree().get_first_node_in_group("player") as Node3D


# --- pointer ----------------------------------------------------------------

## True on platforms where the mouse should never be captured: the player
## drives a touch d-pad instead, so the cursor has to stay visible for UI.
func is_mobile() -> bool:
	return OS.has_feature("mobile") or OS.has_feature("android") or OS.has_feature("ios")


func _apply_pointer_mode() -> void:
	if is_mobile():
		return
	if mode == Mode.EXPLORE and not _is_paused:
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	else:
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)


func release_pointer() -> void:
	if not is_mobile():
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)


func capture_pointer() -> void:
	if not is_mobile() and mode == Mode.EXPLORE and not _is_paused:
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)


## Explicit pointer control for modal UI (gallery, settings, dialog windows).
## The mode-driven default is restored by _apply_pointer_mode on the next mode
## change, so a caller only has to say "visible for now".
func set_pointer_visible(value: bool) -> void:
	if is_mobile():
		return
	if value:
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	else:
		capture_pointer()


## True while a modal UI layer owns the pointer (gallery / settings / pause).
func is_modal_ui_open() -> bool:
	return _is_paused or not is_exploring()


## How long the current unpaused stretch has lasted; HorrorSystem uses it to
## decide when a room may be "wrong" without the player noticing.
func current_stretch() -> float:
	return time_since_pause
