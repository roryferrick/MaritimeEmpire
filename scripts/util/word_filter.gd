# Copyright (c) 2026 Rory Ferrick. All rights reserved. Maritime Empire.
class_name WordFilter
## Blanks inappropriate words out of text with asterisks, for the multiplayer
## filter (Net.filter_words): "you shitty boat" -> "you ****ty boat". The words
## are in data/word_filter.json, which says how they're matched.

const PATH := "res://data/word_filter.json"
const LEET := {"0": "o", "1": "i", "3": "e", "4": "a", "5": "s", "7": "t", "8": "b", "@": "a", "$": "s"}
const ENDINGS: Array[String] = ["", "s", "es", "ed", "er", "ers", "ing", "y"]

static var _parts: Array[RegEx] = []
static var _words := {}
static var _allow := {}
static var _loaded := false


## The text with every blocked word's letters (and digits) turned to *.
static func clean(text: String) -> String:
	_load()
	var out := text
	for token: PackedInt32Array in _tokens(text):
		# The token's letters as read (lowercase, leet undone), and where each came from.
		var read := ""
		var at: Array[int] = []
		for i in token:
			var c := text[i].to_lower()
			c = LEET.get(c, c)
			if c >= "a" and c <= "z":
				read += c
				at.append(i)
		if read.is_empty() or _allow.has(read):
			continue
		if _is_word(read):
			out = _mask(out, at[0], at[-1])
			continue
		for part in _parts:
			for found in part.search_all(read):
				out = _mask(out, at[found.get_start()], at[found.get_end() - 1])
	return out


## Whether the text has anything clean() would blank out.
static func is_clean(text: String) -> bool:
	return clean(text) == text


## The text's words, as the indices of their characters: split at whitespace,
## with runs of single characters ("f u c k") joined into one.
static func _tokens(text: String) -> Array[PackedInt32Array]:
	var words: Array[PackedInt32Array] = []
	var word := PackedInt32Array()
	for i in text.length() + 1:
		if i < text.length() and text[i] != " " and text[i] != "\t" and text[i] != "\n":
			word.append(i)
		elif not word.is_empty():
			words.append(word)
			word = PackedInt32Array()
	var out: Array[PackedInt32Array] = []
	for k in words.size():
		if k > 0 and words[k].size() == 1 and words[k - 1].size() == 1:
			out[-1].append_array(words[k])  # Carries on a run of single characters.
		else:
			out.append(words[k])
	return out


static func _is_word(read: String) -> bool:
	for ending in ENDINGS:
		if read.ends_with(ending) and _words.has(read.left(read.length() - ending.length())):
			return true
	return false


static func _mask(text: String, from: int, to: int) -> String:
	for i in range(from, to + 1):
		var c := text[i]
		if c != " " and (c.to_lower() != c.to_upper() or c.is_valid_int() or LEET.has(c)):
			text[i] = "*"
	return text


static func _load() -> void:
	if _loaded:
		return
	_loaded = true
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	if not data is Dictionary:
		push_error("Couldn't read %s" % PATH)
		return
	for part: String in data.get("parts", []):
		var pattern := ""
		for c in part:
			pattern += c + "+"  # Any letter doubled or more: "fuuuck".
		_parts.append(RegEx.create_from_string(pattern))
	for word: String in data.get("words", []):
		_words[word] = true
	for word: String in data.get("allow", []):
		_allow[word] = true
