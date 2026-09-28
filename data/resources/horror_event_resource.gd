class_name HorrorEventResource
extends Resource
## One scripted horror beat. Events never roll dice to decide story-critical
## outcomes: they are queued by StorySystem / HorrorSystem by id.

enum Kind {
	LIGHT_FLICKER,
	AUDIO_STING,
	OBJECT_DISAPPEAR,
	OBJECT_APPEAR,
	OBJECT_JUMP,
	TEXT_MUTATION,
	NPC_BEHAVIOR,
	GAME_2D_LEAK,
	OFFSCREEN_EVENT,
	SCREAMER,
	PAUSE_ANOMALY,
	CAMERA_MUTATION,
	REPORT_MUTATION,
	SECRET_LEVEL,
	OFFICE_REWRITE,
}

enum Target {
	OFFICE_LIGHT,
	OFFICE_PROP,
	OFFICE_WINDOW,
	COMPUTER,
	MONITOR,
	PHOTO_GALLERY,
	REPORT_FILE,
	MINIGAME,
	PLAYER_CAMERA,
	PAUSE_MENU,
}

@export var id: String = ""
@export var kind: Kind = Kind.AUDIO_STING
@export var target: Target = Target.OFFICE_LIGHT
@export var title: String = ""

## Minimum / maximum tension for the event to be allowed to fire.
@export_range(0, 5) var min_tension: int = 0
@export_range(0, 5) var max_tension: int = 5
## Typical delay after being queued.
@export var delay: float = 0.0
@export var duration: float = 1.0
## Cooldown before the same event can fire again.
@export var cooldown: float = 60.0
@export_range(0.0, 1.0) var chance: float = 1.0
## Screamers consume a limited budget so they stay rare.
@export var is_screamer: bool = false
@export var consumes_budget: bool = true

@export var audio_key: String = "sting"
@export var audio_volume_db: float = -8.0
@export var prop_id: String = ""
@export var text_id: String = ""
@export var subtitle: String = ""
@export var required_flag: StringName = &""
@export var sets_flag: StringName = &""
@export var sets_tension: int = -1
@export var one_shot: bool = true
## Which systems must be idle for the event to run safely.
@export var requires_mode: int = 0
@export var min_ignore_repeats: int = 0
