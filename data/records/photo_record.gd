class_name PhotoRecord
extends RefCounted
## One photograph taken with the in-game camera.
##
## Images live in memory only (never written to disk), which is exactly what the
## brief allows and also makes the "the photograph changes" meta-horror beat
## trivial: replace the generated image in place.

var id: String = ""
var bug_id: String = ""
var unix_time: int = 0
var game_time: float = 0.0
var valid: bool = false
var subject_position: Vector2 = Vector2.ZERO
var source: String = "office"  ## "office" | "monitor"
var mutation_level: int = 0
var label: String = ""
var image: Image = null
var tex: ImageTexture = null
var chapter: int = 0


static func create(photo_id: String, bug: String, valid_flag: bool, source_kind: String) -> PhotoRecord:
	var rec := PhotoRecord.new()
	rec.id = photo_id
	rec.bug_id = bug
	rec.valid = valid_flag
	rec.source = source_kind
	rec.unix_time = int(Time.get_unix_time_from_system())
	rec.game_time = GameManager.total_playtime
	return rec


func make_texture() -> ImageTexture:
	if image == null:
		return null
	if tex == null or tex.get_width() != image.get_width():
		tex = ImageTexture.create_from_image(image)
	return tex


func time_string() -> String:
	var total := int(game_time)
	return "%02d:%02d:%02d" % [total / 3600, (total / 60) % 60, total % 60]


func to_evidence() -> PhotoEvidence:
	return PhotoEvidence.new(bug_id, unix_time, valid, "photo:%s" % id)


func to_dict() -> Dictionary:
	return {
		"id": id,
		"bug_id": bug_id,
		"unix_time": unix_time,
		"game_time": game_time,
		"valid": valid,
		"source": source,
		"mutation_level": mutation_level,
		"subject_position": [subject_position.x, subject_position.y],
		"chapter": chapter,
	}


static func from_dict(d: Dictionary) -> PhotoRecord:
	var rec := PhotoRecord.new()
	rec.id = str(d.get("id", ""))
	rec.bug_id = str(d.get("bug_id", ""))
	rec.unix_time = int(d.get("unix_time", 0))
	rec.game_time = float(d.get("game_time", 0.0))
	rec.valid = bool(d.get("valid", false))
	rec.source = str(d.get("source", "office"))
	rec.mutation_level = int(d.get("mutation_level", 0))
	rec.chapter = int(d.get("chapter", 0))
	var pos: Array = d.get("subject_position", [0.0, 0.0])
	if pos.size() == 2:
		rec.subject_position = Vector2(float(pos[0]), float(pos[1]))
	return rec
