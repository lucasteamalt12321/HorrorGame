extends Node
## InteractionSystem — the single interaction router.
##
## Chooses the best `Interactable` for the current viewpoint, drives the HUD
## prompt and dispatches the E key. There is exactly ONE implementation of this
## in the project (rule 4): computers, doors, documents, switches all derive
## from `Interactable`.

signal focus_changed(target: Interactable, prompt: String)
signal focus_cleared()
signal interaction_performed(target: Interactable)

@export var default_range: float = 2.6
@export var default_angle: float = deg_to_rad(38.0)
@export var scan_interval: float = 0.06
@export var show_debug: bool = false

var _registry: Array[Interactable] = []
var _current: Interactable = null
var _timer: float = 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func register(node: Interactable) -> void:
	if node != null and not _registry.has(node):
		_registry.append(node)
		_prune()


func unregister(node: Interactable) -> void:
	_registry.erase(node)
	if _current == node:
		_set_current(null)


func clear() -> void:
	_registry.clear()
	_set_current(null)


func _prune() -> void:
	for i in range(_registry.size() - 1, -1, -1):
		if not is_instance_valid(_registry[i]):
			_registry.remove_at(i)


func _process(delta: float) -> void:
	_timer -= delta
	if _timer <= 0.0:
		_timer = scan_interval
		_update_focus()


func _update_focus() -> void:
	if not GameManager.is_exploring():
		if _current != null:
			_set_current(null)
		return
	var cam := _viewpoint()
	if cam == null:
		_set_current(null)
		return
	var best: Interactable = null
	var best_score := -INF
	var forward := -cam.global_transform.basis.z
	var origin := cam.global_position

	for it: Interactable in _registry:
		if not is_instance_valid(it):
			continue
		if not it.enabled:
			continue
		var pos := _focus_point(it)
		var to := pos - origin
		var dist := to.length()
		if dist > it.get_interaction_range():
			continue
		if dist > 0.0001:
			var dir := to / dist
			var angle := acos(clampf(dir.dot(forward), -1.0, 1.0))
			if angle > it.get_interaction_angle():
				continue
		var score := (1.0 - dist / maxf(it.get_interaction_range(), 0.001)) * 10.0 + float(it.focus_priority)
		if score > best_score:
			best_score = score
			best = it
	_set_current(best)


func _focus_point(it: Interactable) -> Vector3:
	if it.has_method("get_focus_point"):
		return it.call("get_focus_point")
	return it.global_position


func _viewpoint() -> Camera3D:
	var player := GameManager.get_player()
	if player != null:
		var cam := player.get_node_or_null("Head/Camera3D") as Camera3D
		if cam != null:
			return cam
	return get_viewport().get_camera_3d()


func _set_current(target: Interactable) -> void:
	if target == _current:
		return
	_current = target
	if _current == null:
		focus_cleared.emit()
		focus_changed.emit(null, "")
	else:
		focus_changed.emit(_current, _current.get_prompt())


func get_current() -> Interactable:
	return _current


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("interact"):
		return
	if not GameManager.is_exploring():
		return
	if _current == null:
		return
	perform(_current)


## Public entry point so UI buttons (mobile) can trigger the same path.
func perform(target: Interactable) -> bool:
	if target == null or not is_instance_valid(target):
		return false
	if not target.can_interact(GameManager.get_player()):
		return false
	var consumed := target.on_interact(GameManager.get_player())
	if consumed:
		interaction_performed.emit(target)
		AudioManager.play_ui("click")
		_update_focus()
	return consumed


func count() -> int:
	_prune()
	return _registry.size()
