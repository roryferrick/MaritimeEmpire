# Copyright (c) 2026 Rory Ferrick. All rights reserved. Maritime Empire.
class_name PeopleScreen
extends Control
## The People page over the map (DESIGN_LIVING_WORLD.md M3): the CEO, the six
## executive posts (each with the person in it, their skills and what the post
## does, or Hire), the department heads (one per trade group and market
## region, each with a budget of contracts to take), the ships' officers, and
## the job market (candidates with age, nationality, skills, traits and
## salary ask; Hire into a post, the headhunter). Refreshes as the people change.

const FONT_SIZE := 14
const SKILL_WIDTH := 200.0

var _body := VBoxContainer.new()
var _hiring := {}  # The candidate being placed (id), and the picked post.
var _new_head_group := ""
var _new_head_region := ""
var _head_budget := 20000000


func _ready() -> void:
	var scroll := ScrollContainer.new()
	scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	var margin := MarginContainer.new()
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for side: String in ["left", "top", "right", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 24)
	scroll.add_child(margin)
	var content := VBoxContainer.new()
	content.add_theme_constant_override(&"separation", 12)
	margin.add_child(content)
	var title := Label.new()
	title.theme_type_variation = &"HeaderLabel"
	title.text = "People"
	content.add_child(title)
	_body.add_theme_constant_override(&"separation", 14)
	content.add_child(_body)
	visibility_changed.connect(_refresh)
	GameState.people.changed.connect(_refresh)
	GameState.ships_changed.connect(_refresh)
	_refresh()


func _refresh() -> void:
	if not is_visible_in_tree():
		return
	for child in _body.get_children():
		_body.remove_child(child)
		child.queue_free()
	var company := GameState.company
	var people: People = GameState.people
	_body.add_child(_dim("Skills work for the company: about %d%% a point over %d on what a post touches, up to %d%%. Salaries are paid with the crews' wages (%s a period now)." % [roundi(People.PER_POINT * 100.0), Traits.BASE_SKILL, roundi(People.CAP * 100.0), Fmt.money(people.salaries_due(company))]))
	_add_executives(company, people)
	_add_heads(company, people)
	_add_officers(company)
	_add_family(company, people)
	_add_market(company, people)


# --- Executives -----------------------------------------------------------------------------

func _add_executives(company: Company, people: People) -> void:
	var box := _card("Executives")
	box.add_child(_person_row(company.ceo, "Chief Executive (you)", "", "", company))
	for role: String in People.ROLE_ORDER:
		var info: Dictionary = People.ROLES[role]
		var person: Dictionary = company.executives.get(role, {})
		var effects := PackedStringArray()
		for key: String in info.effects:
			effects.append(_effect_word(key))
		var what := "%s: %s (draws on %s)" % [str(info.name), ", ".join(effects), ", ".join(PackedStringArray((info.skills as Array).map(func(s: String) -> String: return str(Traits.SKILL_NAMES[s]))))]
		if person.is_empty():
			var row := HBoxContainer.new()
			row.add_theme_constant_override(&"separation", 10)
			var empty := _text("%s — vacant" % str(info.short))
			empty.theme_type_variation = &"DimLabel"
			empty.tooltip_text = what
			empty.size_flags_horizontal = SIZE_EXPAND_FILL
			row.add_child(empty)
			row.add_child(_hunt_button(people, company, "exec", role))
			box.add_child(row)
		else:
			box.add_child(_person_row(person, "%s (%s)" % [str(info.short), str(info.name)], "exec", role, company, what))
	_body.add_child(box.get_parent())


static func _effect_word(key: String) -> String:
	return {interest = "loan interest", fees = "port fees", dock = "time in port", wages = "wages", wear = "wear", breakdowns = "breakdowns", research = "research points",
		rates = "contract rates", standing = "standing gains", hiring = "hiring costs", penalties = "contract penalties"}.get(key, key)


# --- Heads ----------------------------------------------------------------------------------

func _add_heads(company: Company, people: People) -> void:
	var box := _card("Department heads")
	box.add_child(_dim("A head for a trade group in a market region takes the producers' offers there under their budget when an idle ship of yours of the right line can reach the load port, and puts the ship on it. Their Negotiation nudges the rate."))
	for key: String in company.heads:
		var budget := int(company.head_budgets.get(key, 0))
		var row := _person_row(company.heads[key], People.head_title(key), "head", key, company)
		var spin := SpinBox.new()
		spin.min_value = 0
		spin.max_value = 1000000000
		spin.step = 1000000
		spin.prefix = "$"
		spin.value = budget
		spin.custom_minimum_size.x = 150.0
		spin.tooltip_text = "The most in contracts this head may have on the books at once."
		spin.value_changed.connect(func(value: float) -> void: GameState.set_head_budget(key, roundi(value)))
		row.add_child(spin)
		box.add_child(row)
	var groups := People.groups_of(company)
	if groups.is_empty():
		box.add_child(_dim("Your divisions carry no cargo lines a head could run."))
	else:
		var row := HBoxContainer.new()
		row.add_theme_constant_override(&"separation", 8)
		row.add_child(_text("New post:"))
		var group_picker := OptionButton.new()
		for category: String in groups:
			group_picker.add_item(People.group_name(category))
			group_picker.set_item_metadata(group_picker.item_count - 1, category)
		if _new_head_group.is_empty():
			_new_head_group = groups[0]
		for i in group_picker.item_count:
			if group_picker.get_item_metadata(i) == _new_head_group:
				group_picker.select(i)
		group_picker.item_selected.connect(func(index: int) -> void: _new_head_group = str(group_picker.get_item_metadata(index)))
		row.add_child(group_picker)
		var region_picker := OptionButton.new()
		for region: Dictionary in GameData.markets.get("regions", []):
			region_picker.add_item(str(region.name))
			region_picker.set_item_metadata(region_picker.item_count - 1, str(region.id))
		if _new_head_region.is_empty():
			_new_head_region = str(GameData.port_region(company.home_port).get("id", GameData.markets.get("regions", [{}])[0].get("id", "")))
		for i in region_picker.item_count:
			if region_picker.get_item_metadata(i) == _new_head_region:
				region_picker.select(i)
		region_picker.item_selected.connect(func(index: int) -> void: _new_head_region = str(region_picker.get_item_metadata(index)))
		row.add_child(region_picker)
		row.add_child(_dim("then Hire a head from the market below, or:"))
		row.add_child(_hunt_button(people, company, "head", ""))
		box.add_child(row)
	_body.add_child(box.get_parent())


# --- Officers -------------------------------------------------------------------------------

func _add_officers(company: Company) -> void:
	var box := _card("Officers")
	var any := false
	for ship in GameState.fleet(company):
		if ship.captains.is_empty():
			continue
		any = true
		for i in ship.captains.size():
			box.add_child(_person_row(ship.captains[i], "%s of %s (%s)" % [Characters.rank(i), ship.name, str(ship.model().get("name", ""))], "officer", "%d|%d" % [ship.id, i], company))
	if not any:
		box.add_child(_dim("No ships, no officers yet."))
	_body.add_child(box.get_parent())


# --- The family ---------------------------------------------------------------------------------

func _add_family(company: Company, people: People) -> void:
	var box := _card("The family")
	var family: Dictionary = company.family
	var ceo: Dictionary = company.ceo
	var spouse: Dictionary = family.get("spouse", {})
	var children: Array = family.get("children", [])
	if spouse.is_empty() and children.is_empty():
		box.add_child(_dim("%s is unmarried. In time there may be a spouse and children; a child of age can be named heir, and takes the shares and the post when %s dies or retires." % [str(ceo.get("name", "The CEO")), str(ceo.get("name", "")).get_slice(" ", 0)]))
		_body.add_child(box.get_parent())
		return
	if not spouse.is_empty():
		box.add_child(_person_row(spouse, "spouse of %s" % str(ceo.get("name", "")), "", "", company))
	var heir := people.heir_of(company)
	for i in children.size():
		var child: Dictionary = children[i]
		var age := float(child.get("age", 0.0))
		var row := _person_row(child, "%s, %s" % ["child" if age < People.ADULT_AGE else "of age", "heir" if child == heir else "not the heir"], "", "", company)
		if age >= People.ADULT_AGE and child != heir:
			var index := i
			row.add_child(_flat_button("Make heir", func() -> void: GameState.set_heir(index)))
		box.add_child(row)
	box.add_child(_dim("The heir inherits the founder's shares and becomes chief executive, with their own traits and skills, when the CEO dies or retires; without one of age, an executive or a hire steps up."))
	_body.add_child(box.get_parent())


# --- The market ------------------------------------------------------------------------------

func _add_market(company: Company, people: People) -> void:
	var box := _card("Job market (%d)" % people.candidates.size())
	box.add_child(_dim("A third of the market turns over each month. Hire puts the person in a post: an executive's role, a head's post (the New post pickers above) or a ship's command. Someone at another firm costs a signing bonus and the firm remembers."))
	var grid := GridContainer.new()
	grid.columns = 7
	grid.add_theme_constant_override(&"h_separation", 14)
	grid.add_theme_constant_override(&"v_separation", 3)
	for head: String in ["Name", "Age", "From", "For", "Skills", "Traits", "Asks a year"]:
		grid.add_child(_cell(head, &"DimLabel"))
	for candidate: Dictionary in people.candidates:
		var person: Dictionary = candidate.character
		grid.add_child(_cell(str(person.get("name", ""))))
		grid.add_child(_cell(str(roundi(float(person.get("age", 40))))))
		var from := str(WorldEconomy.country(str(person.get("nationality", ""))).get("name", person.get("nationality", "")))
		if int(candidate.get("employer", -1)) >= 0:
			from += ", at %s" % str((GameState.firms as ShippingFirms).firms[int(candidate.employer)].name)
		grid.add_child(_cell(from))
		var kind := str(candidate.kind)
		grid.add_child(_cell(str(People.ROLES[candidate.role].short) if kind == "exec" and People.ROLES.has(candidate.role) else kind.capitalize()))
		grid.add_child(_cell(_skills_text(person)))
		grid.add_child(_cell(Traits.names_of(person) if not Traits.names_of(person).is_empty() else "—"))
		var ask := HBoxContainer.new()
		ask.add_theme_constant_override(&"separation", 6)
		ask.add_child(_cell(Fmt.money(int(candidate.ask))))
		var hire := Button.new()
		hire.text = "Hire"
		hire.add_theme_font_size_override(&"font_size", FONT_SIZE)
		var error := people.hire_error(company, candidate)
		hire.disabled = not error.is_empty()
		hire.tooltip_text = error if not error.is_empty() else ("Signing bonus %s" % Fmt.money(people.hiring_cost(company, candidate)) if people.hiring_cost(company, candidate) > 0 else "")
		var id := int(candidate.id)
		hire.pressed.connect(func() -> void:
			_hiring = {id = id}
			_refresh())
		ask.add_child(hire)
		grid.add_child(ask)
		if int(_hiring.get("id", -1)) == id:
			var picker := _post_picker(company, candidate)
			grid.add_child(picker)
			for k in 6:
				grid.add_child(Control.new())
	box.add_child(grid)
	_body.add_child(box.get_parent())


## Where to put a candidate: the posts their kind fits.
func _post_picker(company: Company, candidate: Dictionary) -> Control:
	var flow := HFlowContainer.new()
	flow.add_theme_constant_override(&"h_separation", 6)
	flow.add_child(_dim("Put %s in:" % str((candidate.character as Dictionary).get("name", ""))))
	var id := int(candidate.id)
	var kind := str(candidate.kind)
	if kind == "exec":
		for role: String in People.ROLE_ORDER:
			var taken := not (company.executives.get(role, {}) as Dictionary).is_empty()
			flow.add_child(_flat_button("%s%s" % [str(People.ROLES[role].short), " (replacing %s)" % str(company.executives[role].name) if taken else ""], func() -> void:
				GameState.hire_person(id, "exec", role, 0)
				_hiring = {}
				_refresh()))
	elif kind == "head":
		var key := "%s|%s" % [_new_head_group, _new_head_region]
		flow.add_child(_flat_button("%s (budget %s)" % [People.head_title(key), Fmt.money_short(_head_budget)], func() -> void:
			GameState.hire_person(id, "head", key, _head_budget)
			_hiring = {}
			_refresh()))
	else:
		for ship in GameState.fleet(company):
			if ship.captains.is_empty():
				continue
			flow.add_child(_flat_button("Captain of %s (now %s)" % [ship.name, str(ship.captains[0].get("name", ""))], func() -> void:
				GameState.hire_person(id, "officer", "%d|0" % ship.id, 0)
				_hiring = {}
				_refresh()))
	flow.add_child(_flat_button("Cancel", func() -> void:
		_hiring = {}
		_refresh()))
	return flow


func _hunt_button(people: People, company: Company, kind: String, role: String) -> Button:
	var button := Button.new()
	var base := People.OFFICER_SALARY if kind == "officer" else (People.HEAD_SALARY if kind == "head" else People.EXEC_SALARY)
	button.text = "Headhunter %s" % Fmt.money_short(roundi(base * 1.5 * People.HEADHUNT_FEE))
	button.add_theme_font_size_override(&"font_size", FONT_SIZE)
	button.tooltip_text = "For the fee, a strong candidate for this post joins the market at the top."
	button.pressed.connect(func() -> void: GameState.headhunt(kind, role))
	return button


# --- Bits --------------------------------------------------------------------------------------

## A person in a post: portrait, name, age and nationality, traits, skills, salary, and Dismiss / Promote.
func _person_row(person: Dictionary, post: String, kind: String, key: String, company: Company, tip := "") -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", 10)
	var face := Portrait.new(person, true)
	face.custom_minimum_size = Vector2(44, 44)
	face.size_flags_vertical = SIZE_SHRINK_CENTER
	row.add_child(face)
	var text := VBoxContainer.new()
	text.add_theme_constant_override(&"separation", 0)
	text.size_flags_horizontal = SIZE_EXPAND_FILL
	var name := _text("%s — %s" % [str(person.get("name", "")), post])
	if not tip.is_empty():
		name.tooltip_text = tip
		name.mouse_filter = Control.MOUSE_FILTER_PASS
	text.add_child(name)
	var from := str(WorldEconomy.country(str(person.get("nationality", ""))).get("name", ""))
	var detail := "%s%s · %s · %s" % ["%d, " % roundi(float(person.get("age", 40))) if person.has("age") else "", from if not from.is_empty() else "age unknown", _skills_text(person),
		Traits.names_of(person) if not Traits.names_of(person).is_empty() else "no traits of note"]
	if int(person.get("salary", 0)) > 0:
		detail += " · %s a year" % Fmt.money(int(person.salary))
	if person.get("notice", false):
		detail += " · retiring soon"
	if kind == "officer" and key.ends_with("|0"):
		detail += " · %s (morale %d)" % [People.morale_word(person), roundi(People.morale_of(person))]
	text.add_child(_dim(detail))
	row.add_child(text)
	if kind == "officer" and key.ends_with("|0"):
		var bonus := Button.new()
		bonus.text = "Bonus"
		bonus.flat = true
		bonus.add_theme_font_size_override(&"font_size", FONT_SIZE)
		bonus.tooltip_text = "A %s bonus for the captain: morale +%d. Morale drifts back to %d; calls at home and a sound ship keep it up, breakdowns and being passed over pull it down; under %d the captain resigns." % [Fmt.money(People.BONUS_PAY), roundi(People.MORALE_BONUS), roundi(People.MORALE_BASE), roundi(People.MORALE_RESIGN)]
		var ship_id := int(key.split("|")[0])
		bonus.pressed.connect(func() -> void: GameState.pay_bonus(GameState.ship_by_id(ship_id)))
		row.add_child(bonus)
	if kind == "officer":
		var promote := MenuButton.new()
		promote.text = "Promote"
		promote.add_theme_font_size_override(&"font_size", FONT_SIZE)
		promote.tooltip_text = "Make this officer an executive (free; a new officer takes the ship)."
		for role: String in People.ROLE_ORDER:
			promote.get_popup().add_item(str(People.ROLES[role].short))
		var parts := key.split("|")
		promote.get_popup().index_pressed.connect(func(index: int) -> void: GameState.promote_officer(GameState.ship_by_id(int(parts[0])), int(parts[1]), People.ROLE_ORDER[index]))
		row.add_child(promote)
	if not kind.is_empty():
		var dismiss := Button.new()
		dismiss.text = "Replace" if kind == "officer" else "Dismiss"
		dismiss.flat = true
		dismiss.add_theme_font_size_override(&"font_size", FONT_SIZE)
		dismiss.pressed.connect(func() -> void: GameState.fire_person(kind, key))
		row.add_child(dismiss)
	return row


static func _skills_text(person: Dictionary) -> String:
	var skills := Traits.skills_of(person)
	var parts := PackedStringArray()
	for skill: String in Traits.SKILLS:
		parts.append("%s %d" % [str(Traits.SKILL_NAMES[skill]).substr(0, 3), int(skills.get(skill, 0))])
	return " ".join(parts)


func _card(title_text: String) -> VBoxContainer:
	var card := PanelContainer.new()
	card.theme_type_variation = &"CardPanel"
	var box := VBoxContainer.new()
	box.add_theme_constant_override(&"separation", 6)
	card.add_child(box)
	var title := Label.new()
	title.text = title_text
	title.add_theme_font_size_override(&"font_size", 17)
	box.add_child(title)
	return box


func _text(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override(&"font_size", FONT_SIZE)
	return label


func _dim(text: String) -> Label:
	var label := _text(text)
	label.theme_type_variation = &"DimLabel"
	return label


func _cell(text: String, variation := &"") -> Label:
	var label := Label.new()
	label.text = text
	label.theme_type_variation = variation
	label.add_theme_font_size_override(&"font_size", FONT_SIZE)
	return label


func _flat_button(text: String, then: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.add_theme_font_size_override(&"font_size", FONT_SIZE)
	button.pressed.connect(then)
	return button
