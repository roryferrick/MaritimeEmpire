# Copyright (c) 2026 Rory Ferrick. All rights reserved. Maritime Empire.
extends Node
## Writes every Steam achievement the game can unlock (SteamAchievements.catalog())
## to data/steam_achievements.txt (comma separated): API name, display name, description, hidden.
## For setting them up on the Steamworks partner site (Stats & Achievements).
##   Godot --headless --path . tools/export_steam_achievements.tscn
## (A scene, not a script: it needs the autoloads.)
const OUT := "res://data/steam_achievements.txt"  # (A .csv would be imported as translations.)


func _ready() -> void:
	var file := FileAccess.open(OUT, FileAccess.WRITE)
	file.store_line("api_name,display_name,description,hidden")
	var count := 0
	for entry: Dictionary in SteamAchievements.catalog():
		file.store_csv_line(PackedStringArray([str(entry.api), str(entry.name), str(entry.description), "1" if bool(entry.hidden) else "0"]))
		count += 1
	print("%d Steam achievements written to %s" % [count, OUT])
	get_tree().quit()
