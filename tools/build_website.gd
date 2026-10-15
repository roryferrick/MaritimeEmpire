# Copyright (c) 2026 Rory Ferrick. All rights reserved. Maritime Empire.
extends SceneTree
## Builds the website's wiki from SPEC.md and its privacy page from PRIVACY.md
## (website/wiki/*.html, website/wiki/search_index.js, website/privacy.html).
## The wiki is pages of pages: a topic (TOPICS) lists its sections, each "## "
## section of the spec is a page, and each "### " part of a section a page of
## its own under it. Sections whose heading ends in a date ("(2026-10-12)")
## carry it as a note and are also listed under Recent changes on the wiki's
## home. The landing page (website/index.html), style.css and assets/wiki.js
## are written by hand. Rerun after changing SPEC.md or PRIVACY.md (`-- --spec
## <path>` builds from another copy of the spec, such as the last committed one):
##   Godot --headless --path . -s tools/build_website.gd

const SPEC_PATH := "res://SPEC.md"
const PRIVACY_PATH := "res://PRIVACY.md"
const SITE_DIR := "res://website"
const WIKI_DIR := "res://website/wiki"
## The Steam store page, empty until the listing is up (the button then says
## "Coming soon to Steam"). Set it in website/index.html too.
const STEAM_URL := ""
const SITE_NAME := "Maritime Empire"
## The site's address, for the sitemap and the social tags (no trailing slash).
const SITE_URL := "https://maritimeempiregame.com"

## The wiki's topics, in order: [slug, title, blurb, picture, section titles
## (the spec's headings without their dates)]. A section not named here goes
## under the last topic.
const TOPICS := [
	["playing", "Playing the game", "Starting a company, the screens and popups, the tutorial and the settings.", "found_company",
		["Screens", "Tutorial", "Popups", "Activity log", "Look", "Settings page sliders"]],
	["business", "Business and trading", "Company types, ratings and logos, money, cargo, farms and markets: how a shipping company makes (and loses) its fortune.", "types",
		["Company types", "Company ratings", "Company logos", "Economy & time", "Trading", "Farms", "Vehicle makers and factories", "Market regions", "Headquarters and hubs", "Company and ship levels (XP)", "Achievements", "Divine Actions", "Skin packs, Sand Dollars and the Shop"]],
	["ships", "Ships and crews", "Every model, the cruise lines, fuel and repairs, tugs, icebreakers, recovery boats and the people on deck.", "fleet",
		["Ship models", "Cruise lines", "Fuel, maintenance and port stops", "Refuel stops", "Lost ships and recovery boats", "Tugs", "Tugs working a ship in",
			"Icebreakers", "Long-term moorings", "People on deck", "Wakes", "Fishing and crabbing", "Choosing a fishing base"]],
	["world", "The world", "The globe, its ports and lanes, the great canals, the Arctic and the Great Lakes.", "globe",
		["World", "Panama Canal", "Suez Canal", "Great Lakes", "The Arctic",
			"Wonders of the world"]],
	["sea-and-sky", "Sea and sky", "Weather and storms, currents, seasons, and the animals and birds that share the sea.", "shanghai",
		["Weather", "Rough seas", "Seasonal closures", "Ocean currents", "Sea animals", "Wildlife", "Birds", "Sound"]],
	["rivals", "Rivals and multiplayer", "AI rival companies and playing with friends over Steam or a local network.", "routes",
		["AI rivals", "Multiplayer"]],
	["about", "About the game", "What's not in the beta yet, and copyright.", "",
		["Explicitly NOT in beta", "Copyright"]],
]
## Pictures shown at the top of particular pages (assets/shots/<name>.webp).
const PAGE_ART := {
	"World": ["globe", "The whole globe, every port and the fleet's lanes"],
	"Panama Canal": ["panama", "Colon, the canal and Balboa"],
	"Headquarters and hubs": ["singapore", "Singapore and Tanjung Pelepas, side by side on the strait"],
	"Wonders of the world": ["istanbul", "Istanbul's marina, with the Hagia Sophia"],
	"Tugs": ["rotterdam", "Rotterdam and Antwerp-Bruges: basins, piers and towns"],
	"Ship models": ["shop", "The Shop: every model with its speed, hold, range and crew"],
	"Birds": ["shanghai", "Shanghai, with its gulls over the harbour"],
	"Long-term moorings": ["harbour", "Ships coming and going at Apia"],
	"Trading": ["routes", "Trade lanes across the East China Sea"],
	"Screens": ["found_company", "Founding a company: choose its headquarters on the globe"],
	"Ships screen": ["fleet", "The Ships screen: the whole fleet, by model"],
	"2. Ships screen": ["fleet", "The Ships screen: the whole fleet, by model"],
	"3. Shop screen": ["shop", "The Shop"],
	"Farms": ["farms", "The Farms screen: a farm port's plots, what each grows, and the farm store"],
	"Company types": ["types", "Choosing your company type: six trades, each with its five tiers of ships"],
	"Company logos": ["logo", "Making your company logo"],
	"Company ratings": ["ratings", "The Ratings page: each type's stars and what goes into them"],
	"Cruise lines": ["cruise_planner", "The Cruise planner: prices against their recommendations, and the bookings outlook"],
}

var _bullet := RegEx.create_from_string("^(\\s*)[-*] (.*)$")
var _dated := RegEx.create_from_string("\\s*\\((\\d{4}-\\d{2}-\\d{2})[^)]*\\)\\s*$")
var _code := RegEx.create_from_string("`([^`]+)`")
var _bold := RegEx.create_from_string("\\*\\*([^*]+)\\*\\*")
var _link := RegEx.create_from_string("\\[([^\\]]+)\\]\\((https?://[^)\\s]+)\\)")
var _slug_strip := RegEx.create_from_string("[^a-z0-9]+")

## The spec is also the developer's notebook. The wiki leaves out what only
## matters to the code: these sections whole, and from every other line each
## bracketed note, then each sentence, that names code (files, functions,
## constants, identifiers, tool flags) or talks about the build.
const HIDDEN_SECTIONS := ["Tech", "Data & tools", "Lanes off the land and rounded", "Port approach fixes", "Ports on the water", "Lanes gate to gate", "Steam achievements and ship skins"]
## Heading words dropped from titles ("Ship models (data file)").
const TITLE_NOTES := [" (data file)"]
const BUILD_WORDS := ["probe", "native", "gdscript", "godot", "headless", "dll", "the tool", "rerun", "rebuilt", "cached", "cache ",
	"draw call", "per frame", "a frame", "each frame", "every frame", "shader", "atlas", "mesh", "batch", "export", "save version",
	"saves from before", "from before", "old saves", "debug", "profil", "build_", "spec ", "commit", "renamed", "lanes run",
	"grid", "tessellat", "thread", "callback", "signal", "autoload", "class_name"]
var _code_token := RegEx.create_from_string(
	"[\\w/.-]+\\.(gd|json|res|tscn|svg|ogg|wav|webp|png|gdshader|cfg|tres|md|h|cpp|ps1|py|sh|tsv|dll|txt)\\b" +
	"|\\b[A-Z][A-Za-z0-9]*\\.[a-z_][A-Za-z0-9_]*" +  # Class.member
	"|\\b_?[A-Za-z]\\w*\\(\\)" +  # call()
	"|(^|[\\s(])_[a-z]\\w+" +  # _private
	"|\\b[a-z][a-z0-9]*_[a-z0-9_]+\\b" +  # snake_case
	"|\\b[A-Z][A-Z0-9]*_[A-Z0-9_]+\\b" +  # CONSTANT_NAMES
	"|\\b[a-z]+[A-Z]\\w*\\b" +  # camelCase
	"|\\b[A-Z][a-z]+[A-Z][A-Za-z]*\\b(?<!GodotSteam)(?<!PlayStation)" +  # PascalCase classes
	"|user://|res://|(^|\\s)--[a-z]|`|\\bdata/|\\bart/|\\bscripts/|\\btools/|\\baudio/|\\bnative/")
var _sentence_end := RegEx.create_from_string("(?<=[.;!?])\\s+(?=[A-Z(\"])")

## Every page: {kind (topic, section, part), title, slug, file, dated, lines,
## parent (a page), children (pages), topic (its topic page)}.
var _pages := []
var _topics := []


func _init() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(WIKI_DIR))
	_clear_old_pages()
	var args := OS.get_cmdline_user_args()
	var spec_path := args[args.find("--spec") + 1] if args.has("--spec") and args.find("--spec") + 1 < args.size() else SPEC_PATH
	var spec := _split(FileAccess.get_file_as_string(spec_path))
	_build_tree(spec.sections)
	var index := []
	for page in _pages:
		_write("%s/%s" % [WIKI_DIR, page.file], _wiki_shell(page, _page_body(page)))
		index.append({t = page.title, p = _trail_text(page), u = page.file, x = _plain_text(page.lines)})
	_write(WIKI_DIR + "/index.html", _wiki_shell({}, _wiki_home(spec)))
	_write(WIKI_DIR + "/search_index.js", "window.WIKI_INDEX = %s;\n" % JSON.stringify(index))
	_write_privacy()
	_write_sitemap()
	print("wiki built: %d topics, %d pages" % [_topics.size(), _pages.size()])
	quit()


## Removes the last build's pages, so a renamed section leaves no stale page.
func _clear_old_pages() -> void:
	var dir := DirAccess.open(WIKI_DIR)
	if dir == null:
		return
	for file in dir.get_files():
		if file.ends_with(".html"):
			dir.remove(file)


## The spec as {title, intro, sections: [{title, dated, lines}]}.
func _split(text: String) -> Dictionary:
	var result := {title = SITE_NAME, intro = PackedStringArray(), sections = []}
	var current: Dictionary = {}
	for line in text.replace("\r", "").split("\n"):
		if line.begins_with("## "):
			var title := line.substr(3).strip_edges()
			var m := _dated.search(title)
			if m:
				title = _dated.sub(title, "")
			for note in TITLE_NOTES:
				title = title.replace(note, "")
			current = {title = title, dated = m.get_string(1) if m else "", lines = PackedStringArray()}
			if not HIDDEN_SECTIONS.has(title):
				result.sections.append(current)
		elif line.begins_with("# ") and current.is_empty():
			result.title = line.substr(2).strip_edges()
		elif current.is_empty():
			result.intro.append(_public(line))
		else:
			var kept := _public(line)
			if kept != "" or line.strip_edges() == "":
				current.lines.append(kept)
	return result


## A spec line as the wiki shows it: with its notes about the code taken out
## (see HIDDEN_SECTIONS), or "" if nothing is left. Headings and table rows
## are kept as they are.
func _public(line: String) -> String:
	var stripped := line.strip_edges()
	if stripped == "" or stripped.begins_with("#") or stripped.begins_with("|"):
		return line
	var m := _bullet.search(line)
	var lead := ("%s- " % m.get_string(1)) if m else ""
	var text := _without_code_notes(m.get_string(2) if m else stripped)
	var sentences := PackedStringArray()
	var dropped := false
	for sentence in _split_sentences(text):
		if _is_internal(sentence):
			dropped = true
			continue
		if dropped or sentences.is_empty():  # A sentence left on its own after a cut starts with a capital.
			sentence = sentence.left(1).to_upper() + sentence.substr(1)
			if not sentences.is_empty() and sentences[-1].ends_with(";"):
				sentences[-1] = sentences[-1].trim_suffix(";") + "."
		sentences.append(sentence)
		dropped = false
	text = " ".join(sentences).strip_edges()
	if text.ends_with(";"):
		text = text.trim_suffix(";") + "."
	text = text.replace(" ,", ",").replace(" .", ".").replace(" ;", ";").replace(" :", ":").replace("()", "").replace("  ", " ")
	if text.length() < 3 or text.ends_with(":") and text.length() < 40:
		return ""
	return lead + text


## Drops every bracketed group (with any inside it) that is internal.
func _without_code_notes(text: String) -> String:
	var out := ""
	var i := 0
	while i < text.length():
		if text[i] == "(":
			var depth := 0
			var j := i
			while j < text.length():
				if text[j] == "(":
					depth += 1
				elif text[j] == ")":
					depth -= 1
					if depth == 0:
						break
				j += 1
			var inner := text.substr(i + 1, j - i - 1)
			if j < text.length() and _is_internal(inner):
				out = out.rstrip(" ")
				i = j + 1
				continue
			out += "(" + _without_code_notes(inner) + (")" if j < text.length() else "")
			i = j + 1
			continue
		out += text[i]
		i += 1
	return out


## Sentences split at ". " or "; " outside brackets.
func _split_sentences(text: String) -> PackedStringArray:
	var parts := PackedStringArray()
	var depth := 0
	var start := 0
	for i in text.length():
		var c := text[i]
		if c == "(":
			depth += 1
		elif c == ")":
			depth = maxi(depth - 1, 0)
		elif depth == 0 and (c == "." or c == ";") and i + 1 < text.length() and text[i + 1] == " " \
				and not (i > 0 and text[i - 1].is_valid_int() and i + 2 < text.length() and text[i + 2].is_valid_int()):
			parts.append(text.substr(start, i + 1 - start).strip_edges())
			start = i + 2
	if start < text.length():
		parts.append(text.substr(start).strip_edges())
	return parts


func _is_internal(text: String) -> bool:
	if _code_token.search(text):
		return true
	var lower := text.to_lower()
	for word in BUILD_WORDS:
		if lower.contains(word):
			return true
	return false


func _slug(title: String) -> String:
	return _slug_strip.sub(title.to_lower(), "-", true).trim_prefix("-").trim_suffix("-")


## Topics, their sections, and each section's "### " parts as pages under it.
func _build_tree(sections: Array) -> void:
	var by_title := {}
	for section in sections:
		by_title[section.title] = section
	var placed := {}
	for t in TOPICS:
		var topic := {kind = "topic", title = t[1], slug = t[0], file = "%s.html" % t[0], dated = "",
			lines = PackedStringArray(), parent = {}, children = [], blurb = t[2], art = t[3]}
		topic.topic = topic
		_topics.append(topic)
		topic.index = _pages.size()
		_pages.append(topic)
		for title in t[4]:
			if by_title.has(title):
				placed[title] = true
				_add_section(topic, by_title[title])
	for section in sections:  # Anything new in the spec lands in the last topic.
		if not placed.has(section.title):
			_add_section(_topics.back(), section)


func _add_section(topic: Dictionary, section: Dictionary) -> void:
	var slug := _slug(section.title)
	var page := {kind = "section", title = section.title, slug = slug, file = "%s.html" % slug, dated = section.dated,
		lines = PackedStringArray(), parent = topic, topic = topic, children = []}
	topic.children.append(page)
	page.index = _pages.size()
	_pages.append(page)
	var part: Dictionary = {}
	for line: String in section.lines:
		if line.begins_with("### "):
			var title := line.substr(4).strip_edges()
			var part_slug := "%s--%s" % [slug, _slug(title)]
			part = {kind = "part", title = title, slug = part_slug, file = "%s.html" % part_slug, dated = section.dated,
				lines = PackedStringArray(), parent = page, topic = topic, children = []}
			page.children.append(part)
			part.index = _pages.size()
			_pages.append(part)
		elif part.is_empty():
			page.lines.append(line)
		else:
			part.lines.append(line)


func _page_body(page: Dictionary) -> String:
	var html := "<article class=\"wiki-page\">\n" + _breadcrumbs(page)
	html += "<h1>%s</h1>\n" % _inline(page.title)
	if page.dated != "":
		html += "<p class=\"dated\">Added or changed on %s</p>\n" % _long_date(page.dated)
	if page.kind == "topic":
		html += "<p class=\"lead\">%s</p>\n" % _escape(page.blurb)
		if page.art != "":
			html += _figure(page.art, page.title)
	elif PAGE_ART.has(page.title):
		html += _figure(PAGE_ART[page.title][0], PAGE_ART[page.title][1])
	html += _render(page.lines)
	if not page.children.is_empty():
		html += "<h2>%s</h2>\n" % ("In this topic" if page.kind == "topic" else "Pages in this section")
		html += _cards(page.children)
	html += _prev_next(page)
	return html + "</article>\n"


func _figure(art: String, caption: String) -> String:
	return "<figure class=\"shot\"><img src=\"../assets/shots/%s.webp\" alt=\"%s\" loading=\"lazy\"><figcaption>%s</figcaption></figure>\n" % [
		art, _escape(caption), _escape(caption)]


func _cards(pages: Array) -> String:
	var html := "<div class=\"cards\">\n"
	for page in pages:
		var count := ""
		if not page.children.is_empty():
			count = "<em>%d %s</em>" % [page.children.size(), "pages" if page.children.size() > 1 else "page"]
		var summary: String = page.blurb if page.kind == "topic" else _summary(page)
		html += "<a class=\"card\" href=\"%s\"><strong>%s</strong><span>%s</span>%s</a>\n" % [
			page.file, _inline(page.title), _escape(summary), count]
	return html + "</div>\n"


func _breadcrumbs(page: Dictionary) -> String:
	var trail := []
	var at: Dictionary = page.parent
	while not at.is_empty():
		trail.push_front("<a href=\"%s\">%s</a>" % [at.file, _inline(at.title)])
		at = at.parent
	trail.push_front("<a href=\"index.html\">Wiki</a>")
	return "<nav class=\"crumbs\" aria-label=\"Breadcrumb\">%s</nav>\n" % " <span>/</span> ".join(trail)


## "Wiki / The world / Panama Canal" without the page itself, for search results.
func _trail_text(page: Dictionary) -> String:
	var names := []
	var at: Dictionary = page.parent
	while not at.is_empty():
		names.push_front(at.title)
		at = at.parent
	return " / ".join(names)


## The pages before and after this one, reading the whole wiki in order.
func _prev_next(page: Dictionary) -> String:
	var i: int = page.index
	var html := "<nav class=\"prev-next\">"
	if i > 0:
		html += "<a class=\"prev\" href=\"%s\"><span>Previous</span>%s</a>" % [_pages[i - 1].file, _inline(_pages[i - 1].title)]
	else:
		html += "<span></span>"
	if i + 1 < _pages.size():
		html += "<a class=\"next\" href=\"%s\"><span>Next</span>%s</a>" % [_pages[i + 1].file, _inline(_pages[i + 1].title)]
	return html + "</nav>\n"


func _wiki_home(spec: Dictionary) -> String:
	var html := "<article class=\"wiki-home\">\n<h1>Maritime Empire Wiki</h1>\n"
	html += "<p class=\"lead\">How everything in the game works, from trading and fuel to tugs, weather and wildlife. The wiki is built from the game's own design spec, so it keeps up with every build.</p>\n"
	html += _render(spec.intro)
	html += "<div class=\"topic-grid\">\n"
	for topic in _topics:
		var art := "<img src=\"../assets/shots/%s.webp\" alt=\"\" loading=\"lazy\">" % topic.art if topic.art != "" else "<div class=\"topic-blank\"></div>"
		html += "<a class=\"topic\" href=\"%s\">%s<strong>%s</strong><span>%s</span><em>%d sections</em></a>\n" % [
			topic.file, art, _escape(topic.title), _escape(topic.blurb), topic.children.size()]
	html += "</div>\n"
	var recent := []
	for page in _pages:
		if page.kind == "section" and page.dated != "":
			recent.append(page)
	recent.sort_custom(func(a, b): return a.dated > b.dated)
	if not recent.is_empty():
		html += "<h2>Recent changes</h2>\n<ul class=\"recent\">\n"
		for page in recent:
			html += "<li><time>%s</time><a href=\"%s\">%s</a> <span>in %s</span></li>\n" % [
				_long_date(page.dated), page.file, _inline(page.title), _escape(page.topic.title)]
		html += "</ul>\n"
	return html + "</article>\n"


func _long_date(iso: String) -> String:
	var months := ["January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December"]
	var parts := iso.split("-")
	return "%d %s %s" % [int(parts[2]), months[int(parts[1]) - 1], parts[0]]


## The page's first sentence or so, for its card.
func _summary(page: Dictionary) -> String:
	var lines: PackedStringArray = page.lines
	if _first_text(lines) == "" and not page.children.is_empty():
		lines = page.children[0].lines
	var text := _first_text(lines)
	if text.length() > 140:
		text = text.substr(0, text.rfind(" ", 140)) + "..."
	return text


func _first_text(lines: PackedStringArray) -> String:
	for line in lines:
		var m := _bullet.search(line)
		var text := (m.get_string(2) if m else line.strip_edges()).replace("**", "").replace("`", "")
		if text != "" and not text.begins_with("#") and not text.begins_with("|"):
			return text
	return ""


## Markdown (the subset the spec uses: #### headings, nested - lists, | tables,
## paragraphs, `code`, **bold** and [links](https://...)) to HTML.
func _render(lines: PackedStringArray) -> String:
	var out := PackedStringArray()
	var stack: Array[int] = []
	var para := PackedStringArray()
	var i := 0
	while i < lines.size():
		var line := lines[i]
		var stripped := line.strip_edges()
		if stripped == "" or stripped.begins_with("#") or stripped.begins_with("|"):
			_close_para(out, para)
			_close_lists(out, stack)
		if stripped == "":
			i += 1
			continue
		if stripped.begins_with("#"):
			var level := stripped.find(" ")
			var title := stripped.substr(level + 1)
			var id := _slug(title)
			var tag := "h%d" % clampi(level, 2, 4)
			out.append("<%s id=\"%s\">%s</%s>" % [tag, id, _inline(title), tag])
			i += 1
			continue
		if stripped.begins_with("|"):
			var rows := PackedStringArray()
			while i < lines.size() and lines[i].strip_edges().begins_with("|"):
				rows.append(lines[i].strip_edges())
				i += 1
			out.append(_table(rows))
			continue
		var m := _bullet.search(line)
		if m:
			_close_para(out, para)
			var indent := m.get_string(1).length()
			if stack.is_empty() or indent > stack.back():
				out.append("<ul>")
				stack.append(indent)
			else:
				while stack.size() > 1 and indent < stack.back():
					out.append("</li></ul>")
					stack.pop_back()
				out.append("</li>")
			out.append("<li>" + _inline(m.get_string(2)))
		elif not stack.is_empty():
			out.append(" " + _inline(stripped))
		else:
			para.append(_inline(stripped))
		i += 1
	_close_para(out, para)
	_close_lists(out, stack)
	return "\n".join(out) + "\n"


func _close_para(out: PackedStringArray, para: PackedStringArray) -> void:
	if not para.is_empty():
		out.append("<p>" + " ".join(para) + "</p>")
		para.clear()


func _close_lists(out: PackedStringArray, stack: Array[int]) -> void:
	while not stack.is_empty():
		out.append("</li></ul>")
		stack.pop_back()


func _table(rows: PackedStringArray) -> String:
	var html := "<div class=\"table-wrap\"><table>\n"
	var head := true
	for row in rows:
		var cells := row.trim_prefix("|").trim_suffix("|").split("|")
		if cells[0].strip_edges().begins_with("---"):
			head = false
			continue
		var tag := "th" if head else "td"
		html += "<tr>"
		for cell in cells:
			html += "<%s>%s</%s>" % [tag, _inline(cell.strip_edges()), tag]
		html += "</tr>\n"
	return html + "</table></div>"


func _escape(s: String) -> String:
	return s.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;").replace("\"", "&quot;")


func _inline(s: String) -> String:
	var html := _escape(s)
	html = _code.sub(html, "<code>$1</code>", true)
	html = _bold.sub(html, "<strong>$1</strong>", true)
	html = _link.sub(html, "<a href=\"$2\">$1</a>", true)
	return html


func _plain_text(lines: PackedStringArray) -> String:
	var text := " ".join(lines).replace("**", "").replace("`", "").replace("|", " ")
	return " ".join(text.split(" ", false))


## The sidebar: every topic, the current topic's sections, and the current
## section's pages.
func _nav(current: Dictionary) -> String:
	var html := "<nav class=\"sidebar\" id=\"sidebar\">\n<a class=\"side-home%s\" href=\"index.html\">Wiki home</a>\n<ul class=\"tree\">\n" % (
		" current" if current.is_empty() else "")
	var open_topic: Dictionary = current.get("topic", {})
	var open_section: Dictionary = {}
	if not current.is_empty():
		open_section = current if current.kind == "section" else (current.parent if current.kind == "part" else {})
	for topic in _topics:
		var is_open := is_same(topic, open_topic)
		html += "<li class=\"t%s\"><a%s href=\"%s\">%s</a>" % [" open" if is_open else "", _current(topic, current), topic.file, _escape(topic.title)]
		if is_open:
			html += "\n<ul>\n"
			for section in topic.children:
				html += "<li><a%s href=\"%s\">%s</a>" % [_current(section, current), section.file, _inline(section.title)]
				if is_same(section, open_section) and not section.children.is_empty():
					html += "<ul>"
					for part in section.children:
						html += "<li><a%s href=\"%s\">%s</a></li>" % [_current(part, current), part.file, _inline(part.title)]
					html += "</ul>"
				html += "</li>\n"
			html += "</ul>\n"
		html += "</li>\n"
	return html + "</ul>\n</nav>\n"


func _current(page: Dictionary, current: Dictionary) -> String:
	return " class=\"current\" aria-current=\"page\"" if is_same(page, current) else ""


func _header(prefix: String, active: String) -> String:
	var steam := "<a class=\"btn btn-steam\" href=\"%s\">Wishlist on Steam</a>" % STEAM_URL if STEAM_URL != "" \
		else "<span class=\"btn btn-steam is-soon\" title=\"The Steam page isn't up yet\">Coming soon to Steam</span>"
	return """<header class="site-header">
<a class="brand" href="%sindex.html"><img src="%sassets/icon_64.png" alt="" width="32" height="32">Maritime Empire</a>
<nav class="site-nav"><a%s href="%sindex.html">Home</a><a%s href="%swiki/index.html">Wiki</a>%s</nav>
</header>
""" % [prefix, prefix, " class=\"active\"" if active == "home" else "", prefix,
		" class=\"active\"" if active == "wiki" else "", prefix, steam]


func _footer(prefix: String) -> String:
	return """<footer class="site-footer">
<p>&copy; 2026 Rory Ferrick. All rights reserved. Maritime Empire is in development.</p>
<p><a href="%swiki/index.html">Wiki</a> &middot; <a href="%sprivacy.html">Privacy</a></p>
</footer>
""" % [prefix, prefix]


func _head(title: String, prefix: String, description: String) -> String:
	return """<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>%s</title>
<meta name="description" content="%s">
<link rel="icon" href="%sassets/icon_32.png" sizes="32x32">
<link rel="apple-touch-icon" href="%sassets/icon_180.png">
<link rel="stylesheet" href="%sstyle.css">
<meta property="og:title" content="%s">
<meta property="og:description" content="%s">
<meta property="og:image" content="%s/assets/shots/rome.webp">
<meta property="og:type" content="website">
<meta name="twitter:card" content="summary_large_image">
</head>
""" % [_escape(title), _escape(description), prefix, prefix, prefix, _escape(title), _escape(description), SITE_URL]


func _wiki_shell(page: Dictionary, content: String) -> String:
	var title := "%s - %s Wiki" % [page.title, SITE_NAME] if not page.is_empty() else "%s Wiki" % SITE_NAME
	var description := "%s, on the %s wiki." % [page.title, SITE_NAME] if not page.is_empty() else "How everything in Maritime Empire works."
	var html := _head(title, "../", description)
	html += "<body class=\"wiki\">\n<a class=\"skip\" href=\"#main\">Skip to content</a>\n" + _header("../", "wiki")
	html += """<div class="wiki-layout">
<aside class="wiki-aside">
<div class="search"><input id="search" type="search" placeholder="Search the wiki" autocomplete="off" aria-label="Search the wiki"><div id="results" class="results" hidden></div></div>
<button class="side-toggle" id="side-toggle" aria-controls="sidebar" aria-expanded="false">All topics</button>
"""
	html += _nav(page) + "</aside>\n<main class=\"wiki-main\" id=\"main\">\n" + content + "</main>\n</div>\n"
	html += _footer("../")
	html += "<script src=\"search_index.js\" defer></script>\n<script src=\"../assets/wiki.js\" defer></script>\n</body>\n</html>\n"
	return html


## sitemap.xml: the landing page, the privacy page and every wiki page.
func _write_sitemap() -> void:
	var urls := ["/", "/privacy.html", "/wiki/"]
	for page in _pages:
		urls.append("/wiki/%s" % page.file)
	var xml := "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<urlset xmlns=\"http://www.sitemaps.org/schemas/sitemap/0.9\">\n"
	for url in urls:
		xml += "<url><loc>%s%s</loc></url>\n" % [SITE_URL, url]
	_write(SITE_DIR + "/sitemap.xml", xml + "</urlset>\n")


func _write_privacy() -> void:
	var lines := FileAccess.get_file_as_string(PRIVACY_PATH).replace("\r", "").split("\n")
	if lines.size() > 0 and lines[0].begins_with("# "):
		lines.remove_at(0)
	var html := _head("Privacy Policy - " + SITE_NAME, "", "How Maritime Empire handles your information.")
	html += "<body>\n<a class=\"skip\" href=\"#main\">Skip to content</a>\n" + _header("", "")
	html += "<main class=\"prose\" id=\"main\">\n<h1>Privacy Policy</h1>\n%s</main>\n" % _render(lines)
	html += _footer("") + "</body>\n</html>\n"
	_write(SITE_DIR + "/privacy.html", html)


func _write(path: String, text: String) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		push_error("couldn't write %s: %d" % [path, FileAccess.get_open_error()])
		return
	f.store_string(text)
