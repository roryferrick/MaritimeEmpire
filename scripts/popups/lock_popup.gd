class_name LockPopup
extends AnchoredPopup
## Opened by clicking a canal lock on the map. A lock with a lane each way shows
## each direction's chambers (the ship in each, rising or lowering, with how
## long it has left) and its line; a shared lock shows each of its chambers
## (which way it's ready for, or turning around) and the lines both ways.
## Refreshes a few times a second.

const REFRESH_SECONDS := 0.25
const FONT_SIZE := 15

## Set before adding to the tree.
var canal_id := ""
var lock_index := 0

var _body := VBoxContainer.new()
var _clock := 0.0


func _init() -> void:
	theme_type_variation = &"MapPopup"
	custom_minimum_size = Vector2(380, 0)


func _ready() -> void:
	super()
	var canal := GameData.get_canal(canal_id)
	var lock: Dictionary = canal.locks[lock_index]
	var content := VBoxContainer.new()
	content.add_theme_constant_override(&"separation", 8)
	add_child(content)
	var header := HBoxContainer.new()
	content.add_child(header)
	var title := Label.new()
	title.theme_type_variation = &"HeaderLabel"
	title.text = lock.name
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	var close := Button.new()
	close.text = "X"
	close.flat = true
	close.pressed.connect(queue_free)
	header.add_child(close)
	var chambers := _chambers()
	var parallel := int(lock.get("parallel", 1))
	var layout := "a lane each way"
	if _shared():
		layout = "one ship at a time, either way" if parallel == 1 else "%d chambers side by side" % parallel
	var steps := "%d chamber%s" % [chambers.size(), "" if chambers.size() == 1 else "s"] if chambers.size() > 1 or parallel == 1 else "1 step"
	_add_to(content, "%s · %s, %s s each · %s" % [canal.name, steps, Fmt.thousands(int(canal.get("step_seconds", 3))), layout], &"DimLabel")
	content.add_child(HSeparator.new())
	_body.add_theme_constant_override(&"separation", 4)
	content.add_child(_body)
	_refresh()


func _process(delta: float) -> void:
	super(delta)
	_clock += delta
	if _clock >= REFRESH_SECONDS:
		_clock = 0.0
		_refresh()


## This lock's chambers, in path order.
func _chambers() -> Array:
	return GameData.get_canal(canal_id).chambers.filter(func(chamber: Dictionary) -> bool: return chamber.lock == lock_index)


func _shared() -> bool:
	return GameData.get_canal(canal_id).locks[lock_index].get("lanes", "each_way") == "shared"


func _refresh() -> void:
	for child in _body.get_children():
		_body.remove_child(child)
		child.queue_free()
	var canal := GameData.get_canal(canal_id)
	var directions: Array = canal.get("directions", ["Forward", "Back"])
	var traffic := GameState.canal_traffic
	var chambers := _chambers()
	if _shared():
		for chamber: Dictionary in chambers:
			var slots := GameData.chamber_slots(canal, chamber)
			for slot in slots:
				var label := "Chamber %s" % char(65 + int(slot)) if slots.size() > 1 else "Chamber"
				_add("%s: %s" % [label, _shared_slot_text(canal, chamber, slot, directions)])
		_body.add_child(HSeparator.new())
		for forward: bool in [true, false]:
			var first: Dictionary = chambers[0] if forward else chambers[-1]
			_add_line(traffic.line(canal_id, first.index, forward), directions[0 if forward else 1])
	else:
		for forward: bool in [true, false]:
			if not forward:
				_body.add_child(HSeparator.new())
			_add(directions[0] if forward else directions[1], &"DimLabel")
			var in_order := chambers.duplicate()
			if not forward:
				in_order.reverse()
			for i in in_order.size():
				_add("Chamber %d: %s" % [i + 1, _each_way_text(canal, in_order[i], forward)])
			_add_line(traffic.line(canal_id, in_order[0].index, forward), "")
	reset_size.call_deferred()


func _add_line(line: Array, direction: String) -> void:
	var prefix := "Waiting (%s)" % direction.split(",")[0].to_lower() if not direction.is_empty() else "Waiting"
	if line.is_empty():
		_add("%s: no one" % prefix, &"DimLabel")
	else:
		_add("%s: %s" % [prefix, ", ".join(PackedStringArray(line.map(func(ship: Ship) -> String: return ship.name)))])


func _each_way_text(canal: Dictionary, chamber: Dictionary, forward: bool) -> String:
	var ship := GameState.canal_traffic.slot_ship(canal_id, chamber.index, "f" if forward else "b")
	return _ship_text(canal, chamber, ship, forward)


func _shared_slot_text(canal: Dictionary, chamber: Dictionary, slot: String, directions: Array) -> String:
	var traffic := GameState.canal_traffic
	var ship := traffic.slot_ship(canal_id, chamber.index, slot)
	var turn := traffic.slot_turn(canal_id, chamber.index, slot)
	if ship != null and turn > 0.0:
		return "being made ready for %s (%s)" % [ship.name, Fmt.duration(ceilf(turn))]
	if ship != null:
		var forward: bool = GameData.lane_chambers(ship.from_port, ship.to_port)[ship.canal_step if ship.lock_time < 0.0 else ship.canal_step - 1].forward
		return _ship_text(canal, chamber, ship, forward)
	return "empty"


func _ship_text(canal: Dictionary, chamber: Dictionary, ship: Ship, forward: bool) -> String:
	if ship == null:
		return "empty"
	if ship.lock_chamber().get("index", -1) != chamber.index or ship.lock_chamber().canal != canal:
		return "%s coming in" % ship.name
	var step := float(canal.get("step_seconds", 3))
	if ship.lock_time >= step:
		return "%s, waiting to move on" % ship.name
	var rises: bool = canal.locks[lock_index].rises_forward == forward
	return "%s, %s (%s)" % [ship.name, "rising" if rises else "lowering", Fmt.duration(ceilf(step - ship.lock_time))]


func _add(text: String, variation := &"") -> void:
	_add_to(_body, text, variation)


func _add_to(parent: Node, text: String, variation := &"") -> void:
	var label := Label.new()
	label.text = text
	label.theme_type_variation = variation
	label.add_theme_font_size_override(&"font_size", FONT_SIZE)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	parent.add_child(label)
