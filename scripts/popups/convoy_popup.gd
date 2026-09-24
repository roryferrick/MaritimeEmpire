class_name ConvoyPopup
extends AnchoredPopup
## Opened by clicking a convoy canal (or one of its anchorages) on the map: the
## time to the next convoys, and for each direction the ships at anchor (and
## any waiting for toll money), the convoy ships waiting their turn to enter,
## and the convoy under way. Refreshes a few times a second.

const REFRESH_SECONDS := 0.25
const FONT_SIZE := 15

## Set before adding to the tree.
var canal_id := ""

var _body := VBoxContainer.new()
var _clock := 0.0


func _init() -> void:
	theme_type_variation = &"MapPopup"
	custom_minimum_size = Vector2(400, 0)


func _ready() -> void:
	super()
	var canal := GameData.get_canal(canal_id)
	var content := VBoxContainer.new()
	content.add_theme_constant_override(&"separation", 8)
	add_child(content)
	var header := HBoxContainer.new()
	content.add_child(header)
	var title := Label.new()
	title.theme_type_variation = &"HeaderLabel"
	title.text = canal.name
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	var close := Button.new()
	close.text = "X"
	close.flat = true
	close.pressed.connect(queue_free)
	header.add_child(close)
	_add_to(content, "Convoys every %s each way · %d%% speed · toll %d%% of a leg's pay · +%d%% XP" % [
		Fmt.duration(float(canal.get("convoy_interval_s", 90))), roundi(float(canal.get("speed_factor", 1.0)) * 100.0),
		roundi(float(canal.get("toll_share", 0.0)) * 100.0), roundi(float(canal.get("xp_bonus", 0.0)) * 100.0)], &"DimLabel")
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


func _refresh() -> void:
	for child in _body.get_children():
		_body.remove_child(child)
		child.queue_free()
	var canal := GameData.get_canal(canal_id)
	var traffic := GameState.canal_traffic
	var directions: Array = canal.get("directions", ["Forward", "Back"])
	var anchorages: Array = canal.get("anchorage_names", ["Anchorage", "Anchorage"])
	_add("Next convoys leave in %s" % Fmt.duration(ceilf(traffic.next_convoy_in(canal))))
	for forward: bool in [true, false]:
		_body.add_child(HSeparator.new())
		_add(directions[0 if forward else 1], &"DimLabel")
		var anchored := traffic.anchored_ships(canal, forward)
		var paying := anchored.filter(func(ship: Ship) -> bool: return ship.canal_state != Ship.CANAL_TOLL)
		var broke := anchored.filter(func(ship: Ship) -> bool: return ship.canal_state == Ship.CANAL_TOLL)
		_add("%s: %s" % [anchorages[0 if forward else 1], _names(paying) if not paying.is_empty() else "no one waiting"])
		if not broke.is_empty():
			_add("Waiting for toll money: %s" % _names(broke), &"ErrorLabel")
		var entering := traffic.released_ships(canal, forward)
		if not entering.is_empty():
			_add("Entering: %s" % _names(entering))
		var under_way := traffic.convoy_ships(canal, forward)
		_add("Under way: %s" % (_names(under_way) if not under_way.is_empty() else "none"))
	reset_size.call_deferred()


static func _names(ships: Array) -> String:
	return ", ".join(PackedStringArray(ships.map(func(ship: Ship) -> String: return ship.name)))


func _add(text: String, variation := &"") -> void:
	_add_to(_body, text, variation)


func _add_to(parent: Node, text: String, variation := &"") -> void:
	var label := Label.new()
	label.text = text
	label.theme_type_variation = variation
	label.add_theme_font_size_override(&"font_size", FONT_SIZE)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	parent.add_child(label)
