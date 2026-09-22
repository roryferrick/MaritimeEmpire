class_name AnchoredPopup
extends PanelContainer
## A popup placed just above a point, or below it if there's no room above.
## Kept inside its parent's rect.

## Returns the global point to sit next to. Called every frame, so the popup
## follows moving things like ships and panned ports.
var follow := Callable()
## Distance between the point and the popup's edge.
var gap := 26.0

var _anchor := Vector2.ZERO  # In parent-local coordinates.


func _ready() -> void:
	resized.connect(_reposition)
	_update_follow()


func _process(_delta: float) -> void:
	_update_follow()


func _update_follow() -> void:
	if not follow.is_valid():
		return
	var parent := get_parent() as Control
	var point: Vector2 = parent.get_global_transform().affine_inverse() * follow.call()
	if point != _anchor:
		_anchor = point
		_reposition()


func _reposition() -> void:
	var area := (get_parent() as Control).size
	var pos := Vector2(_anchor.x - size.x / 2.0, _anchor.y - gap - size.y)
	if pos.y < 0.0:
		pos.y = _anchor.y + gap
	pos.x = clampf(pos.x, 0.0, maxf(0.0, area.x - size.x))
	pos.y = clampf(pos.y, 0.0, maxf(0.0, area.y - size.y))
	position = pos
