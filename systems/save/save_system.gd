extends Node
## SaveSystem — versioned, migration-tolerant persistence.
##
## Systems do not write files themselves: they register as providers and expose
## `get_save_state() -> Dictionary` / `apply_save_state(Dictionary) -> void`.
## This keeps data ownership clear and makes the format versioned in one place.

signal saved(slot: int)
signal loaded(slot: int)
signal save_failed(slot: int, reason: String)

const SCHEMA_VERSION := 3
const SLOT_COUNT := 3
const AUTOSAVE_SLOT := 0
const SAVE_DIR := "user://saves"

const PROVIDER_IDS := [
	"story", "bugs", "tasks", "reports", "photos", "minigame", "horror", "office",
	"dialogue",
]

var _providers: Dictionary = {}
var current_slot: int = AUTOSAVE_SLOT
var last_error: String = ""


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	DirAccess.make_dir_recursive_absolute(SAVE_DIR)


func register(provider_id: StringName, provider: Object) -> void:
	if provider == null:
		push_warning("SaveSystem: null provider '%s'" % provider_id)
		return
	if not provider.has_method("get_save_state"):
		push_warning("SaveSystem: provider '%s' has no get_save_state()" % provider_id)
		return
	_providers[String(provider_id)] = provider


func unregister(provider_id: StringName) -> void:
	_providers.erase(String(provider_id))


func has_slot(slot: int) -> bool:
	return FileAccess.file_exists(slot_path(slot))


func slot_path(slot: int) -> String:
	return "%s/slot_%d.json" % [SAVE_DIR, slot]


func build_payload() -> Dictionary:
	var payload := {
		"schema_version": SCHEMA_VERSION,
		"saved_at_unix": int(Time.get_unix_time_from_system()),
		"saved_at_msec": Time.get_ticks_msec(),
		"playtime": GameManager.total_playtime if has_node("/root/GameManager") else 0.0,
		"game_mode": int(GameManager.mode) if has_node("/root/GameManager") else 0,
		"pause_count": GameManager.pause_count if has_node("/root/GameManager") else 0,
		"build": ProjectSettings.get_setting("application/config/version", "dev"),
		"providers": {},
		"flags": StoryFlags.to_dict() if has_node("/root/StoryFlags") else {},
	}
	for id: StringName in PROVIDER_IDS:
		var provider: Object = _providers.get(String(id))
		if provider != null and provider.has_method("get_save_state"):
			payload["providers"][String(id)] = provider.call("get_save_state")
		elif provider != null and provider.has_method("get_save_data"):
			# Backwards-compatible hook name.
			payload["providers"][String(id)] = provider.call("get_save_data")
	return payload


func save_game(slot: int = AUTOSAVE_SLOT) -> bool:
	var payload := build_payload()
	var file := FileAccess.open(slot_path(slot), FileAccess.WRITE)
	if file == null:
		last_error = "cannot open %s (%d)" % [slot_path(slot), FileAccess.get_open_error()]
		push_warning("SaveSystem: " + last_error)
		save_failed.emit(slot, last_error)
		return false
	file.store_string(JSON.stringify(payload, "\t"))
	file.close()
	current_slot = slot
	saved.emit(slot)
	return true


func load_game(slot: int = AUTOSAVE_SLOT) -> bool:
	var path := slot_path(slot)
	if not FileAccess.file_exists(path):
		last_error = "slot %d is empty" % slot
		save_failed.emit(slot, last_error)
		return false
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		last_error = "cannot read slot %d" % slot
		save_failed.emit(slot, last_error)
		return false
	var text := file.get_as_text()
	file.close()

	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		last_error = "corrupted save (not a JSON object)"
		push_warning("SaveSystem: " + last_error)
		save_failed.emit(slot, last_error)
		return false

	var data: Dictionary = parsed
	data = migrate(data)
	apply_payload(data)
	current_slot = slot
	loaded.emit(slot)
	return true


func apply_payload(data: Dictionary) -> void:
	if data.has("flags") and typeof(data["flags"]) == TYPE_DICTIONARY:
		StoryFlags.load_dict(data["flags"])

	var providers: Dictionary = data.get("providers", {})
	for id: StringName in PROVIDER_IDS:
		var provider: Object = _providers.get(String(id))
		if provider == null:
			continue
		var state: Variant = providers.get(String(id))
		if typeof(state) != TYPE_DICTIONARY:
			continue
		if provider.has_method("apply_save_state"):
			provider.call("apply_save_state", state)
		elif provider.has_method("apply_save_data"):
			provider.call("apply_save_data", state)

	# Session counters: v3 renamed "total_playtime" to "playtime", so read both.
	if data.has("playtime") or data.has("total_playtime"):
		GameManager.total_playtime = float(data.get("playtime", data.get("total_playtime", 0.0)))
	if data.has("pause_count"):
		GameManager.pause_count = int(data.get("pause_count", 0))


func delete_slot(slot: int) -> void:
	if has_slot(slot):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(slot_path(slot)))
		saved.emit(slot)


## Versioned migration. Every older schema maps forward here and nowhere else.
func migrate(data: Dictionary) -> Dictionary:
	var version := int(data.get("schema_version", 1))
	if version < 1:
		version = 1

	if version == 1:
		# v1 stored a flat "found_bugs" array instead of the bugs provider.
		var providers: Dictionary = data.get("providers", {})
		if providers.is_empty() and data.has("found_bugs"):
			providers["bugs"] = {
				"discovered": data.get("found_bugs", []),
				"reported": data.get("reported_bugs", []),
				"mutated": [],
			}
			data["providers"] = providers
		data["schema_version"] = 2
		version = 2

	if version == 2:
		# v2 had no horror provider and no mutation tracking.
		var providers: Dictionary = data.get("providers", {})
		if not providers.has("horror"):
			providers["horror"] = {"tension": 0, "fired_events": [], "screamer_budget": 3}
			data["providers"] = providers
		data["schema_version"] = 3
		version = 3

	data["schema_version"] = SCHEMA_VERSION
	return data


func export_payload_string() -> String:
	return JSON.stringify(build_payload(), "\t")


func import_payload_string(text: String) -> bool:
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		return false
	apply_payload(migrate(parsed))
	return true
