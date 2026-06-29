extends Node
## AudioManager — handles SFX for tap, win, lose, draw, error.
## Sounds are optional; we generate them procedurally if no audio assets are present.

var _bus_sfx: int = 1
var _tap_sound: AudioStream
var _win_sound: AudioStream
var _lose_sound: AudioStream
var _error_sound: AudioStream

func _ready() -> void:
	_tap_sound = _make_tone(880.0, 0.05)
	_win_sound = _make_arpeggio([523.25, 659.25, 783.99, 1046.5], 0.12)
	_lose_sound = _make_arpeggio([392.0, 329.63, 261.63, 196.0], 0.18)
	_error_sound = _make_tone(220.0, 0.2)

func _make_tone(freq: float, duration: float) -> AudioStreamWAV:
	var sample_rate := 22050
	var sample_count := int(sample_rate * duration)
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_8_BITS
	stream.mix_rate = sample_rate
	stream.stereo = false
	var data := PackedByteArray()
	data.resize(sample_count)
	for i in sample_count:
		var t := float(i) / sample_rate
		var env := 1.0 - (float(i) / sample_count)
		var sample := sin(TAU * freq * t) * 0.4 * env
		data[i] = int((sample + 1.0) * 127.5)
	stream.data = data
	return stream

func _make_arpeggio(freqs: Array, note_dur: float) -> AudioStreamWAV:
	var sample_rate := 22050
	var per_note := int(sample_rate * note_dur)
	var total := per_note * freqs.size()
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_8_BITS
	stream.mix_rate = sample_rate
	stream.stereo = false
	var data := PackedByteArray()
	data.resize(total)
	for note_idx in freqs.size():
		var freq: float = freqs[note_idx]
		for i in per_note:
			var t := float(i) / sample_rate
			var env := 1.0 - (float(i) / per_note)
			var sample := sin(TAU * freq * t) * 0.35 * env
			var idx := note_idx * per_note + i
			data[idx] = int((sample + 1.0) * 127.5)
	stream.data = data
	return stream

func play_tap() -> void: _play(_tap_sound)
func play_win() -> void: _play(_win_sound)
func play_lose() -> void: _play(_lose_sound)
func play_error() -> void: _play(_error_sound)

func _play(stream: AudioStream) -> void:
	if stream == null:
		return
	var player := AudioStreamPlayer.new()
	player.stream = stream
	player.bus = "SFX"
	add_child(player)
	player.play()
	player.finished.connect(player.queue_free)