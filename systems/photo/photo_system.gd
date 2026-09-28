extends Node
## PhotoSystem — the in-game camera and the evidence it produces.
##
## Photographs are generated procedurally into memory Images (never written to
## disk, as allowed by the brief). This also makes the meta-horror beat
## "the photograph changes" a one-line mutation instead of file surgery.

signal photo_taken(record: PhotoRecord)
signal photo_evidence_ready(evidence: PhotoEvidence)
signal photo_mutated(record: PhotoRecord)
signal photo_count_changed(count: int)

const IMAGE_W := 128
const IMAGE_H := 96
const MAX_PHOTOS := 60
const RAY_LENGTH := 6.0
const SUBJECT_THRESHOLD := 0.18  ## NDC distance from screen centre.

@export var office_raycast_mask: int = 1
@export var flash_duration: float = 0.18
@export var shutter_sound_db: float = -6.0

var photos: Array[PhotoRecord] = []
var _id_counter: int = 0
var _rng := RandomNumberGenerator.new()
var _cooldown: float = 0.0
## Registered 3D objects that can be photographed as evidence.
var _photo_targets: Array[Node3D] = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_rng.randomize()
	SaveSystem.register(&"photos", self)


func _process(delta: float) -> void:
	if _cooldown > 0.0:
		_cooldown = maxf(0.0, _cooldown - delta)


# --- photo targets in the 3D world ------------------------------------------

func register_photo_target(node: Node3D) -> void:
	if node != null and not _photo_targets.has(node):
		_photo_targets.append(node)


func unregister_photo_target(node: Node3D) -> void:
	_photo_targets.erase(node)


func clear_photo_targets() -> void:
	_photo_targets.clear()


# --- capture ----------------------------------------------------------------

func can_take_photo() -> bool:
	if _cooldown > 0.0:
		return false
	if GameManager.mode == GameManager.Mode.EXPLORE:
		return true
	if GameManager.mode == GameManager.Mode.MINIGAME and MinigameSystem.is_game_running():
		return true
	if GameManager.mode == GameManager.Mode.COMPUTER and MinigameSystem.is_game_running():
		return true
	return false


func take_photo() -> PhotoRecord:
	if not can_take_photo():
		return null
	_cooldown = 0.45

	var rec: PhotoRecord
	if GameManager.mode == GameManager.Mode.EXPLORE:
		rec = _capture_office()
	else:
		rec = _capture_monitor()
	AudioManager.play_sfx("click", shutter_sound_db)
	AudioManager.play_sfx("noise", -18.0, 1.4)
	_flash_screen()

	photos.append(rec)
	while photos.size() > MAX_PHOTOS:
		photos.pop_front()
	photo_taken.emit(rec)
	photo_count_changed.emit(photos.size())

	if rec.valid and rec.bug_id != "":
		var ok := BugSystem.register_evidence(rec.to_evidence())
		if ok:
			photo_evidence_ready.emit(rec.to_evidence())
	return rec


func _capture_office() -> PhotoRecord:
	var id := _next_id()
	var rec := PhotoRecord.create(id, "", false, "office")
	rec.chapter = StorySystem.get_chapter() if has_node("/root/StorySystem") else 0

	var cam := _active_camera()
	var subject := _find_photo_target(cam)
	if subject != null:
		var bug_id := str(subject.get_meta("photo_bug_id", ""))
		if bug_id != "":
			rec.bug_id = bug_id
			rec.valid = BugSystem.is_known(bug_id) and not BugSystem.is_reported(bug_id)
			if rec.valid and not BugSystem.is_photo_valid(bug_id):
				rec.valid = true
		rec.subject_position = _screen_position(cam, subject.global_position)
		rec.label = subject.name
	else:
		rec.subject_position = Vector2(_rng.randf_range(-0.3, 0.3), _rng.randf_range(-0.2, 0.2))
		rec.label = "office"

	rec.image = _render_office_image(subject != null, rec.subject_position)
	return rec


func _capture_monitor() -> PhotoRecord:
	var id := _next_id()
	var rec := PhotoRecord.create(id, "", false, "monitor")
	rec.chapter = StorySystem.get_chapter() if has_node("/root/StorySystem") else 0
	var shot := MinigameSystem.describe_active_bug()
	rec.subject_position = shot.get("ndc", Vector2(0, 0))
	rec.bug_id = String(shot.get("bug_id", ""))
	rec.valid = bool(shot.get("valid", false)) and rec.bug_id != ""
	rec.label = rec.bug_id if rec.bug_id != "" else "screen"
	rec.image = _render_screen_image(rec.valid, rec.subject_position, rec.bug_id)
	return rec


func _active_camera() -> Camera3D:
	var player := GameManager.get_player()
	if player != null:
		var c := player.get_node_or_null("Head/Camera3D") as Camera3D
		if c != null:
			return c
	return get_viewport().get_camera_3d()


func _find_photo_target(cam: Camera3D) -> Node3D:
	if cam == null:
		return null
	var space := cam.get_world_3d().direct_space_state
	if space == null:
		return null
	var q := PhysicsRayQueryParameters3D.create(
		cam.global_position, cam.global_position - cam.global_transform.basis.z * RAY_LENGTH
	)
	q.collision_mask = office_raycast_mask
	q.collide_with_areas = true
	q.collide_with_bodies = true
	var hit := space.intersect_ray(q)
	if hit.is_empty():
		return null
	var collider: Object = hit.get("collider")
	if collider is Node3D and _photo_targets.has(collider):
		return collider as Node3D
	return null


func _screen_position(cam: Camera3D, world_pos: Vector3) -> Vector2:
	if cam == null or not cam.is_position_behind(world_pos):
		return Vector2(9, 9)
	return cam.unproject_position(world_pos) / Vector2(get_viewport().get_visible_rect().size) * 2.0 - Vector2.ONE


# --- procedural image synthesis ---------------------------------------------

func _new_image(base: Color) -> Image:
	var img := Image.create(IMAGE_W, IMAGE_H, false, Image.FORMAT_RGB8)
	img.fill(base)
	return img


func _render_office_image(has_subject: bool, ndc: Vector2) -> Image:
	var img := _new_image(Color(0.05, 0.05, 0.06))
	var rng := RandomNumberGenerator.new()
	rng.seed = int(ndc.x * 10000.0) ^ int(ndc.y * 7777.0) ^ photos.size()

	# Vignette + desk surface + monitor glow: a plausible "office" frame.
	for y in IMAGE_H:
		for x in IMAGE_W:
			var u := float(x) / IMAGE_W
			var v := float(y) / IMAGE_H
			var r := 0.05 + 0.05 * (1.0 - v)
			var g := 0.05 + 0.045 * (1.0 - v)
			var b := 0.06 + 0.07 * (1.0 - v)
			if v > 0.62:
				var desk := (v - 0.62) / 0.38
				r = lerpf(r, 0.16, desk)
				g = lerpf(g, 0.13, desk)
				b = lerpf(b, 0.11, desk)
			# Screen glow in the upper middle.
			var glow := exp(-((u - 0.5) * (u - 0.5)) * 9.0 - ((v - 0.38) * (v - 0.38)) * 12.0)
			r += glow * 0.10
			g += glow * 0.16
			b += glow * 0.20
			# Sensor noise.
			var n := rng.randf_range(-0.035, 0.035)
			var vig := 1.0 - 0.7 * pow(maxf(absf(u - 0.5), absf(v - 0.5)) * 1.9, 2.4)
			img.set_pixel(x, y, Color(clampf((r + n) * vig, 0, 1), clampf((g + n) * vig, 0, 1), clampf((b + n) * vig, 0, 1)))

	if has_subject:
		var px := int(clampf((ndc.x * 0.5 + 0.5) * IMAGE_W, 4, IMAGE_W - 5))
		var py := int(clampf((1.0 - (ndc.y * 0.5 + 0.5)) * IMAGE_H, 4, IMAGE_H - 5))
		_blit_blob(img, px, py, 9, 9, Color(0.85, 0.88, 0.95))
	# Flash corner: camera UI furniture.
	_blit_rect(img, 2, 2, 10, 2, Color(0.9, 0.3, 0.2))
	return img


func _render_screen_image(valid: bool, ndc: Vector2, bug_id: String) -> Image:
	var img := _new_image(Color(0.02, 0.02, 0.03))
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(bug_id) + photos.size()

	# The photographed screen keeps the pixel-art look of the 2D game.
	var scale := 3
	for y in IMAGE_H:
		for x in IMAGE_W:
			var u := float(x) / IMAGE_W
			var v := float(y) / IMAGE_H
			var sky := 0.06 + 0.05 * sin(u * 6.0)
			var ground := 0.03
			var c: Color
			if v < 0.72:
				c = Color(sky * 0.5, sky * 0.7, sky * 1.4)
			else:
				c = Color(ground, ground * 1.2, ground * 1.1)
			var block := (int(x / scale) % 2 == 0) and (int(y / scale) % 2 == 0)
			if block:
				c = c.darkened(0.12)
			c = c.darkened(rng.randf_range(-0.02, 0.02))
			var vig := 1.0 - 0.8 * pow(maxf(absf(u - 0.5), absf(v - 0.5)) * 1.9, 2.2)
			img.set_pixel(x, y, Color(c.r * vig, c.g * vig, c.b * vig))

	if valid:
		var px := int(clampf((ndc.x * 0.5 + 0.5) * IMAGE_W, 4, IMAGE_W - 12))
		var py := int(clampf((1.0 - (ndc.y * 0.5 + 0.5)) * IMAGE_H, 4, IMAGE_H - 12))
		_blit_blob(img, px, py, 12, 20, Color(1.0, 0.25, 0.2))
	# CRT scanlines.
	for y in range(0, IMAGE_H, 2):
		for x in IMAGE_W:
			img.set_pixel(x, y, img.get_pixel(x, y).darkened(0.22))
	return img


func _blit_blob(img: Image, cx: int, cy: int, w: int, h: int, color: Color) -> void:
	for y in range(cy - h / 2, cy + h / 2):
		for x in range(cx - w / 2, cx + w / 2):
			if x < 0 or y < 0 or x >= IMAGE_W or y >= IMAGE_H:
				continue
			var d := Vector2(float(x - cx) / (w * 0.5), float(y - cy) / (h * 0.5)).length()
			var a: float = clampf(1.0 - d, 0.0, 1.0)
			img.set_pixel(x, y, img.get_pixel(x, y).lerp(color, a))


func _blit_rect(img: Image, x0: int, y0: int, w: int, h: int, color: Color) -> void:
	for y in range(y0, y0 + h):
		for x in range(x0, x0 + w):
			if x < 0 or y < 0 or x >= IMAGE_W or y >= IMAGE_H:
				continue
			img.set_pixel(x, y, color)


# --- meta-horror: the photograph changes ------------------------------------

func mutate_photo(photo_id: String, level: int = 1) -> bool:
	var rec := get_photo(photo_id)
	if rec == null or rec.mutation_level >= level:
		return false
	rec.mutation_level = level
	rec.image = _mutated_image(rec, level)
	rec.tex = null
	rec.label = "%s (rev.%d)" % [rec.label, rec.mutation_level + 1]
	photo_mutated.emit(rec)
	return true


func mutate_all_photos(level: int = 1) -> int:
	var n := 0
	for rec in photos:
		if mutate_photo(rec.id, level):
			n += 1
	return n


func _mutated_image(rec: PhotoRecord, level: int) -> Image:
	var img := _new_image(Color(0.02, 0.02, 0.02))
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(rec.id) + level * 7919
	if rec.image != null:
		img.blit_rect(rec.image, Rect2i(0, 0, IMAGE_W, IMAGE_H), Vector2i.ZERO)
		img = img.duplicate() as Image

	# Extra silhouette in the frame that was not there before.
	var px := rng.randi_range(IMAGE_W / 3, IMAGE_W * 2 / 3)
	_blit_blob(img, px, IMAGE_H - 14, 10, 26, Color(0.05, 0.05, 0.06))
	# Torn scanlines.
	for i in level * 6:
		var y := rng.randi_range(0, IMAGE_H - 1)
		for x in IMAGE_W:
			img.set_pixel(x, y, img.get_pixel(x, y).lightened(0.35))
	# Timestamp-like burnt-in text bar.
	_blit_rect(img, 4, IMAGE_H - 8, 44, 3, Color(0.8, 0.8, 0.7))
	_blit_rect(img, IMAGE_W - 30, 4, 24, 2, Color(0.9, 0.2, 0.2))
	return img


# --- collection -------------------------------------------------------------

func get_photo(photo_id: String) -> PhotoRecord:
	for rec in photos:
		if rec.id == photo_id:
			return rec
	return null


func get_valid_photos() -> Array[PhotoRecord]:
	var out: Array[PhotoRecord] = []
	for rec in photos:
		if rec.valid:
			out.append(rec)
	return out


func count() -> int:
	return photos.size()


func _next_id() -> String:
	_id_counter += 1
	return "PH_%04d" % _id_counter


# --- presentation -----------------------------------------------------------

func _flash_screen() -> void:
	var layer := get_tree().get_first_node_in_group("photo_flash_layer")
	if layer == null:
		return
	if layer.has_method("flash"):
		layer.call("flash")


# --- persistence ------------------------------------------------------------

func get_save_state() -> Dictionary:
	var out := []
	for rec in photos:
		out.append(rec.to_dict())
	return {"photos": out, "id_counter": _id_counter}


func apply_save_state(data: Dictionary) -> void:
	photos.clear()
	for d: Variant in data.get("photos", []):
		if typeof(d) == TYPE_DICTIONARY:
			photos.append(PhotoRecord.from_dict(d))
	_id_counter = int(data.get("id_counter", photos.size()))
	photo_count_changed.emit(photos.size())
