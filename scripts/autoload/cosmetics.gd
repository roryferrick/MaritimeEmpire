# Copyright (c) 2026 Rory Ferrick. All rights reserved. Maritime Empire.
extends Node
## Cosmetics: the skin packs (data/skin_packs.json) and this player's Sand
## Dollars, the in-game currency that buys them (one Sand Dollar is one cent;
## bought in bundles with Steam money through the Steam Inventory Service,
## see buy_bundle()). What's owned, what's equipped and the balance are this
## computer's (user://cosmetics.json), not a save's: skins follow the player
## into every game. A pack owned unlocks its outfits in Found Company (the
## CEO's look: see allowed()), its hats and colours on the Uniforms page
## (CrewLooks) and, equipped, its ships' skins on the player's own ships
## (ship_skin(); other players' ships are drawn as they are).

signal changed
## A line for the Shop to show (a purchase's progress, or why it couldn't be made).
signal message(text: String)

const CATALOG_PATH := "res://data/skin_packs.json"
const PROFILE_PATH := "user://cosmetics.json"
const SKIN_ART_DIR := "res://art/skins/"
## Where the packs' options start in Characters.PARTS: the options before
## these are everyone's (see allowed()).
const PACK_OPTIONS_FROM := {top = 18, bottoms = 12, shoes = 10, headwear = 21}
## Steam Inventory results (EResult): OK.
const STEAM_OK := 1

var catalog := {}
var sand_dollars := 0
var owned: Array = []
var equipped := ""
## Every grant and purchase: {at (unix time), kind, amount, note}.
var ledger: Array = []
var _skins := {}  # pack id -> {model id -> Texture2D}
var _steam: Object = null
var _buying := ""  # The bundle id a Steam purchase is under way for.
var _consuming := {}  # Steam result handle -> bundle, for bundles being consumed into Sand Dollars.


func _ready() -> void:
	_load_catalog()
	_load_profile()
	_hook_steam.call_deferred()


func _load_catalog() -> void:
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(CATALOG_PATH)) if FileAccess.file_exists(CATALOG_PATH) else null
	catalog = data if data is Dictionary else {packs = [], bundles = [], currency = {}}


func _load_profile() -> void:
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(PROFILE_PATH)) if FileAccess.file_exists(PROFILE_PATH) else null
	if data is Dictionary:
		sand_dollars = maxi(int(data.get("sand_dollars", 0)), 0)
		owned = []
		for id: Variant in data.get("owned", []):
			if pack(str(id)).size() > 0:
				owned.append(str(id))
		equipped = str(data.get("equipped", ""))
		if not owns(equipped):
			equipped = ""
		ledger = data.get("ledger", []) if data.get("ledger", []) is Array else []


func _save_profile() -> void:
	var file := FileAccess.open(PROFILE_PATH, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify({sand_dollars = sand_dollars, owned = owned, equipped = equipped, ledger = ledger}, "\t"))
	changed.emit()


# --- The catalog ---------------------------------------------------------------

func currency_name(count := 2) -> String:
	var currency: Dictionary = catalog.get("currency", {})
	return str(currency.get("singular", "Sand Dollar")) if count == 1 else str(currency.get("name", "Sand Dollars"))


## The packs on sale now (and any owned, on sale or not).
func packs_for_sale() -> Array:
	var out := []
	for pack: Dictionary in catalog.get("packs", []):
		if bool(pack.get("on_sale", true)) or owns(str(pack.id)):
			out.append(pack)
	return out


func pack(id: String) -> Dictionary:
	for pack: Dictionary in catalog.get("packs", []):
		if str(pack.id) == id:
			return pack
	return {}


func bundles() -> Array:
	return catalog.get("bundles", [])


func owns(id: String) -> bool:
	return not id.is_empty() and owned.has(id)


## A sum of Sand Dollars as the Shop shows it ("1,250 Sand Dollars").
func amount(sum: int) -> String:
	return "%s %s" % [Fmt.thousands(sum), currency_name(sum)]


## A bundle's price in money, as shown ("$5.00").
static func bundle_price(bundle: Dictionary) -> String:
	return "$%.2f" % float(bundle.get("usd", 0.0))


# --- Buying and equipping packs ---------------------------------------------------

## Buys a pack with Sand Dollars: "" when bought, else why not.
func buy_pack(id: String) -> String:
	var it := pack(id)
	if it.is_empty():
		return "There's no such pack."
	if owns(id):
		return "You already own this pack."
	var price := int(it.get("price", 0))
	if sand_dollars < price:
		return "You need %s more." % amount(price - sand_dollars)
	sand_dollars -= price
	owned.append(id)
	ledger.append({at = int(Time.get_unix_time_from_system()), kind = "pack", amount = -price, note = id})
	if equipped.is_empty():
		equipped = id
	_save_profile()
	message.emit("%s is yours." % it.title)
	return ""


## Equips a pack's ship skins ("" for none): the player's ships wear them.
func equip(id: String) -> void:
	if not id.is_empty() and not owns(id):
		return
	equipped = id
	_save_profile()


## The skin the player's ships of a model wear (the equipped pack's), or null.
func ship_skin(model_id: String) -> Texture2D:
	if equipped.is_empty():
		return null
	if not _skins.has(equipped):
		var it := pack(equipped)
		var skins := {}
		var ships: Dictionary = it.get("ships", {})
		for model: String in ships:
			var path := SKIN_ART_DIR + str(it.get("folder", equipped)) + "/" + str(ships[model]) + ".svg"
			if ResourceLoader.exists(path):
				skins[model] = load(path)
		_skins[equipped] = skins
	return (_skins[equipped] as Dictionary).get(model_id, null)


# --- Outfits and crew looks --------------------------------------------------------

## Whether a look's option may be chosen: everyone's options always, a pack's
## only when the pack is owned.
func allowed(key: String, index: int) -> bool:
	if index < int(PACK_OPTIONS_FROM.get(key, 1 << 30)):
		return true
	var pack_id := pack_of_option(key, index)
	return pack_id.is_empty() or owns(pack_id)


## The pack an option belongs to ("" for everyone's).
func pack_of_option(key: String, index: int) -> String:
	var option_name := Characters.option_name(key, index)
	for it: Dictionary in catalog.get("packs", []):
		if (it.get(key, []) as Array).has(option_name):
			return str(it.id)
	return ""


func hat_allowed(hat_name: String) -> bool:
	return allowed("headwear", CrewLooks.hat_index(hat_name))


## The uniform colours the owned packs add ("shirts" or "trousers"): [[name, hex], ...].
func pack_colors(part: String, owned_only := true) -> Array:
	var out := []
	for it: Dictionary in catalog.get("packs", []):
		if not owned_only or owns(str(it.id)):
			out.append_array(it.get(part, []))
	return out


# --- Sand Dollars through Steam --------------------------------------------------

## Starts buying a bundle of Sand Dollars through Steam: the Steam overlay's
## checkout opens for the bundle's item; once paid, the item is consumed into
## Sand Dollars (see _on_inventory_result()). Progress and problems come as
## `message`.
func buy_bundle(bundle: Dictionary) -> void:
	if _steam == null:
		message.emit("Buying %s needs Steam: start Steam and log in, then start the game again." % currency_name())
		return
	if not _steam.has_method("startPurchase"):
		message.emit("This version of the game can't buy through Steam.")
		return
	if not _buying.is_empty():
		message.emit("A purchase is already under way.")
		return
	var handle: int = _steam.startPurchase([int(bundle.get("steam_itemdef", 0))], [1])
	if handle < 0:
		message.emit("Steam couldn't start the purchase.")
		return
	_buying = str(bundle.id)
	message.emit("Steam is opening the checkout for %s (%s)..." % [amount(int(bundle.sand_dollars)), bundle_price(bundle)])


func _hook_steam() -> void:
	if Net.steam == null:
		return
	_steam = Net.steam
	for pair: Array in [["inventory_start_purchase_result", _on_start_purchase], ["micro_txn_authorization_response", _on_authorization], ["inventory_result_ready", _on_inventory_result]]:
		if _steam.has_signal(pair[0]):
			_steam.connect(pair[0], pair[1])
	if _steam.has_method("loadItemDefinitions"):
		_steam.loadItemDefinitions()
	_collect_bundles()


## Asks Steam for everything in the player's inventory: bundles bought but not
## yet turned into Sand Dollars (the game closed mid-purchase) are consumed.
func _collect_bundles() -> void:
	if _steam != null and _steam.has_method("getAllItems"):
		_steam.getAllItems()


func _on_start_purchase(result: Variant, _order_id: Variant, _transaction_id: Variant) -> void:
	if str(result) != "OK" and int(result) != STEAM_OK:
		message.emit("Steam couldn't start the purchase (%s)." % str(result))
		_buying = ""


func _on_authorization(_app_id: Variant, _order_id: Variant, authorized: bool) -> void:
	if authorized:
		message.emit("Paid. Adding your %s..." % currency_name())
		_collect_bundles()
	else:
		message.emit("The purchase was cancelled.")
	_buying = ""


func _on_inventory_result(result: Variant, handle: int) -> void:
	if int(result) != STEAM_OK:
		if _consuming.has(handle):
			message.emit("Steam couldn't hand over the %s; they'll be added next time the game starts." % currency_name())
			_consuming.erase(handle)
		return
	if _consuming.has(handle):
		var bundle: Dictionary = _consuming[handle]
		_consuming.erase(handle)
		_grant(int(bundle.sand_dollars), "steam:" + str(bundle.id))
		message.emit("%s added. You have %s." % [amount(int(bundle.sand_dollars)), amount(sand_dollars)])
	elif _steam.has_method("getResultItems"):
		for item: Dictionary in _steam.getResultItems(handle):
			var bundle := _bundle_of_itemdef(int(item.get("item_def", 0)))
			var quantity := int(item.get("quantity", 0))
			if not bundle.is_empty() and quantity > 0 and _steam.has_method("consumeItem"):
				var consume: int = _steam.consumeItem(int(item.get("item_id", 0)), quantity)
				if consume >= 0:
					var whole := bundle.duplicate()
					whole.sand_dollars = int(bundle.sand_dollars) * quantity
					_consuming[consume] = whole
	if _steam.has_method("destroyResult"):
		_steam.destroyResult(handle)


func _bundle_of_itemdef(itemdef: int) -> Dictionary:
	for bundle: Dictionary in bundles():
		if int(bundle.get("steam_itemdef", -1)) == itemdef:
			return bundle
	return {}


func _grant(sum: int, note: String) -> void:
	sand_dollars += sum
	ledger.append({at = int(Time.get_unix_time_from_system()), kind = "grant", amount = sum, note = note})
	_save_profile()
