class_name PortSizes
extends RefCounted
## Every port's size, 1 to 100 (see game_config port_sizes): Small, Medium,
## Large or Giant by band. Each starts at its ports.json size. It grows with
## the cargo value the player's ships load and unload there (more value
## needed the bigger it is, and never faster than max_growth_per_hour), and
## from company level shrink_from_level a port above shrink_floor slowly
## shrinks back towards it, traffic making up for the shrinking.
##
## Size sets how much the player's trades move prices there (and how fast they
## recover), what fuel and repairs cost, and which ships can dock (ship_models
## min_port). Large ports are as the game was before sizes.

## A port changed band ("medium"...), growing or shrinking into it.
signal band_changed(port_id: String, band: String, grew: bool)

## How often (game seconds) growth and shrinking are applied.
const STEP_S := 5.0
## A shrink into a lower band is only announced this far below the band it
## was announced in, so a port on a band's edge doesn't flip back and forth.
const BAND_HYSTERESIS := 1.0

var _state: Node  # GameState
var _sizes := {}  # port id -> size
## Growth earned but not yet applied (applied at up to max_growth_per_hour).
var _pending := {}  # port id -> size points
## Change over the last step, in size points per hour (not saved).
var _rates := {}  # port id -> points per hour
## The band last announced for each port (see BAND_HYSTERESIS; not saved).
var _announced := {}  # port id -> band
var _clock := 0.0


func _init(state: Node) -> void:
	_state = state


## Every port at its starting size.
func reset() -> void:
	_sizes.clear()
	_pending.clear()
	_rates.clear()
	for port: Dictionary in GameData.ports:
		_sizes[port.id] = float(port.get("size", _settings().get("normal", [51, 75])[0]))
	_announce_all()


func size(port_id: String) -> float:
	return float(_sizes.get(port_id, 51.0))


## The size as shown: a whole number, 1 to 100.
func level(port_id: String) -> int:
	return floori(size(port_id))


## "small", "medium", "large" or "giant".
func band(port_id: String) -> String:
	return band_of(size(port_id))


func band_of(value: float) -> String:
	var found := ""
	for entry: Array in _settings().get("bands", []):
		if value >= float(entry[1]):
			found = entry[0]
	return found


## The smallest size in a band.
func band_min(band_name: String) -> float:
	for entry: Array in _settings().get("bands", []):
		if entry[0] == band_name:
			return float(entry[1])
	return 1.0


## The size of the next band up (the max size + 1 in the top band).
func next_band_min(port_id: String) -> float:
	for entry: Array in _settings().get("bands", []):
		if float(entry[1]) > size(port_id):
			return float(entry[1])
	return float(_settings().get("max", 100)) + 1.0


## Size points per hour over the last few seconds: + growing, - shrinking.
func rate(port_id: String) -> float:
	return float(_rates.get(port_id, 0.0))


## Whether a ship model can dock here: its min_port band or bigger (recovery
## boats and models without one anywhere).
func fits(model: Dictionary, port_id: String) -> bool:
	var needs := str(model.get("min_port", ""))
	return needs.is_empty() or size(port_id) >= band_min(needs)


## Cargo value the player's ships loaded or unloaded here.
func add_traffic(port_id: String, value: float) -> void:
	var settings := _settings()
	var points := value / (float(settings.get("growth_value_per_point", 720000)) * size(port_id))
	_pending[port_id] = minf(float(_pending.get(port_id, 0.0)) + points, float(settings.get("max_pending", 5.0)))


## How much more (or less) the player's trades move prices here than at a
## Large port; also how much longer their effect lasts.
func impact_factor(port_id: String) -> float:
	var settings := _settings()
	return _by_size(port_id, float(settings.get("impact_at_min", 2.0)), float(settings.get("impact_at_max", 0.5)))


## Fuel and repair prices here, as a multiple of a Large port's.
func cost_factor(port_id: String) -> float:
	var settings := _settings()
	return _by_size(port_id, 1.0 + float(settings.get("costs_at_min", 0.2)), 1.0 + float(settings.get("costs_at_max", -0.2)))


## 1.0 through the normal (Large) band, going linearly to at_min at size 1 and
## at_max at the max size.
func _by_size(port_id: String, at_min: float, at_max: float) -> float:
	var settings := _settings()
	var normal: Array = settings.get("normal", [51, 75])
	var value := size(port_id)
	if value < float(normal[0]):
		return lerpf(1.0, at_min, (float(normal[0]) - value) / (float(normal[0]) - 1.0))
	if value > float(normal[1]):
		return lerpf(1.0, at_max, (value - float(normal[1])) / (float(settings.get("max", 100)) - float(normal[1])))
	return 1.0


func step(delta: float) -> void:
	_clock += delta
	if _clock < STEP_S:
		return
	var seconds := _clock
	_clock = 0.0
	var settings := _settings()
	var most := float(settings.get("max_growth_per_hour", 5.0)) * seconds / 3600.0
	var floor_size := float(settings.get("shrink_floor", 51))
	var shrink := 0.0
	if _state.company_level() >= int(settings.get("shrink_from_level", 46)):
		shrink = float(settings.get("shrink_per_hour", 0.833)) * seconds / 3600.0
	var top := float(settings.get("max", 100))
	for port_id: String in _sizes:
		var before: float = _sizes[port_id]
		var grow := minf(float(_pending.get(port_id, 0.0)), most)
		if grow > 0.0:
			_pending[port_id] = float(_pending[port_id]) - grow
		var after := minf(before + grow, top)
		if after > floor_size:
			after = maxf(after - shrink, floor_size)
		_rates[port_id] = (after - before) * 3600.0 / seconds
		if after == before:
			continue
		_sizes[port_id] = after
		_announce(port_id, after)


## Announces a port reaching a bigger band at once, and a smaller one only once
## it's BAND_HYSTERESIS below the band it was in.
func _announce(port_id: String, value: float) -> void:
	var was: String = _announced[port_id]
	var now := band_of(value)
	if now == was:
		return
	var grew := band_min(now) > band_min(was)
	if not grew and value > band_min(was) - BAND_HYSTERESIS:
		return
	_announced[port_id] = now
	band_changed.emit(port_id, now, grew)


## Every port's band as already announced (on starting or loading).
func _announce_all() -> void:
	_announced.clear()
	for port_id: String in _sizes:
		_announced[port_id] = band(port_id)


## Raises a port to at least a size (for ships already routed through it when
## sizes arrived; see GameState._fit_ports_to_routes()).
func raise_to(port_id: String, value: float) -> void:
	_sizes[port_id] = maxf(size(port_id), value)
	_announced[port_id] = band(port_id)


func to_dict() -> Dictionary:
	var out := {}
	for port_id: String in _sizes:
		out[port_id] = [_sizes[port_id], float(_pending.get(port_id, 0.0))]
	return out


## Loads saved sizes over the starting ones. Returns false for a save from
## before port sizes.
func from_dict(data: Dictionary) -> bool:
	reset()
	for port_id: String in data:
		if _sizes.has(port_id):
			var entry: Array = data[port_id]
			_sizes[port_id] = float(entry[0])
			_pending[port_id] = float(entry[1])
	_announce_all()
	return not data.is_empty()


func _settings() -> Dictionary:
	return GameData.config.get("port_sizes", {})
