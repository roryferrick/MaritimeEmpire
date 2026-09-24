class_name LockPopup
extends AnchoredPopup
## Opened by clicking a canal lock on the map: for each direction, the ship in
## each chamber (rising or lowering, and how long it has left) and the ships
## waiting in line for the lock. Refreshes a few times a second.

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
	_add_to(content, "%s · %d chamber%s, %s s each · a lane each way" % [canal.name, chambers.size(),
		"" if chambers.size() == 1 else "s", Fmt.thousands(int(canal.get("step_seconds", 3)))], &"DimLabel")
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


func _refresh() -> void:
	for child in _body.get_children():
		_body.remove_child(child)
		child.queue_free()
	var canal := GameData.get_canal(canal_id)
	var directions: Array = canal.get("directions", ["Forward", "Back"])
	for forward: bool in [true, false]:
		if not forward:
			_body.add_child(HSeparator.new())
		_add(directions[0] if forward else directions[1], &"DimLabel")
		var chambers := _chambers()
		if not forward:
			chambers.reverse()
		for i in chambers.size():
			_add("Chamber %d: %s" % [i + 1, _chamber_text(canal, chambers[i], forward)])
		var line := GameState.chamber_line(canal_id, chambers[0].index, forward)
		if line.is_empty():
			_add("No one waiting", &"DimLabel")
		else:
			_add("Waiting: %s" % ", ".join(PackedStringArray(line.map(func(ship: Ship) -> String: return ship.name))))
	reset_size.call_deferred()


func _chamber_text(canal: Dictionary, chamber: Dictionary, forward: bool) -> String:
	var ship := GameState.chamber_ship(canal_id, chamber.index, forward)
	if ship == null:
		return "empty"
	if ship.lock_chamber().get("index", -1) != chamber.index:
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
