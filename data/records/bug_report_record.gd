class_name BugReportRecord
extends RefCounted
## A filed bug report. Created only through ReportSystem.

var bug_id: String = ""
var title: String = ""
var category: String = ""
var severity: int = 1
var author_comment: String = ""
var photo_ids: PackedStringArray = PackedStringArray()
var submitted_at_unix: int = 0
var submitted_at_game_time: float = 0.0
var accepted: bool = false
var reply_shown: bool = false
var chapter: int = 0
var task_id: String = ""
var mutated: bool = false


static func create(bug: BugResource) -> BugReportRecord:
	var rec := BugReportRecord.new()
	rec.bug_id = bug.id
	rec.title = bug.title
	rec.category = bug.category_label()
	rec.severity = bug.severity
	rec.submitted_at_unix = int(Time.get_unix_time_from_system())
	rec.submitted_at_game_time = GameManager.total_playtime
	return rec


func to_dict() -> Dictionary:
	return {
		"bug_id": bug_id,
		"title": title,
		"category": category,
		"severity": severity,
		"author_comment": author_comment,
		"photo_ids": Array(photo_ids),
		"submitted_at_unix": submitted_at_unix,
		"submitted_at_game_time": submitted_at_game_time,
		"accepted": accepted,
		"reply_shown": reply_shown,
		"chapter": chapter,
		"task_id": task_id,
		"mutated": mutated,
	}


static func from_dict(d: Dictionary) -> BugReportRecord:
	var rec := BugReportRecord.new()
	rec.bug_id = str(d.get("bug_id", ""))
	rec.title = str(d.get("title", ""))
	rec.category = str(d.get("category", ""))
	rec.severity = int(d.get("severity", 1))
	rec.author_comment = str(d.get("author_comment", ""))
	var photos: Array = d.get("photo_ids", [])
	for p: Variant in photos:
		rec.photo_ids.append(str(p))
	rec.submitted_at_unix = int(d.get("submitted_at_unix", 0))
	rec.submitted_at_game_time = float(d.get("submitted_at_game_time", 0.0))
	rec.accepted = bool(d.get("accepted", false))
	rec.reply_shown = bool(d.get("reply_shown", false))
	rec.chapter = int(d.get("chapter", 0))
	rec.task_id = str(d.get("task_id", ""))
	rec.mutated = bool(d.get("mutated", false))
	return rec
