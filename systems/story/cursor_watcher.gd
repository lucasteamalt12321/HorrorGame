extends Node
## CursorWatcher — the chapter 5 promise: once the game notices the player, the
## mouse stops belonging to the player.
##
## The beat is deliberately confined to the pause menu. Everywhere else the
## cursor is captured by the engine and warping it would either do nothing or
## fight the camera. In the menu the cursor is a real object the player looks at,
## so pulling it is both visible and harmless to progress.
##
## Rules: it never blocks input, it always returns the pointer to where the
## player left it when the menu closes, and it needs `cursor_followed` to have
## been set at least once by HorrorSystem.

## How far the pointer may be dragged, in pixels, from its real position.
@export var radius: float = 26.0
## Seconds the pull takes to reach full strength.
@export var pull_time: float = 2.5
## Seconds of grace after the menu opens before anything happens.
@export var grace: float = 1.5
## How often the pointer reappears under the cursor, so the menu stays usable.
@export var release_interval: float = 7.0

var _strength: float = 0.0
var _grace_left: float = 0.0
var _release_left: float = 0.0
var _anchor: Vector2 = Vector2.ZERO
var _has_anchor: bool = false
var _released: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func _process(delta: float) -> void:
	if not _menu_open():
		_release()
		return
	if not StoryFlags.has_flag(&"cursor_followed"):
		return

	if _grace_left > 0.0:
		_grace_left -= delta
		return

	if not _has_anchor:
		_anchor = get_viewport().get_mouse_position()
		_has_anchor = true

	_strength = minf(1.0, _strength + delta / maxf(0.1, pull_time))

	if _release_left > 0.0:
		_release_left -= delta
		if _release_left <= 0.0:
			_released = true
			_release_left = release_interval
	if _released:
		return

	# The pointer is pulled a little further every time the player moves it,
	# which is what makes it feel like something else is holding the mouse.
	var pos := get_viewport().get_mouse_position()
	var drift := pos - _anchor
	if drift.length() > 1.0:
		_anchor = pos
	var target := _anchor + Vector2(
		cos(_strength * 9.0) * radius * _strength,
		sin(_strength * 7.0) * radius * _strength * 0.6
	)
	var window := DisplayServer.window_get_size()
	var clamped := Vector2(
		clampf(target.x, 2.0, maxf(3.0, window.x - 3.0)),
		clampf(target.y, 2.0, maxf(3.0, window.y - 3.0))
	)
	Input.warp_mouse(clamped)


func _menu_open() -> bool:
	var menu := get_tree().get_first_node_in_group("pause_menu")
	return menu != null and menu.visible


func _release() -> void:
	if _has_anchor:
		# Hand the pointer back exactly where the menu was opened from, so
		# closing the menu never leaves the cursor somewhere unexpected.
		var window := DisplayServer.window_get_size()
		Input.warp_mouse(Vector2(
			clampf(_anchor.x, 2.0, maxf(3.0, window.x - 3.0)),
			clampf(_anchor.y, 2.0, maxf(3.0, window.y - 3.0))
		))
	_release_state()


func _release_state() -> void:
	_strength = 0.0
	_grace_left = 0.0
	_release_left = release_interval
	_released = false
	_has_anchor = false


## Called by the pause menu so the beat does not start while the player is
## still reaching for the Resume button.
func begin() -> void:
	_grace_left = grace
	_release_state()
	_has_anchor = true
	_anchor = get_viewport().get_mouse_position()
