class_name GemPopup
extends AnchoredPopup
## The hidden gem: opened by clicking the company name in the top bar (once per
## company, see GameState.claim_hidden_gem()). "Claim" adds the money and closes it.


func _init() -> void:
	theme_type_variation = &"MapPopup"
	custom_minimum_size = Vector2(320, 0)
	gap = 8.0


func _ready() -> void:
	super()
	var content := VBoxContainer.new()
	content.add_theme_constant_override(&"separation", 10)
	add_child(content)
	var title := Label.new()
	title.theme_type_variation = &"HeaderLabel"
	title.text = "You found a hidden gem!"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	content.add_child(title)
	var claim := Button.new()
	claim.text = "Claim %s" % Fmt.money(GameState.HIDDEN_GEM_MONEY)
	claim.custom_minimum_size = Vector2(0, 40)
	claim.pressed.connect(func() -> void:
		GameState.claim_hidden_gem()
		queue_free())
	content.add_child(claim)
