extends Node
## State of the running game session, plus saving and loading.
##
## The world only advances while a session is open. The game saves on quit
## and on a timer; nothing happens while the game is closed.

signal money_changed(money: int)
signal containers_changed(total: int)

const SAVE_PATH := "user://savegame.json"
const SAVE_VERSION := 1

var money: int = 0:
	set(value):
		money = value
		money_changed.emit(money)

var containers_delivered: int = 0:
	set(value):
		containers_delivered = value
		containers_changed.emit(containers_delivered)

var in_session := false

var _autosave_timer := Timer.new()


func _ready() -> void:
	_autosave_timer.wait_time = float(GameData.config.get("autosave_seconds", 30))
	_autosave_timer.timeout.connect(save_game)
	add_child(_autosave_timer)


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		save_game()


func has_save() -> bool:
	return FileAccess.file_exists(SAVE_PATH)


func new_game() -> void:
	money = int(GameData.config.get("starting_money", 10000))
	containers_delivered = 0
	_begin_session()
	save_game()


## Loads the save file and starts a session. Returns false if it can't be read.
func continue_game() -> bool:
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(SAVE_PATH))
	if typeof(data) != TYPE_DICTIONARY:
		push_error("GameState: save file %s is missing or corrupt" % SAVE_PATH)
		return false
	money = int(data.get("money", 0))
	containers_delivered = int(data.get("containers_delivered", 0))
	_begin_session()
	return true


func save_game() -> void:
	if not in_session:
		return
	var data := {
		"version": SAVE_VERSION,
		"money": money,
		"containers_delivered": containers_delivered,
	}
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file == null:
		push_error("GameState: could not write save (%s)" % error_string(FileAccess.get_open_error()))
		return
	file.store_string(JSON.stringify(data, "\t"))


func _begin_session() -> void:
	in_session = true
	_autosave_timer.start()
