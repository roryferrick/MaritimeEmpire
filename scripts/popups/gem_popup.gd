# Copyright (c) 2026 Rory Ferrick. All rights reserved. Maritime Empire.
class_name GemPopup
extends AnchoredPopup
## A hidden gem (GameState.HIDDEN_GEMS): opened by clicking its spot on the map
## (the Great Pyramid of Giza, Oregon, the Talkeetna Mountains), once per
## company, see GameState.claim_hidden_gem(). "Claim" adds the money and
## closes it, then calls claimed (the pyramid's wonder popup opens after it).

var gem_id := ""
var claimed := Callable()


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
	var found := GameState.company.hidden_gems.size() + 1
	var where := Label.new()
	where.theme_type_variation = &"DimLabel"
	where.text = "Hidden in %s · %d of %d" % [GameState.HIDDEN_GEMS[gem_id].name, found, GameState.HIDDEN_GEMS.size()]
	where.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	content.add_child(where)
	var claim := Button.new()
	claim.text = "Claim %s" % Fmt.money(GameState.HIDDEN_GEM_MONEY)
	claim.custom_minimum_size = Vector2(0, 40)
	claim.pressed.connect(func() -> void:
		GameState.claim_hidden_gem(gem_id)
		queue_free()
		if claimed.is_valid():
			claimed.call())
	content.add_child(claim)
