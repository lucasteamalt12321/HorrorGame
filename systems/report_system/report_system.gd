extends Node
## ReportSystem — the bug tracker / report composer.
##
## A report can only be filed for a bug that is known, and (when the bug demands
## it) already photographed. Submitting is idempotent: re-submitting the same bug
## never duplicates progress, it just re-opens the thread.

signal report_opened(bug_id: String)
signal report_submitted(record: BugReportRecord)
signal report_accepted(bug_id: String)
signal report_rejected(bug_id: String, reason: String)
signal report_mutated(bug_id: String)
signal tracker_changed()

const REJECT_NO_EVIDENCE := "Требуется фотография-доказательство."
const REJECT_UNKNOWN := "Баг не подтверждён наблюдениями."

var _reports: Dictionary = {}   ## bug_id -> BugReportRecord


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	SaveSystem.register(&"reports", self)


# --- tracker ----------------------------------------------------------------

func build_tracker() -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	for bug in BugSystem.all_bugs():
		if not BugSystem.is_known(bug.id):
			continue
		rows.append({
			"id": bug.id,
			"title": bug.title,
			"status": BugSystem.get_status(bug.id),
			"severity": bug.severity,
			"severity_label": bug.severity_label(),
			"category": bug.category_label(),
			"location": bug.location,
			"photo_required": bug.photo_required,
			"photo_valid": BugSystem.is_photo_valid(bug.id),
			"photo_ids": Array(BugSystem.photo_ids_for(bug.id)),
			"report_required": bug.report_required,
			"reported": BugSystem.is_reported(bug.id),
			"description": bug.description,
			"hint": bug.hint,
		})
	return rows


func get_reportable_bug_ids() -> PackedStringArray:
	var out := PackedStringArray()
	for bug in BugSystem.all_bugs():
		if BugSystem.is_known(bug.id) and BugSystem.is_report_needed(bug.id):
			out.append(bug.id)
	return out


func can_submit(bug_id: String) -> bool:
	return BugSystem.is_report_needed(bug_id) and BugSystem.is_known(bug_id)


# --- attaching evidence from the photo gallery ------------------------------

## Binds a photo to a bug before the report is filed. The photo itself must
## already be a valid capture for that bug, otherwise the tracker refuses the
## binding — this keeps the gallery honest.
func attach_photo(photo_id: String, bug_id: String) -> bool:
	if photo_id == "" or bug_id == "":
		return false
	if not BugSystem.is_known(bug_id):
		report_rejected.emit(bug_id, REJECT_UNKNOWN)
		return false
	if not BugSystem.is_photo_valid(bug_id):
		report_rejected.emit(bug_id, REJECT_NO_EVIDENCE)
		AudioManager.play_computer("error")
		return false
	var rec := get_report(bug_id)
	if rec == null:
		rec = BugReportRecord.create(BugSystem.get_bug(bug_id))
		rec.accepted = false
		_reports[bug_id] = rec
	if not rec.photo_ids.has(photo_id):
		rec.photo_ids.append(photo_id)
		rec.photo_ids.sort()
	tracker_changed.emit()
	return true


func has_photo(photo_id: String) -> bool:
	for rec in _reports.values():
		if (rec as BugReportRecord).photo_ids.has(photo_id):
			return true
	return false


## Photo ids currently bound to a bug's report, for the tracker detail view.
func attached_photos(bug_id: String) -> PackedStringArray:
	var rec := get_report(bug_id)
	return rec.photo_ids if rec != null else PackedStringArray()


func submit(bug_id: String, comment: String = "", task_id: String = "") -> BugReportRecord:
	var bug := BugSystem.get_bug(bug_id)
	if bug == null:
		push_warning("ReportSystem.submit: unknown bug '%s'" % bug_id)
		return null
	if not BugSystem.is_known(bug_id):
		report_rejected.emit(bug_id, REJECT_UNKNOWN)
		return null
	if bug.photo_required and not BugSystem.is_photo_valid(bug_id):
		report_rejected.emit(bug_id, REJECT_NO_EVIDENCE)
		AudioManager.play_computer("error")
		return null
	if BugSystem.is_reported(bug_id):
		# Idempotent: re-submission returns the existing record, and the thread
		# counts as opened again so anything watching the tracker can react.
		var existing: BugReportRecord = _reports.get(bug_id, null)
		report_opened.emit(bug_id)
		tracker_changed.emit()
		return existing

	var rec := BugReportRecord.create(bug)
	rec.author_comment = comment
	rec.photo_ids = BugSystem.photo_ids_for(bug_id)
	rec.chapter = StorySystem.get_chapter() if has_node("/root/StorySystem") else 0
	rec.task_id = task_id if task_id != "" else TaskSystem.get_current_task_id()
	rec.accepted = true
	_reports[bug_id] = rec

	BugSystem.mark_reported(bug_id)
	TaskSystem.notify_bug_reported(bug_id, task_id)
	report_submitted.emit(rec)
	report_accepted.emit(bug_id)
	tracker_changed.emit()
	AudioManager.play_computer("confirm")
	return rec


func get_report(bug_id: String) -> BugReportRecord:
	return _reports.get(bug_id, null)


func all_reports() -> Array[BugReportRecord]:
	var out: Array[BugReportRecord] = []
	for k: String in _reports.keys():
		out.append(_reports[k])
	out.sort_custom(func(a: BugReportRecord, b: BugReportRecord) -> bool:
		return a.submitted_at_unix < b.submitted_at_unix)
	return out


func reported_count() -> int:
	return _reports.size()


# --- meta-horror: the report file rewrites itself ---------------------------

func mutate_report(bug_id: String) -> bool:
	var rec := get_report(bug_id)
	if rec == null or rec.mutated:
		return false
	rec.mutated = true
	report_mutated.emit(bug_id)
	tracker_changed.emit()
	StoryFlags.set_flag(&"report_file_mutated", true)
	return true


func report_body(bug_id: String) -> String:
	var rec := get_report(bug_id)
	var bug := BugSystem.get_bug(bug_id)
	if bug == null:
		return ""
	var body := "%s\n\n%s\n\nКатегория: %s\nСерьёзность: %s (%d)\nЛокация: %s\n" % [
		bug.title, bug.description, bug.category_label(), bug.severity_label(), bug.severity, bug.location
	]
	if rec != null and rec.author_comment.strip_edges() != "":
		body += "\nКомментарий тестировщика: %s\n" % rec.author_comment.strip_edges()
	if rec != null and rec.mutated:
		body += "\n[ Файл отчёта изменён. Автор: неизвестно. Дата: сегодня. ]\n"
		body += "[ В теле отчёта теперь %d строк вместо %d. ]\n" % [999, 12]
	return body


# --- persistence ------------------------------------------------------------

func get_save_state() -> Dictionary:
	var out := {}
	for k: String in _reports.keys():
		out[k] = _reports[k].to_dict()
	return {"reports": out}


func apply_save_state(data: Dictionary) -> void:
	_reports.clear()
	for k: String in data.get("reports", {}).keys():
		var d: Variant = data.get("reports", {})[k]
		if typeof(d) == TYPE_DICTIONARY:
			_reports[k] = BugReportRecord.from_dict(d)
	tracker_changed.emit()
