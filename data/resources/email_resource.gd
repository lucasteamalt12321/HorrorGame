class_name EmailResource
extends Resource
## A message inside the in-game mail client: from the manager, from the
## developers, or — later — from something that should not be able to write.

enum Kind { MANAGER, DEVELOPER, SYSTEM, UNKNOWN_SENDER }

@export var id: String = ""
@export var kind: Kind = Kind.MANAGER
@export var sender_name: String = ""
@export var sender_address: String = ""
@export var subject: String = ""
@export_multiline var body: String = ""
@export var chapter: int = 0
@export var requires_task_id: String = ""
@export var grants_flag: StringName = &""
@export var sorted_by_time: bool = true
## Shown once, then archived. Meta events can un-hide mutated copies.
@export var hidden: bool = false
@export var read_by_default: bool = false
