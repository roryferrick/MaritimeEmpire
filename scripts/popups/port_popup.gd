class_name PortPopup
extends AnchoredPopup
## Shows a port's name and the player's ships docked there.

## Set before adding to the tree.
var port_id := ""


func _ready() -> void:
	super()
	var port := GameData.get_port(port_id)
	%TitleLabel.text = port.get("name", port_id)
	%CloseButton.pressed.connect(queue_free)
	# Docked ships get listed in ShipList once ships exist.
	%NoShipsLabel.visible = %ShipList.get_child_count() == 0
