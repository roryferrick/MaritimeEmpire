# Copyright (c) 2026 Rory Ferrick. All rights reserved. Maritime Empire.
extends Node
## The soundtrack: four Creative Commons tracks (audio/music, credited in
## audio/CREDITS.md and on the Licences page) played in order from the moment
## the game opens, round and round, through the title screen, the game and the
## pause menu alike. "Voyage of Discovery" is first: it's the game's theme. The
## music has its own "Music" bus (Settings.VOLUMES: the Audio settings' Music
## slider), under Master like the rest of the sound.

## The tracks in playing order: [file, title, author].
const TRACKS := [
	["res://audio/music/voyage_of_discovery.mp3", "Voyage of Discovery", "Shane Ivers"],
	["res://audio/music/the_great_sea.mp3", "The Great Sea", "Scott Buckley"],
	["res://audio/music/the_krakens_pursuit.mp3", "The Kraken's Pursuit", "Shane Ivers"],
	["res://audio/music/exploring_the_ocean.ogg", "Exploring the Ocean", "Leonardo Paz"],
]
## A breath between one track and the next (seconds).
const GAP_S := 4.0

## The track that started playing (its place in TRACKS).
signal track_started(index: int)

var _player := AudioStreamPlayer.new()
var _index := -1


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS  # (Plays on behind the pause menu.)
	_player.bus = &"Music"
	_player.finished.connect(_on_finished)
	add_child(_player)
	play_next()


## The track playing now, or {} between tracks: {title, author, index}.
func now_playing() -> Dictionary:
	if _index < 0 or not _player.playing:
		return {}
	return {title = TRACKS[_index][1], author = TRACKS[_index][2], index = _index}


## Plays the next track of the list (the first after the last).
func play_next() -> void:
	for n in TRACKS.size():  # (A track that won't load is skipped.)
		_index = (_index + 1) % TRACKS.size()
		var path := str(TRACKS[_index][0])
		var stream := _load(path)
		if stream == null:
			push_warning("Music: can't load " + path)
			continue
		_player.stream = stream
		_player.play()
		track_started.emit(_index)
		return


func _on_finished() -> void:
	var timer := get_tree().create_timer(GAP_S, true, false, true)
	timer.timeout.connect(play_next)


## The track as imported, or straight from the file when it isn't imported yet
## (a run from the command line before the editor has seen the file).
func _load(path: String) -> AudioStream:
	if ResourceLoader.exists(path):
		return load(path) as AudioStream
	if not FileAccess.file_exists(path):
		return null
	if path.ends_with(".mp3"):
		return AudioStreamMP3.load_from_file(path)
	if path.ends_with(".ogg"):
		return AudioStreamOggVorbis.load_from_file(path)
	return null
