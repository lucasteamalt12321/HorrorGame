class_name CanonRegistry
extends RefCounted
## Read-only registry of external-canon references.
##
## RULE 11: the project has no verified canon source. Every entry therefore
## records HOW a term surfaces in-game and which statements are still open
## questions. Nothing here asserts a fact about the wider universe; the game
## only uses the terms as ambiguous strings the tester can notice.

const CANON_DIR := "res://data/canon"

static var _cache: Array[CanonEntryResource] = []
static var _loaded: bool = false
static var _seen_terms: Dictionary = {}


static func entries() -> Array[CanonEntryResource]:
	if not _loaded:
		_load()
	return _cache


static func _load() -> void:
	_cache.clear()
	_loaded = true
	var dir := DirAccess.open(CANON_DIR)
	if dir == null:
		return
	for f: String in dir.get_files():
		if not f.ends_with(".tres"):
			continue
		var res := load(CANON_DIR.path_join(f))
		if res is CanonEntryResource and (res as CanonEntryResource).term != "":
			_cache.append(res)
	_cache.sort_custom(func(a: CanonEntryResource, b: CanonEntryResource) -> bool:
		return a.term < b.term)


static func get_entry(term: String) -> CanonEntryResource:
	for e in entries():
		if e.term.to_lower() == term.to_lower():
			return e
	return null


static func known_terms() -> PackedStringArray:
	var out := PackedStringArray()
	for e in entries():
		out.append(e.term)
	return out


## Renders the in-game glossary. Unverified entries are shown as such on
## purpose: the tester is supposed to distrust their own notes.
static func render_markdown() -> String:
	var out := "ГЛОССАРИЙ СБОРКИ (автоматически собран из строк сборки)\n\n"
	if entries().is_empty():
		return out + "Записей нет."
	for e in entries():
		var status := "ПОДТВЕРЖДЕНО"
		if not e.is_safe():
			match e.status:
				CanonEntryResource.Status.TODO:
					status = "НЕ ПОДТВЕРЖДЕНО"
				CanonEntryResource.Status.AMBIGUOUS:
					status = "ТРАКТОВКА НЕЯСНА"
		out += "[b]%s[/b] — %s\n" % [e.term, status]
		out += "  Где встречается: %s\n" % _join(e.surfaces_in)
		if e.is_safe():
			for f: String in e.safe_facts:
				out += "  • %s\n" % f
		if not e.open_questions.is_empty():
			out += "  Вопросы:\n"
			for q: String in e.open_questions:
				out += "    - %s\n" % q
		out += "\n"
	return out


## Checks rule 11 for every entry and returns one message per violation.
##
## The rule exists because `safe_facts` is what the glossary prints to the
## player as a fact: a TODO entry that still carries safe_facts turns a guess
## into a statement the game makes out loud. Nothing else validates this, so
## the smoke test calls it.
static func validate() -> PackedStringArray:
	var problems := PackedStringArray()
	for e in entries():
		if e.term.strip_edges().is_empty():
			problems.append("запись без термина")
			continue
		if e.status == CanonEntryResource.Status.TODO and not e.safe_facts.is_empty():
			problems.append("%s: status TODO, но safe_facts не пуст (%d шт.) — глоссарий напечатает их как факты"
				% [e.term, e.safe_facts.size()])
		if e.is_safe() and e.safe_facts.is_empty():
			problems.append("%s: status SAFE, но safe_facts пуст" % e.term)
		if e.status == CanonEntryResource.Status.AMBIGUOUS and e.safe_facts.is_empty():
			problems.append("%s: status AMBIGUOUS, но safe_facts пуст — трактовку нечего предъявить"
				% e.term)
		for s: String in e.surfaces_in:
			if s.strip_edges().is_empty():
				problems.append("%s: пустая поверхность в surfaces_in" % e.term)
		for q: String in e.open_questions:
			if q.strip_edges().is_empty():
				problems.append("%s: пустой вопрос в open_questions" % e.term)
	return problems


## Called when the player actually notices a term. Returns true only the first
## time a given term is seen. The first observation of any term raises the
## story flag, so the narrative can react without hardcoding string checks.
static func mark_seen(term: String) -> bool:
	var e := get_entry(term)
	if e == null:
		return false
	if _seen_terms.has(term.to_lower()):
		return false
	_seen_terms[term.to_lower()] = true
	if not StoryFlags.has_flag(&"canon_term_seen"):
		StoryFlags.set_flag(&"canon_term_seen", true)
	return true


## Marks every term the tester has just been shown. Returns the terms that were
## noticed for the first time so the caller can react to the discovery.
static func mark_all_seen() -> PackedStringArray:
	var fresh: PackedStringArray = PackedStringArray()
	for e in entries():
		if mark_seen(e.term):
			fresh.append(e.term)
	return fresh


static func _join(values: PackedStringArray) -> String:
	if values.is_empty():
		return "—"
	var parts: PackedStringArray = PackedStringArray()
	for v in values:
		parts.append(v)
	return ", ".join(parts)
