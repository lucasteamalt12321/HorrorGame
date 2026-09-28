class_name Interactable
extends Area3D
## Base class for everything the player can press E on.
##
## Subclasses override `get_prompt()` / `on_interact()`; they never touch the
## HUD or the input directly. Registration with InteractionSystem happens in
## `_ready`, so dropping the node in a scene is enough.

signal interact_performed(by: Node)

@export var prompt_text: String = "Взаимодействовать"
@export var prompt_key: String = "E"
@export var enabled: bool = true
@export var one_shot: bool = false
## When several objects overlap, the one with the highest priority wins.
## Named `focus_priority` because `Area3D` already owns a native `priority`.
@export var focus_priority: int = 0
@export var focus_radius: float = 0.0  ## 0 = use the system default.
@export var focus_angle_deg: float = 0.0
@export var show_prompt_always: bool = false
@export var group_hint: String = ""

var _used: bool = false
var _last_error: String = ""
var _router: Node = null


## The router is resolved through a runtime node lookup instead of a direct
## autoload reference: `InteractionSystem` type-hints `Interactable`, so a
## compile-time reference back to the autoload would create a dependency cycle
## and break member resolution on this class.
func _router_node() -> Node:
	if _router == null or not is_instance_valid(_router):
		_router = get_node_or_null("/root/InteractionSystem")
	return _router


func _ready() -> void:
	add_to_group("interactable")
	monitoring = false
	monitorable = false
	var router := _router_node()
	if router != null and router.has_method("register"):
		router.register(self)


func _exit_tree() -> void:
	var router := _router_node()
	if router != null and router.has_method("unregister"):
		router.unregister(self)


# --- overridable ------------------------------------------------------------

func get_prompt() -> String:
	return prompt_text


func can_interact(_by: Node) -> bool:
	if not enabled:
		return false
	if one_shot and _used:
		return false
	return true


## Returns true when the interaction was actually consumed.
func on_interact(by: Node) -> bool:
	interact_performed.emit(by)
	if one_shot:
		_used = true
	return true


# --- helpers ----------------------------------------------------------------

func get_interaction_range() -> float:
	if focus_radius > 0.0:
		return focus_radius
	var router := _router_node()
	if router != null:
		var value: Variant = router.get("default_range")
		if value != null:
			return float(value)
	return 2.6


func get_interaction_angle() -> float:
	if focus_angle_deg > 0.0:
		return deg_to_rad(focus_angle_deg)
	var router := _router_node()
	if router != null:
		var value: Variant = router.get("default_angle")
		if value != null:
			return float(value)
	return deg_to_rad(38.0)


func is_used() -> bool:
	return _used


func set_enabled(value: bool) -> void:
	enabled = value


func mark_used() -> void:
	_used = true


func push_error_message(msg: String) -> void:
	_last_error = msg
