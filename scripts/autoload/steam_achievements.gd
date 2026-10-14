# Copyright (c) 2026 Rory Ferrick. All rights reserved. Maritime Empire.
extends Node
## Steam achievements: every in-game achievement (Achievements: each star of
## a line and each badge) is a Steam achievement too, unlocked on Steam the
## moment it's earned (and all of a company's again when its save loads), and
## on top of them this player's own (EXTRAS: things that span games, such as
## founding a second company, or a first Trans Atlantic). Those are kept on
## this computer (user://player_stats.json: what's unlocked, games founded,
## models bought, seconds played) and shown like the others (cards and the
## activity log: see WorldScreen._check_achievements()).
##
## Steam side: the achievements have to exist on the Steamworks partner site
## (Stats & Achievements) under the game's own app id, with these API names
## (api_name(); tools/export_steam_achievements.gd writes them all out as a
## CSV to copy in). Until then setAchievement() fails quietly and everything
## works as it does without Steam.

## The Hidden gems line's stars on Steam (hidden there until earned).
const GEM_DESCRIPTIONS := ["Find a hidden gem", "Find two hidden gems", "Find all three hidden gems"]
## This player's own achievements: [id, name, what it takes].
const EXTRAS := [
	["here_we_go_again", "Here we go again", "Found your second company"],
	["the_game_starts_now", "The game starts now", "Buy your first Trans Atlantic"],
	["top_of_the_line", "Top of the line", "Buy a Dominator"],
	["call_the_mammoth", "Call the Mammoth", "Buy a Mammoth"],
	["dressed_for_the_occasion", "Dressed for the occasion", "Give a ship a skin"],
	["full_wardrobe", "Full wardrobe", "Own every skin of a skin pack"],
	["old_salt", "Old salt", "Play for ten hours in all"],
	["night_watch", "Night watch", "Play between midnight and four in the morning"],
	["the_more_the_merrier", "The more the merrier", "Play a multiplayer game"],
	["lake_bugs", "Lake bugs", "Deliver crayfish from the Great Lakes"],
	["captain_of_everything", "Captain of everything", "Earn every star and badge with one company"],
]
const PATH := "user://player_stats.json"
const OLD_SALT_SECONDS := 10.0 * 3600.0
const SAVE_EVERY_S := 60.0
## Ships bought that count: model id -> the extra it earns.
const MODEL_EXTRAS := {model_4 = "the_game_starts_now", model_5 = "top_of_the_line", model_6 = "call_the_mammoth"}

var unlocked: Array = []
var games_created := 0
var models_bought: Array = []
var seconds_played := 0.0
var _unsaved := 0.0
var _steam: Object = null
var _synced := {}  # API names set on Steam this run.


func _ready() -> void:
	_load()
	_hook_steam.call_deferred()


func _process(delta: float) -> void:
	if not GameState.in_session:
		return
	seconds_played += delta
	_unsaved += delta
	if _unsaved >= SAVE_EVERY_S:
		_save()


func _hook_steam() -> void:
	_steam = Net.steam
	if _steam != null:
		for id: String in unlocked:
			_set_on_steam(api_name(id))


func _load() -> void:
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH)) if FileAccess.file_exists(PATH) else null
	if data is Dictionary:
		unlocked = data.get("unlocked", []) if data.get("unlocked", []) is Array else []
		games_created = int(data.get("games_created", 0))
		models_bought = data.get("models_bought", []) if data.get("models_bought", []) is Array else []
		seconds_played = float(data.get("seconds_played", 0.0))


func _save() -> void:
	_unsaved = 0.0
	var file := FileAccess.open(PATH, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify({unlocked = unlocked, games_created = games_created, models_bought = models_bought, seconds_played = seconds_played}, "\t"))


# --- The catalog -----------------------------------------------------------------

## The Steam API name of an achievement: a line's star "DELIVER_COFFEE_2", a
## badge "FIRST_HUB", an extra "HERE_WE_GO_AGAIN".
static func api_name(id: String, stars := 0) -> String:
	var name := id.to_upper()
	return "%s_%d" % [name, stars] if stars > 0 else name


## Every Steam achievement: [{api, name, description, hidden}], the in-game
## lines' stars and badges first, then the extras.
static func catalog() -> Array:
	var out := []
	for line: Dictionary in Achievements.lines():
		for k in 3:
			out.append({api = api_name(str(line.id), k + 1), name = "%s %s" % [line.name, "★".repeat(k + 1)],
				description = GEM_DESCRIPTIONS[k] if line.id == "hidden_gems" else "%s %s" % [Fmt.thousands(int(line.stars[k])), line.unit],
				hidden = line.id == "hidden_gems"})
	for badge: Array in Achievements.BADGES:
		out.append({api = api_name(str(badge[0])), name = str(badge[1]), description = str(badge[2]), hidden = false})
	for extra: Array in EXTRAS:
		out.append({api = api_name(str(extra[0])), name = str(extra[1]), description = str(extra[2]), hidden = false})
	return out


# --- Earning ---------------------------------------------------------------------

## An in-game achievement earned (or loaded with its company): set on Steam.
func earned_ingame(id: String, stars: int) -> void:
	if stars > 0:
		for k in stars:  # (The stars below it too: a save from before, or a jump of two.)
			_set_on_steam(api_name(id, k + 1))
	else:
		_set_on_steam(api_name(id))


## Every achievement a company has, set on Steam (when its save loads).
func sync_company(company: Company) -> void:
	for id: String in company.achievements:
		earned_ingame(id, int(company.achievements[id]) if _is_line(id) else 0)


static func _is_line(id: String) -> bool:
	for line: Dictionary in Achievements.lines():
		if line.id == id:
			return true
	return false


## Looks for this player's own achievements newly earned: [{id, name, stars 0}].
func check(company: Company) -> Array:
	var news := []
	var hour := int(Time.get_time_dict_from_system().hour)
	for extra: Array in EXTRAS:
		var id: String = extra[0]
		if unlocked.has(id):
			continue
		var done := false
		match id:
			"here_we_go_again":
				done = games_created >= 2
			"the_game_starts_now", "top_of_the_line", "call_the_mammoth":
				done = models_bought.has(_model_for(id))
			"dressed_for_the_occasion":
				done = Cosmetics.wears_any() or GameState.fleet(company).any(func(ship: Ship) -> bool: return not ship.skin.is_empty() and ship.skin != "base")
			"full_wardrobe":
				for pack: Dictionary in Cosmetics.catalog.get("packs", []):
					if Cosmetics.owns(str(pack.id)):
						done = true
			"old_salt":
				done = seconds_played >= OLD_SALT_SECONDS
			"night_watch":
				done = hour < 4
			"the_more_the_merrier":
				done = Net.is_online()
			"lake_bugs":
				done = int(company.delivered.get("crayfish", 0)) > 0
			"captain_of_everything":
				var score := Achievements.score(company)
				done = score.y > 0 and score.x >= score.y
		if done:
			unlock(id)
			news.append({id = id, name = str(extra[1]), stars = 0})
	return news


static func _model_for(extra_id: String) -> String:
	for model_id: String in MODEL_EXTRAS:
		if MODEL_EXTRAS[model_id] == extra_id:
			return model_id
	return ""


func unlock(id: String) -> void:
	if unlocked.has(id):
		return
	unlocked.append(id)
	_save()
	_set_on_steam(api_name(id))


## A game founded (GameState.new_game()).
func note_game_created() -> void:
	games_created += 1
	_save()


## A ship bought for this player's company (GameState.buy_ship()).
func note_ship_bought(model_id: String) -> void:
	if not models_bought.has(model_id):
		models_bought.append(model_id)
		_save()


func _set_on_steam(api: String) -> void:
	if _steam == null or _synced.has(api) or not _steam.has_method("setAchievement"):
		return
	_synced[api] = true
	if _steam.setAchievement(api) and _steam.has_method("storeStats"):
		_steam.storeStats()
