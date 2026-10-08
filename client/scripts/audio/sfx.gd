extends Node
## Autoload `Sfx` (M-001): the only way the game makes a noise.
##
## Why one autoload: the dev's brief is "nothing high-pitched, loud or
## annoying", and that is enforced here rather than at 40 call sites - one bus,
## a fixed voice pool, one toggle.
##
##   Sfx.play("card_flip")    -> picks card_flip_1..3 at random, +/-3% pitch
##   Sfx.haptic("pack_tear")  -> 20 ms, same toggle as sound
##
## Pure helpers (variant_for / pitch_jitter_for) take an RNG so tests can pin
## the behaviour without a live audio device.

const AUDIO_DIR := "res://audio/"
const BUS := "SFX"
const SETTINGS_PATH := "user://settings.cfg"

## Never more than three overlapping sounds: a fast pack opening stacks several
## cues and the mix must not turn into a pile. The oldest voice is dropped.
const MAX_VOICES := 3
## Repetition grates faster than loudness. Small enough to stay in key on a
## sine, large enough that a run of taps never sounds like a machine.
const PITCH_JITTER := 0.03

## Short and rare (ANIMATOR.md): only moments a thumb cannot feel otherwise.
const HAPTIC_MS := {"pack_tear": 20, "reveal_legendary": 35}

## Variant suffixes per sound. Kept explicit so a typo is an empty button on
## the sound board rather than a silent failure at runtime.
const VARIANT_COUNTS := {
	"pack_rustle": 3,
	"card_slide": 4,
	"card_flip": 3,
	"tap": 3,
}

## Global sound toggle; defaults to on (ANIMATOR.md) and persists.
var enabled := true

var _rng := RandomNumberGenerator.new()
var _voices: Array[AudioStreamPlayer] = []
## Voices that actually reached the audio device. Differs from play() calls
## whenever the pool has no tree to play in (see play()), so a muted-but-
## working board can never be confused with a dead one.
var _started := 0
## When each pooled voice last started, by pool index. _take_voice drops the
## lowest. Unset entries read as 0, so a fresh voice always wins a free slot.
var _seq_of := PackedInt32Array()
var _play_seq := 0
## Cached streams so a tap never touches the disk mid-frame.
var _streams: Dictionary = {}
var _settings := ConfigFile.new()


func _ready() -> void:
	_rng.randomize()
	_load_settings()
	_ensure_pool()


func _exit_tree() -> void:
	_save_settings()


# --- playback ----------------------------------------------------------------

## Play `name`, choosing a random `name_N` variant and +/-PITCH_JITTER pitch.
## Silently does nothing when sound is off or the stream is missing, so callers
## never have to guard.
##
## The voice is still picked and handed back when the pool is not in a scene
## tree: AudioStreamPlayer.play() is an engine error outside one (the headless
## test runner builds its tree root late), and callers use the return value to
## reason about the cap. Nothing reaches an audio device in that case anyway.
func play(name: String) -> AudioStreamPlayer:
	if not enabled:
		return null
	var stream := _stream_for(variant_for(name, _rng))
	if stream == null:
		return null
	var player := _take_voice()
	player.stream = stream
	player.pitch_scale = pitch_jitter_for(_rng)
	if is_inside_tree():
		player.play()
		_started += 1
	return player


## Long sound (pack tear, legendary reveal) with its haptic. The sound lane's
## "build anticipation" cue is the one place both channels fire together.
func play_and_haptic(name: String) -> AudioStreamPlayer:
	var p := play(name)
	if p != null:
		haptic(name)
	return p


## ms of vibration for `kind`, or 0 when that moment has no haptic or the
## toggle is off. Input.vibrate_handheld is a no-op off-device, so this is safe
## in the editor and in tests.
func haptic(kind: String) -> int:
	if not enabled:
		return 0
	var ms: int = int(HAPTIC_MS.get(kind, 0))
	if ms <= 0:
		return 0
	Input.vibrate_handheld(ms)
	return ms


## How many players the pool holds (always MAX_VOICES once built).
func voice_pool_size() -> int:
	_ensure_pool()
	return _voices.size()


## How many voices actually reached the audio device since launch. Stays 0
## while the pool is outside a scene tree, which is how a test proves play()
## never asks the engine to play from a detached node.
func voices_started() -> int:
	return _started


# --- pure helpers (the tested surface) ---------------------------------------

## The WAV stem that should sound for `name`: `name_1..name_N` at random when
## variants exist, otherwise `name` itself. An unknown sound still round-trips
## its name so play() can report a missing stream instead of guessing.
static func variant_for(name: String, rng: RandomNumberGenerator) -> String:
	var count := int(VARIANT_COUNTS.get(name, 0))
	if count <= 0:
		return name
	return "%s_%d" % [name, rng.randi_range(1, count)]


## Pitch scale in [1-JITTER, 1+JITTER]. Jitter in pitch, never in volume: volume
## shifts read as loudness, pitch shifts read as "another take".
static func pitch_jitter_for(rng: RandomNumberGenerator) -> float:
	return 1.0 + rng.randf_range(-PITCH_JITTER, PITCH_JITTER)


# --- settings ----------------------------------------------------------------

func set_enabled(on: bool) -> void:
	_ensure_pool()
	enabled = on
	_settings.set_value("audio", "enabled", on)
	if not on:
		# Silencing must silence now, not at the next tap.
		for p in _voices:
			p.stop()
	# Save immediately: a player who turns sound off expects it to stay off.
	_settings.save(SETTINGS_PATH)


func _load_settings() -> void:
	if _settings.load(SETTINGS_PATH) != OK:
		# First run, or an unreadable file: default to on (AGENTS.md launch).
		enabled = true
		return
	enabled = bool(_settings.get_value("audio", "enabled", true))


func _save_settings() -> void:
	_settings.set_value("audio", "enabled", enabled)
	_settings.save(SETTINGS_PATH)


# --- internals ---------------------------------------------------------------

## Fixed pool: built once, recycled forever, so play() allocates nothing and the
## voice count is a fact rather than a hope. Built lazily because callers can
## reach play() before the node is ready (and tests do).
func _ensure_pool() -> void:
	if not _voices.is_empty():
		return
	for i in MAX_VOICES:
		var p := AudioStreamPlayer.new()
		p.name = "Voice%d" % i
		p.bus = BUS
		# Release the stream reference so a long session holds no dead audio.
		p.finished.connect(_on_voice_finished.bind(p))
		add_child(p)
		_voices.append(p)
	_seq_of.resize(MAX_VOICES)
	_seq_of.fill(0)


func _take_voice() -> AudioStreamPlayer:
	_ensure_pool()
	# Age is a monotonic counter indexed by pool slot, not `playing` or
	# playback_position: the audio device has no clock at startup or under
	# --headless, so either would pick an arbitrary victim. Recycling purely by
	# age also matches "drop the oldest" - a voice that already finished is the
	# oldest one anyway. Slot indices (not instance ids) keep the bookkeeping
	# valid when a voice is freed.
	_play_seq += 1
	var oldest := 0
	for i in range(1, _voices.size()):
		if _seq_of[i] < _seq_of[oldest]:
			oldest = i
	_seq_of[oldest] = _play_seq
	var player := _voices[oldest]
	player.stop()
	return player


func _on_voice_finished(p: AudioStreamPlayer) -> void:
	p.stream = null


func _stream_for(stem: String) -> AudioStream:
	if _streams.has(stem):
		return _streams[stem]
	var path := AUDIO_DIR + stem + ".wav"
	if not ResourceLoader.exists(path):
		push_warning("Sfx: no sound named '%s'" % stem)
		return null
	var s := ResourceLoader.load(path) as AudioStream
	_streams[stem] = s
	return s