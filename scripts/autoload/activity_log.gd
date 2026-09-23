extends Node
## Messages about what's happening in the game (deliveries, breakdowns,
## level-ups...), shown newest first in the activity log panel on the left of
## the game screen. Keeps the newest MAX_ENTRIES for the current session.

## A message was added: {text, kind (Kind), color (the ship's map color, or
## transparent for none), time (GameState.play_time)}.
signal entry_added(entry: Dictionary)
signal cleared

## GOOD entries are highlighted green, BAD ones red.
enum Kind { INFO, GOOD, BAD }

const MAX_ENTRIES := 100

var entries: Array[Dictionary] = []


## color: the text color, usually the ship's map color (see ship_color()).
func add(text: String, kind := Kind.INFO, color := Color.TRANSPARENT) -> void:
	var entry := {text = text, kind = kind, color = color, time = GameState.play_time}
	entries.append(entry)
	if entries.size() > MAX_ENTRIES:
		entries.pop_front()
	entry_added.emit(entry)


func clear() -> void:
	entries.clear()
	cleared.emit()


## A ship's map color, for coloring messages about it.
static func ship_color(ship: Ship) -> Color:
	return Color.from_string(ship.model().get("map_color", "#ffffff"), Color.WHITE)
