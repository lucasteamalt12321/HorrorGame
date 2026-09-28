class_name PhotoEvidence
extends RefCounted
## Lightweight proof-of-capture record handed to BugSystem.
## Mirrors the brief's format: bug_id, timestamp, valid, image/reference.

var bug_id: String = ""
var timestamp: int = 0
var valid: bool = false
var image_ref: String = ""


func _init(p_bug_id: String = "", p_timestamp: int = 0, p_valid: bool = false, p_image_ref: String = "") -> void:
	bug_id = p_bug_id
	timestamp = p_timestamp
	valid = p_valid
	image_ref = p_image_ref


func _to_string() -> String:
	return "PhotoEvidence(%s, t=%d, valid=%s, ref=%s)" % [bug_id, timestamp, str(valid), image_ref]
