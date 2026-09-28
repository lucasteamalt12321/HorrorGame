class_name BugResource
extends Resource
## Data-driven description of one bug inside the game under test.
##
## Never hardcode bug behaviour: a bug is a row in `data/bugs/*.tres` and the
## runtime behaviour is selected by `kind`.

enum Kind {
	NONE,
	NPC_THROUGH_WALL,      ## NPC ignores collision.
	FLOATING_PICKUP,       ## Collectible hangs in mid-air.
	BROKEN_PATROL,         ## Enemy patrols along the wrong axis / levitates.
	ANIMATION_LOOP,        ## Sprite animation stalls or replays a single frame.
	WRONG_SPAWN,           ## Object spawns in the wrong place.
	HIDDEN_PASSAGE,        ## Wall that is not solid.
	INVISIBLE_ENEMY,       ## Enemy present but never rendered.
	SCREEN_TEAR,           ## Rendering corruption bands.
	TEXT_MUTATION,         ## Level text rewrites itself.
	NPC_WATCHES,           ## NPC stops and looks at the "camera" (the player).
	SECRET_LEVEL,          ## A level that is not in the build list.
	TEST_ROOM,             ## 2D copy of the office.
	OFFICE_OBJECT_LEAK,    ## A 2D object appears in the 3D office.
	PHOTO_MUTATION,        ## Stored photo changes after being viewed.
	UNPHOTOGRAPHABLE,      ## Cannot be captured: only provable from the log.
	PLAYER_AVATAR,         ## The 2D game contains a copy of the tester.
	LTL_INSCRIPTION,       ## Writing that should not exist.
}

enum Category {
	PHYSICS,
	ANIMATION,
	AI,
	LEVEL_DESIGN,
	RENDERING,
	UI,
	MEMORY,
	SCRIPTING,
	UNKNOWN,
}

@export var id: String = ""
@export var title: String = ""
@export_multiline var description: String = ""
@export var category: Category = Category.UNKNOWN
@export_range(1, 5) var severity: int = 1
@export var kind: Kind = Kind.NONE

## Where in the game under test the bug lives: "L1", "L2", "TEST_ROOM", "OFFICE", "PHOTO"...
@export var location: String = ""
## Level index inside the 2D game (0-based). -1 = not level specific.
@export var level_index: int = -1
## Chapter gate: the bug may only be triggered from this chapter onwards.
@export var min_chapter: int = 0

## Conditions required for the bug to be active while playing.
@export var required_flags: PackedStringArray = PackedStringArray()
@export var requires_task_state: String = ""
@export var repeatable: bool = false
@export var auto_trigger_after_seconds: float = 0.0

@export var photo_required: bool = true
@export var report_required: bool = true
## Seconds the bug stays observable after activation (0 = until level exit).
@export var active_window: float = 0.0
## If > 0 the player must photograph within N seconds of activation.
@export var reaction_window: float = 0.0

## Optional hints shown in the bug tracker / task description.
@export_multiline var hint: String = ""
@export_multiline var observed_text: String = ""
## Developer reply shown after the report is accepted.
@export var reply_email_id: String = ""
## Story flag raised once the bug is reported.
@export var story_flag_on_report: StringName = &""
@export var tension_hint: int = 0


func severity_label() -> String:
	match severity:
		1: return "Trivial"
		2: return "Minor"
		3: return "Major"
		4: return "Critical"
		_: return "Blocker"


func category_label() -> String:
	return Category.keys()[category].capitalize()


func to_dict() -> Dictionary:
	return {
		"id": id,
		"title": title,
		"description": description,
		"category": int(category),
		"severity": severity,
		"kind": int(kind),
		"location": location,
		"level_index": level_index,
		"photo_required": photo_required,
		"report_required": report_required,
		"reply_email_id": reply_email_id,
		"story_flag_on_report": String(story_flag_on_report),
	}
