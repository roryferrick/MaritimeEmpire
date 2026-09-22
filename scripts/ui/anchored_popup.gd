class_name AnchoredPopup
extends PanelContainer
## A popup placed just above a point, or below it if there's no room above.
## Kept inside its parent's rect.

const GAP := 26.0

var _anchor := Vector2.ZERO  # In parent-local coordinates.


func _ready() -> void:
	resized.connect(_reposition)


func anchor_to(point_in_parent: Vector2) -> void:
	_anchor = point_in_parent
	_reposition()


func _reposition() -> void:
	var area := (get_parent() as Control).size
	var pos := Vector2(_anchor.x - size.x / 2.0, _anchor.y - GAP - size.y)
	if pos.y < 0.0:
		pos.y = _anchor.y + GAP
	pos.x = clampf(pos.x, 0.0, maxf(0.0, area.x - size.x))
	pos.y = clampf(pos.y, 0.0, maxf(0.0, area.y - size.y))
	position = pos
