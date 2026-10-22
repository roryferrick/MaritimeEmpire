# Copyright (c) 2026 Rory Ferrick. All rights reserved. Maritime Empire.
class_name Progression
## Company types (game_config company_types) and which ship models a company
## may buy: every model of the types it has (its divisions: one founded with
## it, the rest bought, GameState.choose_company_type()), and the service
## ships (tugs, recovery boats, icebreakers) every company may buy.


# --- Company types -------------------------------------------------------------

## (Not the coming_soon ones: see upcoming_types().)
## The company types (game_config company_types types): {id, name, tab, categories, color, blurb}.
static func company_types() -> Array:
	return GameData.config.get("company_types", {}).get("types", []).filter(func(each: Dictionary) -> bool: return not each.get("coming_soon", false))


## The types a company can be founded as: not the pick_only ones (Research: only as a division).
static func start_types() -> Array:
	return company_types().filter(func(each: Dictionary) -> bool: return not each.get("pick_only", false))


## The company types not playable yet (game_config company_types coming_soon).
static func upcoming_types() -> Array:
	return GameData.config.get("company_types", {}).get("types", []).filter(func(each: Dictionary) -> bool: return each.get("coming_soon", false))


static func company_type(type_id: String) -> Dictionary:
	for each: Dictionary in GameData.config.get("company_types", {}).get("types", []):  # (Coming-soon ones too.)
		if each.id == type_id:
			return each
	return {}


## A type's name ("" for an unknown type).
static func type_name(type_id: String) -> String:
	return str(company_type(type_id).get("name", ""))


## The company type a ship category belongs to ("" for recovery boats, tugs and icebreakers).
static func type_of_category(category: String) -> String:
	if _category_types.is_empty():
		for each: Dictionary in company_types():
			for each_category: String in each.categories:
				_category_types[each_category] = each.id
		_category_types[""] = ""
	return str(_category_types.get(category, ""))
static var _category_types := {}


static func type_of_model(model: Dictionary) -> String:
	return type_of_category(str(model.get("category", "")))


## The company type whose ships carry a commodity ("" if none): by the models
## that carry it (a seafood family by the seafood carriers, so a catch counts as Seafood).
static func type_of_commodity(commodity_id: String) -> String:
	if _commodity_types.is_empty():
		for model: Dictionary in GameData.ship_models:
			for each: String in model.get("cargo", []):
				if not _commodity_types.has(each):
					_commodity_types[each] = type_of_model(model)
		_commodity_types[""] = ""
	return str(_commodity_types.get(commodity_id, ""))
static var _commodity_types := {}


## True if a company (this player's if null) may buy a model: one of its
## types' models, or a service ship (no type).
static func can_buy_model(model: Dictionary, company: Company = null) -> bool:
	company = company if company != null else GameState.company
	var type_id := type_of_model(model)
	return type_id.is_empty() or company == null or company.has_type(type_id)
