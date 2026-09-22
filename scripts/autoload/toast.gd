extends CanvasLayer
## Small notification messages that stack above the bottom nav and fade out.

const DURATION := 3.0
const FADE_TIME := 0.4
const BOTTOM_MARGIN := 90.0

var _stack := VBoxContainer.new()


func _ready() -> void:
	layer = 50
	_stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stack.alignment = BoxContainer.ALIGNMENT_END
	_stack.anchor_left = 0.5
	_stack.anchor_right = 0.5
	_stack.anchor_top = 1.0
	_stack.anchor_bottom = 1.0
	_stack.offset_top = -BOTTOM_MARGIN
	_stack.offset_bottom = -BOTTOM_MARGIN
	_stack.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_stack.grow_vertical = Control.GROW_DIRECTION_BEGIN
	add_child(_stack)


func show_message(text: String) -> void:
	var panel := PanelContainer.new()
	panel.theme_type_variation = &"ToastPanel"
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	panel.add_child(label)
	_stack.add_child(panel)

	var tween := panel.create_tween()
	tween.tween_interval(DURATION)
	tween.tween_property(panel, "modulate:a", 0.0, FADE_TIME)
	tween.tween_callback(panel.queue_free)
