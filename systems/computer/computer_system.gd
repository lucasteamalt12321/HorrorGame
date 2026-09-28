extends Node
## ComputerSystem — entering the machine, launching applications, leaving.
##
## Owns: the COMPUTER/MINIGAME mode transitions, which application window is
## open, and the reference to the monitor's SubViewport.
## Does NOT own: the desktop UI drawing (ui/computer/*), the 2D game rules
## (MinigameSystem), the player's body (player.gd).

signal entered(computer: Node3D)
signal enter_requested(computer: Node3D)
signal exited()
signal app_opened(app_id: String)
signal app_closed(app_id: String)
signal app_changed(app_id: String)

enum App { DESKTOP, BUGTRACKER, MAIL, NOTES, FILES, SETTINGS, GAME }

const APP_IDS := {
	App.DESKTOP: "desktop",
	App.BUGTRACKER: "bugtracker",
	App.MAIL: "mail",
	App.NOTES: "notes",
	App.FILES: "files",
	App.SETTINGS: "settings",
	App.GAME: "game",
}

@export var boot_time: float = 1.6
@export var auto_pickup: bool = false

var computer: Node3D = null
var current_app: int = App.DESKTOP
var app_stack: Array[int] = []
var is_active: bool = false
var _boot_remaining: float = 0.0
var _unread_count: int = 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	GameManager.mode_changed.connect(_on_mode_changed)
	DialogueSystem.unread_changed.connect(func(n: int) -> void: _unread_count = n)


# --- entering / leaving -----------------------------------------------------

func enter(target: Node3D) -> bool:
	if is_active or target == null:
		return false
	computer = target
	is_active = true
	app_stack.clear()
	current_app = App.DESKTOP
	GameManager.set_mode(GameManager.Mode.COMPUTER)
	enter_requested.emit(target)
	_boot_remaining = maxf(0.0, boot_time)
	if _boot_remaining > 0.0:
		AudioManager.play_computer("boot")
	entered.emit(target)
	app_changed.emit(APP_IDS[App.DESKTOP])
	return true


func exit() -> void:
	if not is_active:
		return
	is_active = false
	_boot_remaining = 0.0
	MinigameSystem.force_stop("computer_exit")
	app_stack.clear()
	current_app = App.DESKTOP
	computer = null
	GameManager.set_mode(GameManager.Mode.EXPLORE)
	AudioManager.play_ui("close")
	exited.emit()


func _on_mode_changed(new_mode: int, _old: int) -> void:
	if new_mode == GameManager.Mode.EXPLORE and is_active:
		is_active = false
		exited.emit()


func _process(delta: float) -> void:
	if _boot_remaining > 0.0:
		_boot_remaining = maxf(0.0, _boot_remaining - delta)
		if _boot_remaining <= 0.0:
			_boot_remaining = 0.0
			AudioManager.play_computer("confirm")


func is_booting() -> bool:
	return _boot_remaining > 0.0


# --- applications -----------------------------------------------------------

func open_app(app: int) -> void:
	if not is_active or is_booting():
		return
	if app == current_app:
		return
	if app == App.GAME:
		MinigameSystem.launch_from_desktop()
		if not MinigameSystem.is_game_running():
			AudioManager.play_computer("error")
			return
	stack_push(app)
	app_opened.emit(APP_IDS[app])
	AudioManager.play_ui("open")


func close_app() -> void:
	if app_stack.is_empty():
		exit()
		return
	stack_pop()
	AudioManager.play_ui("close")


## Esc inside the computer: pop one application window, and leave the machine
## entirely when the desktop itself is what is showing. Keeps a single rule for
## "back" no matter which screen the player is on.
func close_top() -> void:
	if not is_active or is_booting():
		return
	if current_app == App.GAME and MinigameSystem.is_game_running():
		MinigameSystem.force_stop("player_exit")
		return
	if current_app == App.DESKTOP:
		exit()
		return
	close_app()


func stack_push(app: int) -> void:
	if current_app != app:
		app_stack.append(current_app)
	current_app = app
	app_changed.emit(APP_IDS[app])


func stack_pop() -> void:
	if app_stack.is_empty():
		current_app = App.DESKTOP
	else:
		current_app = app_stack.pop_back()
	app_closed.emit(APP_IDS[current_app])
	app_changed.emit(APP_IDS[current_app])


func current_app_id() -> String:
	return String(APP_IDS.get(current_app, "desktop"))


func unread_mail() -> int:
	return _unread_count


# --- monitor ----------------------------------------------------------------

func get_monitor() -> Node3D:
	if computer == null or not is_instance_valid(computer):
		return null
	if computer.has_method("get_monitor_node"):
		return computer.call("get_monitor_node")
	return null


func get_screen_viewport() -> SubViewport:
	var mon := get_monitor()
	if mon == null:
		return null
	return mon.get_node_or_null("ScreenViewport") as SubViewport


func get_desktop_root() -> Control:
	return get_tree().get_first_node_in_group("computer_desktop") as Control
