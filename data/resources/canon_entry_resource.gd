class_name CanonEntryResource
extends Resource
## Registry of external-canon references.
##
## IMPORTANT (rule 11 of the brief): the project has no verified canon source
## yet. Entries therefore only record HOW a term is used inside this game, not
## WHAT it means in the wider universe. `status = "TODO"` marks every claim that
## still needs confirmation. Never assert a fact that is not in `safe_facts`.

enum Status { TODO, SAFE, AMBIGUOUS }

@export var term: String = ""
@export var status: Status = Status.TODO
## How the term surfaces in-game (emails, files, wall writings, build strings).
@export var surfaces_in: PackedStringArray = PackedStringArray()
## Facts that are safe to state. Empty for TODO entries.
@export var safe_facts: PackedStringArray = PackedStringArray()
## Open questions. Kept explicit instead of invented.
@export var open_questions: PackedStringArray = PackedStringArray()
@export_multiline var source_note: String = ""


func is_safe() -> bool:
	return status == Status.SAFE
