extends Node
## Messages about what's happening in the game (deliveries, breakdowns,
## level-ups...), shown newest first in the activity log panel on the left of
## the game screen. Keeps the newest MAX_ENTRIES for the current session.

## A message was added: {text, kind (Kind), time (GameState.play_time)}.
signal entry_added(entry: Dictionary)
signal cleared

## GOOD entries show in green, BAD ones in red.
enum Kind { INFO, GOOD, BAD }

const MAX_ENTRIES := 100

var entries: Array[Dictionary] = []


func add(text: String, kind := Kind.INFO) -> void:
	var entry := {text = text, kind = kind, time = GameState.play_time}
	entries.append(entry)
	if entries.size() > MAX_ENTRIES:
		entries.pop_front()
	entry_added.emit(entry)


func clear() -> void:
	entries.clear()
	cleared.emit()
