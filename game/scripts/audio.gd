class_name GameAudio
extends Node
## 音效池 + 主持语音 + 背景音乐。静音开关只影响播放，不影响任何规则结果。

var sfx_on := true
var voice_on := true
var music_on := true

var _pool: Array[AudioStreamPlayer] = []
var _next := 0
var _voice: AudioStreamPlayer
var _music: AudioStreamPlayer
var _cache: Dictionary = {}
var _voice_prio := 0


func _ready() -> void:
	for i in 12:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_pool.append(p)
	_voice = AudioStreamPlayer.new()
	_voice.volume_db = 2.0
	add_child(_voice)
	_voice.finished.connect(func(): _voice_prio = 0)
	_music = AudioStreamPlayer.new()
	_music.volume_db = -15.0
	add_child(_music)
	_music.finished.connect(func(): if music_on: _music.play())


func _load(path: String) -> AudioStream:
	if not _cache.has(path):
		_cache[path] = load(path) if ResourceLoader.exists(path) else null
	return _cache[path]


func sfx(name: String, vol_db := 0.0, pitch := 1.0) -> void:
	if not sfx_on:
		return
	var s := _load("res://assets/audio/sfx/%s.wav" % name)
	if s == null:
		return
	var p := _pool[_next]
	_next = (_next + 1) % _pool.size()
	p.stream = s
	p.volume_db = vol_db
	p.pitch_scale = pitch
	p.play()


## prio 越大越重要；正在播放更重要的台词时，低优先级台词直接丢弃（不排队、不拖延操作）。
func voice(name: String, prio := 1) -> bool:
	if not voice_on:
		return false
	if _voice.playing and prio < _voice_prio:
		return false
	var s := _load("res://assets/audio/vo/%s.mp3" % name)
	if s == null:
		return false
	_voice.stream = s
	_voice_prio = prio
	_voice.play()
	return true


func stop_voice() -> void:
	_voice.stop()
	_voice_prio = 0


func start_music() -> void:
	var s := _load("res://assets/audio/bgm.mp3")
	if s == null:
		return
	_music.stream = s
	if music_on and not _music.playing:
		_music.play()


func set_music(on: bool) -> void:
	music_on = on
	if on:
		start_music()
	else:
		_music.stop()


func duck(on: bool) -> void:
	var tw := create_tween()
	tw.tween_property(_music, "volume_db", -26.0 if on else -15.0, 0.25)
