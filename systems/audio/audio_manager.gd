extends Node
## AudioManager — one owner for every sound in the game.
##
## The project ships no binary audio assets: all sounds are synthesised at
## runtime (AudioStreamWAV), so ambience/SFX/horror stings work out of the box
## and remain fully data-driven through the `@export` parameters below.

signal bus_volume_changed(bus: String, linear: float)
signal tension_changed(level: int)

const BUS_MASTER := "Master"
const BUS_MUSIC := "Music"
const BUS_SFX := "SFX"
const BUS_AMBIENCE := "Ambience"
const BUS_UI := "UI"
const BUS_HORROR := "Horror"
const BUS_COMPUTER := "Computer"
const BUS_GAME2D := "Game2D"

const MIX_RATE := 22050
const TENSION_LEVELS := 6

## Ambience layer gain per TENSION_0..5. Linear 0..1.
@export var tension_ambience_gain: PackedFloat32Array = PackedFloat32Array([0.0, 0.15, 0.35, 0.6, 0.85, 1.0])
## Drone base frequency per TENSION level.
@export var tension_drone_hz: PackedFloat32Array = PackedFloat32Array([48.0, 46.0, 43.0, 39.0, 34.0, 27.0])
## Probability weight multiplier for random stingers, per tension level.
@export var tension_stinger_weight: PackedFloat32Array = PackedFloat32Array([0.0, 0.15, 0.3, 0.5, 0.75, 1.0])

var _stream_cache: Dictionary = {}
var _loop_players: Dictionary = {}
var _pool: Array[AudioStreamPlayer] = []
var _pool_index: int = 0
var _voices: Array[AudioStreamPlayer3D] = []
var _voice_index: int = 0
var _rng := RandomNumberGenerator.new()
var tension: int = 0
## The drone pitch currently loaded into the tension_drone loop, so the stream is
## only rebuilt when the pitch actually changes.
var _drone_hz: float = 0.0
var _ready_done: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_rng.randomize()
	_ensure_buses()
	for i in 10:
		var p := AudioStreamPlayer.new()
		p.bus = BUS_SFX
		p.process_mode = Node.PROCESS_MODE_ALWAYS
		add_child(p)
		_pool.append(p)
	for i in 8:
		var v := AudioStreamPlayer3D.new()
		v.bus = BUS_SFX
		v.max_distance = 30.0
		v.unit_size = 4.0
		v.process_mode = Node.PROCESS_MODE_ALWAYS
		add_child(v)
		_voices.append(v)
	_start_loops()
	_ready_done = true
	apply_settings()


func _ensure_buses() -> void:
	for bus_name in [BUS_MUSIC, BUS_SFX, BUS_AMBIENCE, BUS_UI, BUS_HORROR, BUS_COMPUTER, BUS_GAME2D]:
		if AudioServer.get_bus_index(bus_name) == -1:
			var idx := AudioServer.bus_count
			AudioServer.add_bus(idx)
			AudioServer.set_bus_name(idx, bus_name)
			AudioServer.set_bus_send(idx, BUS_MASTER)


func apply_settings() -> void:
	if not _ready_done:
		return
	set_bus_volume(BUS_MASTER, Settings.get_value("master_volume", 0.9))
	set_bus_volume(BUS_MUSIC, Settings.get_value("music_volume", 0.6))
	set_bus_volume(BUS_SFX, Settings.get_value("sfx_volume", 0.9))
	set_bus_volume(BUS_AMBIENCE, Settings.get_value("ambience_volume", 0.8))
	set_bus_volume(BUS_UI, Settings.get_value("ui_volume", 0.8))


func set_bus_volume(bus_name: String, linear: float) -> void:
	var idx := AudioServer.get_bus_index(bus_name)
	if idx == -1:
		return
	AudioServer.set_bus_volume_db(idx, linear_to_db(clampf(linear, 0.0001, 2.0)))
	AudioServer.set_bus_mute(idx, linear <= 0.0001)
	bus_volume_changed.emit(bus_name, linear)


func fade_bus(bus_name: String, to_linear: float, duration: float = 1.0) -> void:
	var idx := AudioServer.get_bus_index(bus_name)
	if idx == -1 or duration <= 0.0:
		set_bus_volume(bus_name, to_linear)
		return
	var from_db := AudioServer.get_bus_volume_db(idx)
	var to_db := linear_to_db(clampf(to_linear, 0.0001, 2.0))
	var tw := create_tween()
	tw.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tw.tween_method(
		func(v: float) -> void:
			AudioServer.set_bus_volume_db(idx, v)
			AudioServer.set_bus_mute(idx, v <= linear_to_db(0.0001)),
		from_db, to_db, duration
	)


# --- loops ------------------------------------------------------------------

func _start_loops() -> void:
	_start_loop("office_room", BUS_AMBIENCE, stream_room_tone(), -26.0)
	_start_loop("computer_hum", BUS_COMPUTER, stream_hum(), -30.0)
	_start_loop("tension_drone", BUS_HORROR, stream_drone(tension_drone_hz[0]), -60.0)
	_start_loop("music_calm", BUS_MUSIC, stream_pad(196.0, 293.66), -34.0)
	_start_loop("music_tension", BUS_MUSIC, stream_pad(98.0, 146.83, 4.0), -60.0)
	_start_loop("music_peak", BUS_MUSIC, stream_pad(233.08, 277.18, 4.0), -60.0)
	_drone_hz = tension_drone_hz[0]


func _start_loop(key: String, bus_name: String, stream: AudioStream, volume_db: float) -> void:
	var p := AudioStreamPlayer.new()
	p.name = "Loop_" + key
	p.bus = bus_name
	p.stream = stream
	p.volume_db = volume_db
	p.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(p)
	p.play()
	_loop_players[key] = p


func set_loop_gain(key: String, volume_db: float, duration: float = 1.5) -> void:
	var p: AudioStreamPlayer = _loop_players.get(key)
	if p == null:
		return
	if duration <= 0.0:
		p.volume_db = volume_db
		return
	var tw := create_tween()
	tw.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tw.tween_property(p, "volume_db", volume_db, duration)


func set_loop_playing(key: String, playing: bool) -> void:
	var p: AudioStreamPlayer = _loop_players.get(key)
	if p == null:
		return
	if playing and not p.playing:
		p.play()
	elif not playing and p.playing:
		p.stop()


## Stop every voice and drop every synthesized stream.
##
## All audio here is generated at runtime and cached in _stream_cache, so the
## cache is the only thing keeping those AudioStreamWAV objects alive. Dropping
## it on teardown frees them deterministically instead of letting the engine
## report the session cache as leaked, and a closing game releases its audio
## memory immediately rather than at process exit.
func shutdown() -> void:
	for p: AudioStreamPlayer in _pool:
		p.stop()
		p.stream = null
	for v: AudioStreamPlayer3D in _voices:
		v.stop()
		v.stream = null
	for key: String in _loop_players.keys():
		var p := _loop_players[key] as AudioStreamPlayer
		if p != null:
			p.stop()
			p.stream = null
	_loop_players.clear()
	_stream_cache.clear()


func _exit_tree() -> void:
	# Autoloads are removed from the tree when the SceneTree is torn down; the
	# children are still alive here, so stopping them is safe and quiet.
	shutdown()


# --- tension ----------------------------------------------------------------

func set_tension(level: int) -> void:
	tension = clampi(level, 0, TENSION_LEVELS - 1)
	var gain: float = tension_ambience_gain[tension] if tension < tension_ambience_gain.size() else 0.0
	var hz: float = tension_drone_hz[tension] if tension < tension_drone_hz.size() else 48.0
	var p: AudioStreamPlayer = _loop_players.get("tension_drone")
	if p:
		set_loop_gain("tension_drone", linear_to_db(clampf(gain, 0.0001, 1.0)), 2.5)
		# Comparing the stream against a freshly synthesised one would rebuild a
		# multi-second buffer on every tension change just to throw it away, so
		# the applied pitch is tracked instead.
		if not is_equal_approx(_drone_hz, hz):
			_drone_hz = hz
			var was_playing := p.playing
			p.stream = stream_drone(hz)
			if was_playing:
				p.play()
	_apply_music_layers()
	tension_changed.emit(tension)


## The music bus cross-fades three layers with the tension level: a calm pad
## that always plays, a pulse that fades in from TENSION_2 and a lead that only
## exists at TENSION_4+. The pad itself is ducked by whoever owns the context
## (minigame, gallery), so it never re-asserts its own volume here.
func _apply_music_layers() -> void:
	var pulse := _tension_ramp(2)
	var lead := _tension_ramp(4)
	set_loop_gain("music_tension", _layer_db(pulse), 3.0)
	set_loop_gain("music_peak", _layer_db(lead), 3.0)


## 0.0 below `from_level`, 1.0 at and above the top of the tension range.
func _tension_ramp(from_level: int) -> float:
	if tension <= from_level:
		return 0.0
	var span: float = float(maxi(TENSION_LEVELS - 1 - from_level, 1))
	return clampf(float(tension - from_level) / span, 0.0, 1.0)


func _layer_db(gain: float) -> float:
	if gain <= 0.001:
		return -60.0
	return linear_to_db(clampf(gain, 0.001, 1.0))


func stinger_weight() -> float:
	if not bool(Settings.get_value("stingers_enabled", true)):
		return 0.0
	return tension_stinger_weight[tension] if tension < tension_stinger_weight.size() else 0.0


# --- one-shots --------------------------------------------------------------

func play_sfx(key: String, volume_db: float = 0.0, pitch: float = 1.0) -> void:
	_play_one_shot(key, BUS_SFX, volume_db, pitch)


func play_ui(key: String, volume_db: float = 0.0) -> void:
	match key:
		"hover": _play_one_shot("blip", BUS_UI, -12.0, 1.4)
		"click": _play_one_shot("click", BUS_UI, -8.0)
		"open": _play_one_shot("blip", BUS_UI, -8.0, 0.9)
		"close": _play_one_shot("blip", BUS_UI, -8.0, 0.7)
		"error": _play_one_shot("blip", BUS_UI, -6.0, 0.55)
		"type": _play_one_shot("tick", BUS_UI, -22.0, 1.0)
		_: _play_one_shot(key, BUS_UI, volume_db)


func play_computer(key: String) -> void:
	match key:
		"boot": _play_one_shot("boot", BUS_COMPUTER, -6.0)
		"error": _play_one_shot("glitch", BUS_COMPUTER, -10.0)
		"crash": _play_one_shot("crash", BUS_COMPUTER, -4.0)
		"confirm": _play_one_shot("blip", BUS_COMPUTER, -12.0, 1.1)
		_: _play_one_shot(key, BUS_COMPUTER, -12.0)


func play_game2d(key: String) -> void:
	match key:
		"jump": _play_one_shot("blip", BUS_GAME2D, -16.0, 1.6)
		"coin": _play_one_shot("blip", BUS_GAME2D, -14.0, 2.0)
		"hit": _play_one_shot("noise", BUS_GAME2D, -14.0, 1.2)
		"death": _play_one_shot("sweep_down", BUS_GAME2D, -8.0)
		"win": _play_one_shot("arpeggio", BUS_GAME2D, -10.0)
		"bug": _play_one_shot("glitch", BUS_GAME2D, -8.0)
		_: _play_one_shot(key, BUS_GAME2D, -14.0)


func play_horror(key: String) -> void:
	match key:
		"whisper": _play_one_shot("whisper", BUS_HORROR, -8.0)
		"sting": _play_one_shot("sting", BUS_HORROR, -4.0)
		"glitch": _play_one_shot("glitch", BUS_HORROR, -6.0)
		"drone_hit": _play_one_shot("sweep_down", BUS_HORROR, -4.0)
		"screamer": _play_one_shot("screamer", BUS_HORROR, 0.0)
		"heartbeat": _play_one_shot("heartbeat", BUS_HORROR, -6.0)
		_: _play_one_shot(key, BUS_HORROR, -10.0)


func play_3d(key: String, global_position: Vector3, volume_db: float = 0.0, pitch: float = 1.0) -> void:
	var stream := get_stream(key)
	if stream == null:
		return
	var v := _voices[_voice_index]
	_voice_index = (_voice_index + 1) % _voices.size()
	v.stream = stream
	v.volume_db = volume_db
	v.pitch_scale = pitch
	v.global_position = global_position
	v.play()


func _play_one_shot(key: String, bus_name: String, volume_db: float, pitch: float = 1.0) -> void:
	var stream := get_stream(key)
	if stream == null:
		return
	var p := _pool[_pool_index]
	_pool_index = (_pool_index + 1) % _pool.size()
	p.stream = stream
	p.bus = bus_name
	p.volume_db = volume_db
	p.pitch_scale = clampf(pitch, 0.05, 4.0)
	p.play()


# --- procedural synthesis ---------------------------------------------------

func get_stream(key: String) -> AudioStream:
	if _stream_cache.has(key):
		return _stream_cache[key]
	var s: AudioStream = null
	match key:
		"blip": s = stream_tone(880.0, 0.06)
		"click": s = stream_click()
		"tick": s = stream_tone(1600.0, 0.02)
		"boot": s = stream_boot()
		"crash": s = stream_crash()
		"glitch": s = stream_glitch()
		"noise": s = stream_noise(0.35)
		"hum": s = stream_hum()
		"sting": s = stream_sting()
		"whisper": s = stream_whisper()
		"screamer": s = stream_screamer()
		"heartbeat": s = stream_heartbeat()
		"arpeggio": s = stream_arpeggio()
		"sweep_down": s = stream_sweep(1400.0, 90.0, 0.7)
		"sweep_up": s = stream_sweep(120.0, 1500.0, 0.6)
		_: s = stream_tone(440.0, 0.08)
	_stream_cache[key] = s
	return s


func _wav(samples: PackedFloat32Array, loop: bool = false) -> AudioStreamWAV:
	var bytes := PackedByteArray()
	bytes.resize(samples.size() * 2)
	for i in samples.size():
		var v := int(clampf(samples[i], -1.0, 1.0) * 32767.0)
		bytes.encode_s16(i * 2, v)
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = MIX_RATE
	wav.stereo = false
	wav.data = bytes
	if loop:
		wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
		wav.loop_begin = 0
		wav.loop_end = samples.size()
	return wav


func stream_tone(freq: float, duration: float, kind: int = 0) -> AudioStreamWAV:
	var n := int(MIX_RATE * duration)
	var s := PackedFloat32Array()
	s.resize(n)
	for i in n:
		var t := float(i) / MIX_RATE
		var phase := TAU * freq * t
		var v := 0.0
		match kind:
			1: v = sin(phase)
			2: v = signf(sin(phase))
			3: v = sin(phase) * 0.6 + sin(phase * 2.0) * 0.25
			_: v = sin(phase) * 0.7 + sin(phase * 2.01) * 0.2
		var env: float = minf(1.0, t / 0.01) * pow(1.0 - float(i) / float(n), 1.6)
		s[i] = v * env * 0.6
	return _wav(s)


func stream_click() -> AudioStreamWAV:
	var n := int(MIX_RATE * 0.05)
	var s := PackedFloat32Array()
	s.resize(n)
	for i in n:
		var t := float(i) / MIX_RATE
		var noise := _rng.randf_range(-1.0, 1.0)
		s[i] = noise * pow(1.0 - float(i) / float(n), 8.0) * 0.5
	return _wav(s)


func stream_tick() -> AudioStreamWAV:
	return stream_tone(2000.0, 0.015)


func stream_noise(duration: float) -> AudioStreamWAV:
	var n := int(MIX_RATE * duration)
	var s := PackedFloat32Array()
	s.resize(n)
	var last := 0.0
	for i in n:
		var t := float(i) / MIX_RATE
		last = last * 0.86 + _rng.randf_range(-1.0, 1.0) * 0.14
		s[i] = last * pow(1.0 - t / duration, 1.2) * 0.8
	return _wav(s)


func stream_hum(duration: float = 1.0) -> AudioStreamWAV:
	var n := int(MIX_RATE * duration)
	var s := PackedFloat32Array()
	s.resize(n)
	for i in n:
		var t := float(i) / MIX_RATE
		var v := sin(TAU * 50.0 * t) * 0.5 + sin(TAU * 100.0 * t) * 0.2 + sin(TAU * 150.0 * t) * 0.08
		s[i] = v * 0.35
	return _wav(s, true)


func stream_room_tone(duration: float = 2.0) -> AudioStreamWAV:
	var n := int(MIX_RATE * duration)
	var s := PackedFloat32Array()
	s.resize(n)
	var lp := 0.0
	for i in n:
		var t := float(i) / MIX_RATE
		lp = lp * 0.995 + _rng.randf_range(-1.0, 1.0) * 0.005
		var hum := sin(TAU * 60.0 * t) * 0.06
		s[i] = (lp * 6.0 + hum) * 0.5
	# Crossfade the tail into the head so the loop is seamless.
	var fade := int(MIX_RATE * 0.05)
	for i in fade:
		var a := float(i) / float(fade)
		s[i] = lerpf(s[n - fade + i], s[i], a)
	return _wav(s, true)


func stream_drone(freq: float, duration: float = 3.0) -> AudioStreamWAV:
	var n := int(MIX_RATE * duration)
	var s := PackedFloat32Array()
	s.resize(n)
	for i in n:
		var t := float(i) / MIX_RATE
		var v := sin(TAU * freq * t) * 0.5
		v += sin(TAU * freq * 1.5 * t) * 0.25
		v += sin(TAU * freq * 2.02 * t) * 0.12
		v += sin(TAU * (freq * 0.5) * t + sin(t * 0.7) * 2.0) * 0.3
		s[i] = v * 0.4
	var fade := int(MIX_RATE * 0.1)
	for i in fade:
		var a := float(i) / float(fade)
		s[i] = lerpf(s[n - fade + i], s[i], a)
	return _wav(s, true)


func stream_pad(freq: float, freq2: float, duration: float = 4.0) -> AudioStreamWAV:
	var n := int(MIX_RATE * duration)
	var s := PackedFloat32Array()
	s.resize(n)
	for i in n:
		var t := float(i) / MIX_RATE
		var lfo := 0.5 + 0.5 * sin(TAU * 0.15 * t)
		var v := sin(TAU * freq * t) * 0.4 + sin(TAU * freq2 * t) * 0.3 * lfo
		s[i] = v * 0.25
	var fade := int(MIX_RATE * 0.2)
	for i in fade:
		var a := float(i) / float(fade)
		s[i] = lerpf(s[n - fade + i], s[i], a)
	return _wav(s, true)


func stream_sweep(from_hz: float, to_hz: float, duration: float) -> AudioStreamWAV:
	var n := int(MIX_RATE * duration)
	var s := PackedFloat32Array()
	s.resize(n)
	var phase := 0.0
	for i in n:
		var t := float(i) / float(n)
		var freq: float = lerpf(from_hz, to_hz, t * t)
		phase += TAU * freq / MIX_RATE
		var env: float = pow(1.0 - t, 1.4)
		s[i] = sin(phase) * env * 0.55
	return _wav(s)


func stream_glitch(duration: float = 0.25) -> AudioStreamWAV:
	var n := int(MIX_RATE * duration)
	var s := PackedFloat32Array()
	s.resize(n)
	var gate := 1.0
	var next_switch := 0
	for i in n:
		var t := float(i) / MIX_RATE
		if i >= next_switch:
			gate = _rng.randf_range(0.0, 1.0)
			next_switch = i + int(_rng.randf_range(1, 12))
		var f := _rng.randf_range(80.0, 2400.0)
		var v := sin(TAU * f * t) * gate
		s[i] = v * pow(1.0 - t / duration, 0.7) * 0.5
	return _wav(s)


func stream_boot(duration: float = 1.4) -> AudioStreamWAV:
	var n := int(MIX_RATE * duration)
	var s := PackedFloat32Array()
	s.resize(n)
	for i in n:
		var t := float(i) / MIX_RATE
		var v := 0.0
		if t < 0.5:
			v = sin(TAU * 110.0 * t) * 0.3
		else:
			var u := (t - 0.5) / 0.9
			v = sin(TAU * (220.0 + 660.0 * u) * (t - 0.5)) * 0.35
			if fmod(t, 0.08) < 0.02:
				v += _rng.randf_range(-0.3, 0.3)
		s[i] = v * (1.0 - t / duration * 0.4)
	return _wav(s)


func stream_crash(duration: float = 0.8) -> AudioStreamWAV:
	var n := int(MIX_RATE * duration)
	var s := PackedFloat32Array()
	s.resize(n)
	var lp := 0.0
	for i in n:
		var t := float(i) / MIX_RATE
		lp = lp * 0.7 + _rng.randf_range(-1.0, 1.0) * 0.3
		var burst: float = 1.0 if t < 0.05 else 0.35
		s[i] = lp * burst * pow(1.0 - t / duration, 1.3)
	return _wav(s)


func stream_sting(duration: float = 0.6) -> AudioStreamWAV:
	var n := int(MIX_RATE * duration)
	var s := PackedFloat32Array()
	s.resize(n)
	var phase := 0.0
	for i in n:
		var t := float(i) / MIX_RATE
		var u := float(i) / float(n)
		phase += TAU * (900.0 - 800.0 * u) / MIX_RATE
		var cluster := 1.0 if fmod(t, 0.05) < 0.03 else 0.4
		s[i] = sin(phase) * cluster * pow(1.0 - u, 1.8) * 0.6
	return _wav(s)


func stream_whisper(duration: float = 1.6) -> AudioStreamWAV:
	var n := int(MIX_RATE * duration)
	var s := PackedFloat32Array()
	s.resize(n)
	var bp := 0.0
	for i in n:
		var t := float(i) / MIX_RATE
		bp = bp * 0.93 + _rng.randf_range(-1.0, 1.0) * 0.07
		var form: float = sin(TAU * (700.0 + 300.0 * sin(t * 3.0)) * t)
		var env: float = sin(PI * clampf(t / duration, 0.0, 1.0))
		s[i] = bp * form * env * 1.4
	return _wav(s)


func stream_heartbeat(duration: float = 1.0) -> AudioStreamWAV:
	var n := int(MIX_RATE * duration)
	var s := PackedFloat32Array()
	s.resize(n)
	for i in n:
		var t := float(i) / MIX_RATE
		var v := 0.0
		for beat_t: float in [0.0, 0.28]:
			var d: float = t - beat_t
			if d >= 0.0 and d < 0.22:
				var env: float = pow(1.0 - d / 0.22, 2.2)
				v += sin(TAU * (70.0 - 40.0 * d) * d) * env
		s[i] = v * 0.5
	return _wav(s)


func stream_arpeggio(duration: float = 0.8) -> AudioStreamWAV:
	var n := int(MIX_RATE * duration)
	var s := PackedFloat32Array()
	s.resize(n)
	var notes := [523.25, 659.25, 783.99, 1046.5]
	var step := int(MIX_RATE * duration / float(notes.size()))
	for i in n:
		var idx: int = clampi(i / step, 0, notes.size() - 1)
		var local := float(i % step) / float(step)
		s[i] = sin(TAU * float(notes[idx]) * (float(i) / MIX_RATE)) * pow(1.0 - local, 1.2) * 0.4
	return _wav(s)


func stream_screamer(duration: float = 1.1) -> AudioStreamWAV:
	var n := int(MIX_RATE * duration)
	var s := PackedFloat32Array()
	s.resize(n)
	var phase := 0.0
	var lp := 0.0
	for i in n:
		var t := float(i) / MIX_RATE
		var u := float(i) / float(n)
		phase += TAU * (700.0 + 500.0 * sin(t * 34.0) + 300.0 * u) / MIX_RATE
		lp = lp * 0.5 + sin(phase) * 0.5
		var env: float = minf(1.0, t / 0.02) * pow(1.0 - u, 1.1)
		s[i] = lp * env * 0.8
	return _wav(s)
