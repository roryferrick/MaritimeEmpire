# Copyright (c) 2026 Rory Ferrick. All rights reserved. Maritime Empire.
extends Node
## Cosmetics: the skin packs (data/skin_packs.json) and this player's Sand
## Dollars, the in-game currency that buys them (one Sand Dollar is one cent;
## bought in bundles with Steam money through the Steam Inventory Service,
## see buy_bundle()). Skins are sold one at a time (a ship skin covers the
## models it fits; an outfit is a human skin: its CEO and captain options,
## crew hat and uniform colours), or every ship skin of a pack, every outfit
## of a pack, or the whole pack (prices in the catalog; a bundle never charges
## for skins already owned). What's owned, which pack's skins the ships wear
## and the balance are this computer's (user://cosmetics.json), not a save's.
## An owned outfit unlocks its options in Found Company (see allowed()), its
## hat and colours on the Uniforms page (CrewLooks); an owned ship skin is
## worn by the player's own ships while its pack is the one worn (ship_skin();
## other players' ships are drawn as they are).

signal changed
## A line for the Shop to show (a purchase's progress, or why it couldn't be made).
signal message(text: String)

const CATALOG_PATH := "res://data/skin_packs.json"
const PROFILE_PATH := "user://cosmetics.json"
const SKIN_ART_DIR := "res://art/skins/"
## Where the packs' options start in Characters.PARTS: the options before
## these are everyone's (see allowed()).
const PACK_OPTIONS_FROM := {top = 18, bottoms = 12, shoes = 10, headwear = 21, facial_hair = 10}
## The outfit parts an outfit may unlock (Characters.PARTS keys).
const OUTFIT_PARTS := ["top", "bottoms", "shoes", "headwear", "facial_hair"]
## Steam Inventory results (EResult): OK.
const STEAM_OK := 1

var catalog := {}
var sand_dollars := 0
## The skins owned: "pack id/skin id" (a ship skin's id is its art's name
## without a _small/_mid/_big fit; an outfit's its id).
var owned: Array = []
## The pack whose ship skins the player's ships wear ("" for none).
var equipped := ""
## Every grant and purchase: {at (unix time), kind, amount, note}.
var ledger: Array = []
var _skins := {}  # pack id -> {model id -> Texture2D}
var _option_items := {}  # "key/option name" -> [skin keys that unlock it], worked out once.
var _steam: Object = null
var _buying := ""  # The bundle id a Steam purchase is under way for.
var _consuming := {}  # Steam result handle -> bundle, for bundles being consumed into Sand Dollars.


func _ready() -> void:
	_load_catalog()
	_load_profile()
	_hook_steam.call_deferred()


func _load_catalog() -> void:
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(CATALOG_PATH)) if FileAccess.file_exists(CATALOG_PATH) else null
	catalog = data if data is Dictionary else {packs = [], bundles = [], currency = {}, prices = {}}
	_option_items.clear()
	for it: Dictionary in catalog.get("packs", []):
		for outfit: Dictionary in it.get("outfits", []):
			var key := skin_key(str(it.id), str(outfit.id))
			for part: String in OUTFIT_PARTS:
				for option_name: String in outfit.get(part, []):
					_option_items.get_or_add("%s/%s" % [part, option_name], []).append(key)


func _load_profile() -> void:
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(PROFILE_PATH)) if FileAccess.file_exists(PROFILE_PATH) else null
	if data is Dictionary:
		sand_dollars = maxi(int(data.get("sand_dollars", 0)), 0)
		owned = []
		for id: Variant in data.get("owned", []):
			var key := str(id)
			if not pack(key).is_empty():  # (A whole pack, as profiles held before skins were sold one by one.)
				for skin_id: String in skin_ids(key):
					_own(skin_key(key, skin_id))
			elif _is_skin(key):
				_own(key)
		equipped = str(data.get("equipped", ""))
		if not wearable(equipped):
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


## The packs on sale now (and any with a skin owned, on sale or not).
func packs_for_sale() -> Array:
	var out := []
	for it: Dictionary in catalog.get("packs", []):
		if bool(it.get("on_sale", true)) or owned_count(str(it.id)) > 0:
			out.append(it)
	return out


func pack(id: String) -> Dictionary:
	for it: Dictionary in catalog.get("packs", []):
		if str(it.id) == id:
			return it
	return {}


func bundles() -> Array:
	return catalog.get("bundles", [])


## A price from the catalog ("skin", "all_ships", "all_humans", "pack").
func price(kind: String) -> int:
	return int((catalog.get("prices", {}) as Dictionary).get(kind, 100))


static func skin_key(pack_id: String, skin_id: String) -> String:
	return pack_id + "/" + skin_id


## A ship skin's id from its art's name: the name without its fit.
static func ship_skin_id(art_name: String) -> String:
	for fit: String in ["_small", "_mid", "_big"]:
		if art_name.ends_with(fit):
			return art_name.trim_suffix(fit)
	return art_name


## A pack's ship skins, in the order of its names: [{id, name, models}].
func ship_skins(pack_id: String) -> Array:
	var it := pack(pack_id)
	var names: Dictionary = it.get("ship_names", {})
	var models := {}
	for model: String in it.get("ships", {}):
		models.get_or_add(ship_skin_id(str(it.ships[model])), []).append(model)
	var out := []
	for id: String in names:
		out.append({id = id, name = str(names[id]), models = models.get(id, [])})
	return out


## A pack's outfits (human skins): the catalog's entries.
func outfits(pack_id: String) -> Array:
	return pack(pack_id).get("outfits", [])


## Every skin id of a pack: its ship skins, then its outfits.
func skin_ids(pack_id: String) -> Array:
	var out := []
	for skin: Dictionary in ship_skins(pack_id):
		out.append(str(skin.id))
	for outfit: Dictionary in outfits(pack_id):
		out.append(str(outfit.id))
	return out


func _is_skin(key: String) -> bool:
	var parts := key.split("/")
	return parts.size() == 2 and skin_ids(parts[0]).has(parts[1])


## A sum of Sand Dollars as the Shop shows it ("1,250 Sand Dollars").
func amount(sum: int) -> String:
	return "%s %s" % [Fmt.thousands(sum), currency_name(sum)]


## A sum of Sand Dollars with its money ("500 Sand Dollars ($5.00)").
func amount_money(sum: int) -> String:
	return "%s ($%.2f)" % [amount(sum), sum * int((catalog.get("currency", {}) as Dictionary).get("cents_each", 1)) / 100.0]


## A bundle's price in money, as shown ("$5.00").
static func bundle_price(bundle: Dictionary) -> String:
	return "$%.2f" % float(bundle.get("usd", 0.0))


# --- Owning, buying and wearing --------------------------------------------------

func owns_skin(pack_id: String, skin_id: String) -> bool:
	return owned.has(skin_key(pack_id, skin_id))


## True if every skin of a pack is owned.
func owns(pack_id: String) -> bool:
	var ids := skin_ids(pack_id)
	return not ids.is_empty() and owned_count(pack_id) == ids.size()


func owned_count(pack_id: String) -> int:
	var count := 0
	for skin_id: String in skin_ids(pack_id):
		if owns_skin(pack_id, skin_id):
			count += 1
	return count


## The skins of a pack not yet owned: all, "ships" or "humans".
func missing(pack_id: String, which := "all") -> Array:
	var out := []
	if which != "humans":
		for skin: Dictionary in ship_skins(pack_id):
			if not owns_skin(pack_id, str(skin.id)):
				out.append(str(skin.id))
	if which != "ships":
		for outfit: Dictionary in outfits(pack_id):
			if not owns_skin(pack_id, str(outfit.id)):
				out.append(str(outfit.id))
	return out


## What a bundle costs now: its price, or less when some of it is owned (never
## more than the missing skins one by one).
func bundle_cost(pack_id: String, which: String) -> int:
	var kind: String = {all = "pack", ships = "all_ships", humans = "all_humans"}[which]
	return mini(price(kind), missing(pack_id, which).size() * price("skin"))


## Buys one skin: "" when bought, else why not.
func buy_skin(pack_id: String, skin_id: String) -> String:
	if not _is_skin(skin_key(pack_id, skin_id)):
		return "There's no such skin."
	if owns_skin(pack_id, skin_id):
		return "You already own it."
	return _buy([skin_id], pack_id, price("skin"), skin_name(pack_id, skin_id))


## Buys every missing skin of a pack ("all"), or its ship skins ("ships") or
## outfits ("humans"): "" when bought, else why not.
func buy_bundle_of(pack_id: String, which: String) -> String:
	var ids := missing(pack_id, which)
	if ids.is_empty():
		return "You already own all of those."
	var what: String = {all = "the whole %s", ships = "every ship skin of the %s", humans = "every outfit of the %s"}[which] % str(pack(pack_id).get("title", pack_id))
	return _buy(ids, pack_id, bundle_cost(pack_id, which), what)


func _buy(ids: Array, pack_id: String, cost: int, what: String) -> String:
	if sand_dollars < cost:
		return "You need %s more." % amount(cost - sand_dollars)
	sand_dollars -= cost
	for skin_id: String in ids:
		_own(skin_key(pack_id, skin_id))
	ledger.append({at = int(Time.get_unix_time_from_system()), kind = "skins", amount = -cost, note = pack_id + ": " + ", ".join(ids)})
	if equipped.is_empty() and wearable(pack_id):
		equipped = pack_id
	_skins.erase(pack_id)
	_save_profile()
	message.emit("Bought %s for %s." % [what, amount(cost)])
	return ""


func _own(key: String) -> void:
	if not owned.has(key):
		owned.append(key)


## The name of a skin, for the Shop and the ledger.
func skin_name(pack_id: String, skin_id: String) -> String:
	for skin: Dictionary in ship_skins(pack_id):
		if str(skin.id) == skin_id:
			return str(skin.name)
	for outfit: Dictionary in outfits(pack_id):
		if str(outfit.id) == skin_id:
			return str(outfit.name)
	return skin_id


## True if a pack has a ship skin the player owns (so their ships can wear it).
func wearable(pack_id: String) -> bool:
	if pack_id.is_empty():
		return false
	for skin: Dictionary in ship_skins(pack_id):
		if owns_skin(pack_id, str(skin.id)):
			return true
	return false


## The player's ships wear a pack's owned ship skins ("" for none).
func equip(id: String) -> void:
	if not id.is_empty() and not wearable(id):
		return
	equipped = id
	_save_profile()


## The skin the player's ships of a model wear (an owned ship skin of the
## pack worn), or null.
func ship_skin(model_id: String) -> Texture2D:
	if equipped.is_empty():
		return null
	if not _skins.has(equipped):
		var it := pack(equipped)
		var skins := {}
		var ships: Dictionary = it.get("ships", {})
		for model: String in ships:
			var art := str(ships[model])
			if not owns_skin(equipped, ship_skin_id(art)):
				continue
			var path := SKIN_ART_DIR + str(it.get("folder", equipped)) + "/" + art + ".svg"
			if ResourceLoader.exists(path):
				skins[model] = load(path)
		_skins[equipped] = skins
	return (_skins[equipped] as Dictionary).get(model_id, null)


# --- Outfits and crew looks --------------------------------------------------------

## Whether a look's option may be chosen: everyone's options always, a pack's
## only when an outfit that has it is owned.
func allowed(key: String, index: int) -> bool:
	if index < int(PACK_OPTIONS_FROM.get(key, 1 << 30)):
		return true
	var items: Array = _option_items.get("%s/%s" % [key, Characters.option_name(key, index)], [])
	if items.is_empty():
		return true
	for item: String in items:
		if owned.has(item):
			return true
	return false


## The pack an option belongs to ("" for everyone's).
func pack_of_option(key: String, index: int) -> String:
	var items: Array = _option_items.get("%s/%s" % [key, Characters.option_name(key, index)], [])
	return str(items[0]).split("/")[0] if not items.is_empty() else ""


func hat_allowed(hat_name: String) -> bool:
	var index := CrewLooks.hat_index(hat_name)
	if index < int(PACK_OPTIONS_FROM.headwear):
		return true
	for it: Dictionary in catalog.get("packs", []):
		for outfit: Dictionary in it.get("outfits", []):
			if (outfit.get("crew_hats", []) as Array).has(hat_name) and owns_skin(str(it.id), str(outfit.id)):
				return true
	return false


## The uniform colours the outfits add ("shirts" or "trousers"): [[name, hex], ...],
## the owned outfits' or every outfit's.
func pack_colors(part: String, owned_only := true) -> Array:
	var out := []
	var seen := {}
	for it: Dictionary in catalog.get("packs", []):
		for outfit: Dictionary in it.get("outfits", []):
			if owned_only and not owns_skin(str(it.id), str(outfit.id)):
				continue
			for pair: Array in outfit.get(part, []):
				if not seen.has(pair[0]):
					seen[pair[0]] = true
					out.append(pair)
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


## The game's owner plays with Sand Dollars to spare: running from the editor
## (or the Godot binary), or on Steam as one of OWNER_STEAM_IDS, the balance
## is topped up to OWNER_SAND_DOLLARS at every start (a ledger line each
## time). Exported builds given to others have neither, so they get none.
const OWNER_STEAM_IDS: Array[int] = []  # (Steam ID64s. Find yours at https://store.steampowered.com/account/ under "Steam ID".)
const OWNER_SAND_DOLLARS := 10000

func _owner_grant() -> void:
	var owner := OS.has_feature("editor")
	if not owner and _steam != null and _steam.has_method("getSteamID"):
		owner = OWNER_STEAM_IDS.has(int(_steam.getSteamID()))
	if owner and sand_dollars < OWNER_SAND_DOLLARS:
		_grant(OWNER_SAND_DOLLARS - sand_dollars, "owner")


func _hook_steam() -> void:
	_steam = Net.steam
	_owner_grant()
	if _steam == null:
		return
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
