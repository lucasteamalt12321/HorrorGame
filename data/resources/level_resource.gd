class_name LevelResource
extends Resource
## Data description of a level of the game under test.

@export var id: String = ""
@export var display_name: String = ""
@export var scene_path: String = ""
@export var width_tiles: int = 64
@export var height_tiles: int = 18
@export var kill_plane_y: float = -6.0
@export var spawn: Vector2 = Vector2(3, 12)
@export var goal_x: float = 60.0
## Bugs that can be activated here (ids from data/bugs).
@export var bug_ids: PackedStringArray = PackedStringArray()
## Number of in-level collectibles ("data shards") used for the completion %.
@export var collectible_total: int = 5
@export var is_secret: bool = false
@export var chapter_min: int = 0
@export_multiline var build_note: String = ""

## --- geometry (data-driven, no hand-placed nodes) ---
## x/y/width/height in tiles, y grows downward.
@export var platforms: Array[Rect2] = []
@export var enemy_kinds: PackedStringArray = PackedStringArray()
@export var enemy_positions: PackedVector2Array = PackedVector2Array()
## Patrol half-range in tiles, per enemy (0 = standing still).
@export var enemy_ranges: PackedFloat32Array = PackedFloat32Array()
@export var pickup_positions: PackedVector2Array = PackedVector2Array()
## Rect2 zones that activate the matching bug id when the player enters.
@export var bug_trigger_zones: Array[Rect2] = []
@export var bug_trigger_ids: PackedStringArray = PackedStringArray()
## Where a 2D "leak" object appears inside the level (office analogue).
@export var leak_marker: Vector2 = Vector2.ZERO


func zone_bug_id(zone_index: int) -> String:
	if zone_index < 0 or zone_index >= bug_trigger_ids.size():
		return ""
	return bug_trigger_ids[zone_index]


func to_dict() -> Dictionary:
	return {
		"id": id,
		"display_name": display_name,
		"width_tiles": width_tiles,
		"height_tiles": height_tiles,
		"bug_ids": Array(bug_ids),
		"collectible_total": collectible_total,
		"is_secret": is_secret,
	}
