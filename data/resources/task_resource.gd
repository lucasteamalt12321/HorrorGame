class_name TaskResource
extends Resource
## One assignment from the project manager. Drives the whole story chain.

enum State { LOCKED, ACTIVE, COMPLETED, FAILED }

enum Condition {
	REPORT_BUGS,        ## Report N bugs (optionally of given ids).
	REACH_LEVEL,        ## Reach level index N in the 2D game.
	WIN_LEVEL,          ## Complete level N.
	DIE_ON_LEVEL,       ## Die on level N at least once.
	ENTER_TEST_ROOM,    ## Discover the 2D copy of the office.
	STORY_FLAG,         ## Any story flag is set.
	PHOTOGRAPH_ANY,     ## Take N photographs.
	TALK_TO,            ## Read a document / object.
}

@export var id: String = ""
@export var title: String = ""
@export_multiline var description: String = ""
@export_multiline var brief: String = ""

@export var chapter: int = 1
@export var order: int = 0
@export var conditions: Array[Dictionary] = []
@export var required_bug_ids: PackedStringArray = PackedStringArray()
@export var target_level: int = -1
@export var target_amount: int = 0
@export var required_flag: StringName = &""

@export var next_task_id: String = ""
@export var grants_flag: PackedStringArray = PackedStringArray()
@export var reply_email_id: String = ""
@export var sets_tension: int = -1
@export var hint: String = ""

## Optional: auto-completing tasks are used for scripted beats.
@export var auto_complete: bool = false


func condition_kind() -> int:
	if conditions.is_empty():
		return -1
	return int(conditions[0].get("kind", -1))


func condition_amount() -> int:
	if conditions.is_empty():
		return 0
	return int(conditions[0].get("amount", 0))


func condition_id() -> String:
	if conditions.is_empty():
		return ""
	return String(conditions[0].get("id", ""))


func to_dict() -> Dictionary:
	return {
		"id": id,
		"state": int(State.LOCKED),
		"chapter": chapter,
		"completed": false,
	}
