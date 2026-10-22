# Copyright (c) 2026 Rory Ferrick. All rights reserved. Maritime Empire.
class_name HoverCards
extends Control
## Nested hover cards (CK3-style tooltips; DESIGN_LIVING_WORLD.md M1): a
## control attached with attach() shows a card beside it after DELAY_S under
## the mouse, built then by its builder (a Callable returning a Control). The
## card stays while the mouse is over it or its source, and lines inside the
## card may be attached too, opening their own cards beside them: a stack of
## levels, the deeper ones closing as the mouse leaves them (GRACE_S after).
## One layer over the whole game (GameRoot adds it); find() from any node.

const GROUP := &"hover_cards"
const DELAY_S := 0.35
const GRACE_S := 0.25
const GAP := 6.0
const MARGIN := 8.0

var _levels: Array = []  # [{source: Control, card: PanelContainer}], shallowest first.
var _pending: Control = null
var _pending_for := 0.0
var _grace := 0.0


static func find(from: Node) -> HoverCards:
	return from.get_tree().get_first_node_in_group(GROUP) as HoverCards


## Gives a control a hover card: `builder` returns the card's content (a
## Control; its lines may be attached in turn) when it opens.
static func attach(control: Control, builder: Callable) -> void:
	if control.mouse_filter == Control.MOUSE_FILTER_IGNORE:
		control.mouse_filter = Control.MOUSE_FILTER_PASS
	control.set_meta(&"hover_card", builder)
	control.mouse_entered.connect(func() -> void:
		var layer := find(control)
		if layer != null:
			layer._enter(control))
	control.mouse_exited.connect(func() -> void:
		var layer := find(control)
		if layer != null:
			layer._exit(control))


func _ready() -> void:
	add_to_group(GROUP)
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	mouse_filter = MOUSE_FILTER_IGNORE


func _enter(control: Control) -> void:
	_pending = control
	_pending_for = 0.0


func _exit(control: Control) -> void:
	if _pending == control:
		_pending = null


func _process(delta: float) -> void:
	if _pending != null:
		if not is_instance_valid(_pending) or not _pending.is_visible_in_tree():
			_pending = null
		else:
			_pending_for += delta
			if _pending_for >= DELAY_S:
				_open(_pending)
				_pending = null
	if _levels.is_empty():
		return
	var mouse := get_global_mouse_position()
	var deepest := -1
	for i in _levels.size():
		var level: Dictionary = _levels[i]
		var source: Control = level.source
		var card: Control = level.card
		if not is_instance_valid(source) or not source.is_visible_in_tree():
			_close_from(i)
			return
		if Rect2(source.global_position, source.size).has_point(mouse) or Rect2(card.global_position, card.size).has_point(mouse):
			deepest = i
	if deepest < 0:
		_grace += delta
		if _grace >= GRACE_S:
			_close_from(0)
	else:
		_grace = 0.0
		if deepest + 1 < _levels.size():
			_grace_deeper += delta
			if _grace_deeper >= GRACE_S:
				_close_from(deepest + 1)
		else:
			_grace_deeper = 0.0
var _grace_deeper := 0.0


## Opens a source's card: at the level below the card it sits in (closing any
## deeper), beside it, kept on screen.
func _open(source: Control) -> void:
	var builder: Callable = source.get_meta(&"hover_card", Callable())
	if not builder.is_valid():
		return
	var depth := 0
	for i in _levels.size():
		if (_levels[i].card as Control).is_ancestor_of(source):
			depth = i + 1
	_close_from(depth)
	var content: Control = builder.call()
	if content == null:
		return
	var card := PanelContainer.new()
	card.theme_type_variation = &"TooltipPanel"
	card.mouse_filter = MOUSE_FILTER_STOP
	card.add_child(content)
	add_child(card)
	_levels.append({source = source, card = card})
	_grace = 0.0
	_grace_deeper = 0.0
	# Beside the source: to its right, or its left when there's no room; below it when there's room neither side.
	await get_tree().process_frame  # (Its size, once laid out.)
	if not is_instance_valid(card) or not is_instance_valid(source):
		return
	var rect := Rect2(source.global_position, source.size)
	var area := get_viewport_rect().size
	var at := Vector2(rect.end.x + GAP, rect.position.y)
	if at.x + card.size.x > area.x - MARGIN:
		at.x = rect.position.x - GAP - card.size.x
	if at.x < MARGIN:
		at = Vector2(clampf(rect.position.x, MARGIN, area.x - card.size.x - MARGIN), rect.end.y + GAP)
	at.y = clampf(at.y, MARGIN, maxf(area.y - card.size.y - MARGIN, MARGIN))
	card.global_position = at


func _close_from(level: int) -> void:
	while _levels.size() > level:
		var top: Dictionary = _levels.pop_back()
		if is_instance_valid(top.card):
			(top.card as Node).queue_free()
	_grace = 0.0
	_grace_deeper = 0.0


## Closes every card (a screen changing under them).
func close_all() -> void:
	_close_from(0)
	_pending = null
