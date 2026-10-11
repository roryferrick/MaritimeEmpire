# Copyright (c) 2026 Rory Ferrick. All rights reserved. Maritime Empire.
class_name Characters
extends RefCounted
## People: the company's CEO (made on the New Company screen) and each ship's
## officers, its captain and mates (GameState.crew_of(): one officer for the
## smaller ships, up to four for the biggest), made up at random when the ship
## is bought. A character is {name, look}, look a choice (an index into
## PARTS' options) for each part, plus the SLIDERS (0 to 100: height and
## build); Portrait draws them in a clean cartoon style, the clothes drawn
## over whatever body the sliders and the body choice make.

## The story's people (the tutorial's voices: TutorialCard): Captain Mo B. Dick,
## a big white-bearded captain in his dress whites who does the welcome and
## knows the birds; Sailor Sonny, strong, sharp and able, on shipping;
## HQ Marissa (slim, tanned, Italian, long brown hair, green eyes and a lovely smile) on the money and the achievements; and Deckhand Joe on sailing
## and the odd things about ships. Each is a character ({name, look}) drawn by Portrait.
const STORY := {
	dick = {name = "Captain Mo B. Dick", role = "Captain", look = {body = 0, skin = 1, eye_shape = 0, eye_color = 4, nose = 6, mouth = 0, hair = 2, hair_color = 10, facial_hair = 4, top = 5, bottoms = 0, shoes = 1, eyewear = 0, headwear = 1, height = 88, build = 100}},
	sonny = {name = "Sailor Sonny", role = "Sailor", look = {body = 0, skin = 5, eye_shape = 1, eye_color = 0, nose = 2, mouth = 1, hair = 1, hair_color = 0, facial_hair = 1, top = 1, bottoms = 1, shoes = 0, eyewear = 0, headwear = 5, height = 70, build = 95}},
	marissa = {name = "HQ Marissa", role = "Head office", look = {body = 1, skin = 5, eye_shape = 1, eye_color = 6, nose = 5, mouth = 0, hair = 5, hair_color = 2, facial_hair = 0, top = 15, bottoms = 10, shoes = 7, eyewear = 0, headwear = 0, height = 60, build = 18}},
	joe = {name = "Deckhand Joe", role = "Deckhand", look = {body = 0, skin = 2, eye_shape = 4, eye_color = 6, nose = 7, mouth = 3, hair = 8, hair_color = 4, facial_hair = 2, top = 3, bottoms = 2, shoes = 2, eyewear = 0, headwear = 6, height = 45, build = 60}},
}

## The longest a character's name can be (the CEO editor's name box too).
const MAX_NAME_LENGTH := 32

## The parts of a look, in the order the CEO screen lists them: [key, title,
## option names]. Portrait draws each option. The body (male or female
## build) is the first; the outfit parts lean to the sea (a captain's jacket,
## sailor stripes, a pea coat, oilskins, sea boots, a sou'wester...) with
## everyday clothes kept too.
const PARTS := [
	["body", "Body", ["Male", "Female"]],
	["skin", "Skin", ["Porcelain", "Fair", "Light", "Light olive", "Olive", "Tan", "Bronze", "Brown", "Dark brown", "Deep"]],
	["eye_shape", "Eye shape", ["Round", "Almond", "Narrow", "Wide", "Sleepy", "Lashes", "Smiling", "Squint"]],
	["eye_color", "Eye color", ["Brown", "Dark brown", "Hazel", "Amber", "Blue", "Light blue", "Green", "Grey", "Violet"]],
	["nose", "Nose", ["Button", "Long", "Wide", "Pointed", "Hooked", "Small", "Roman", "Snub", "Broad", "Freckled"]],
	["mouth", "Mouth", ["Smile", "Grin", "Straight", "Smirk", "Laugh", "Surprised", "Frown", "Red lips", "Cheeky", "Gentle"]],
	["hair", "Hair style", ["Bald", "Buzz cut", "Short", "Side part", "Quiff", "Long", "Bob", "Ponytail", "Curly", "Braids", "Mohawk", "Bun", "Afro"]],
	["hair_color", "Hair color", ["Black", "Dark brown", "Brown", "Light brown", "Auburn", "Ginger", "Strawberry blonde", "Blonde", "Platinum", "Grey", "White", "Blue", "Pink", "Green"]],
	["facial_hair", "Facial hair", ["None", "Stubble", "Moustache", "Goatee", "Full beard", "Chinstrap", "Handlebar", "Soul patch", "Mutton chops", "Long beard"]],
	["top", "Top", ["Captain's jacket", "Sailor stripes", "Pea coat", "Yellow oilskin", "Fisherman's jumper", "Dress whites", "Deck tee", "Life vest", "Wetsuit", "Officer's shirt", "Tropical shirt", "Pirate coat",
		"White tee", "Red tee", "Grey hoodie", "Black suit", "Plaid flannel", "Hi-vis vest"]],
	["bottoms", "Bottoms", ["Navy trousers", "Sailor bell-bottoms", "Oilskin trousers", "Deck shorts", "Wetsuit legs", "Jeans", "Khakis", "Black trousers", "Cargo trousers", "Red skirt", "Navy skirt", "Denim shorts"]],
	["shoes", "Shoes", ["Deck shoes", "Sea boots", "Yellow wellies", "Barefoot", "Black boots", "Brown boots", "White trainers", "Dress shoes", "Sandals", "Red trainers"]],
	["eyewear", "Glasses", ["None", "Round", "Square", "Sunglasses", "Aviators", "Monocle", "Half-rims", "Cat-eye", "Goggles", "Eye patch"]],
	["headwear", "Hat", ["None", "Captain's cap", "Sailor cap", "Sou'wester", "Tricorne", "Bandana", "Watch cap", "Straw hat", "Bucket hat", "Baseball cap", "Top hat", "Hard hat", "Cowboy hat",
		"Fisherman's cap", "Flat cap", "Beret", "Bicorne", "Pompom beanie", "Fedora", "Pith helmet", "Conical hat"]],
]
## The sliders of a look (0 to 100, 50 the middle): [key, title, low word, high word].
const SLIDERS := [
	["height", "Height", "Short", "Tall"],
	["build", "Build", "Slight", "Broad"],
]
## How likely a random look is to have none of a part that can be left off.
const NONE_CHANCES := {facial_hair = 0.55, eyewear = 0.6, headwear = 0.45}

const FIRST_NAMES: Array[String] = [
	"Ada", "Aiko", "Alex", "Amara", "Anders", "Ane", "Arjun", "Astrid", "Bea", "Ben", "Bjorn", "Bram", "Carla", "Carlos",
	"Chen", "Chloe", "Dara", "Dev", "Diego", "Edda", "Eli", "Elif", "Emil", "Ena", "Erik", "Esme", "Ewan", "Farah",
	"Felix", "Femi", "Finn", "Freya", "Gil", "Grace", "Hana", "Hamid", "Hugo", "Ida", "Imani", "Ines", "Ivan", "Jack",
	"Jade", "Jamal", "Jana", "Jonas", "Jun", "Kai", "Kalani", "Kemal", "Kenji", "Kiri", "Lars", "Leila", "Leo", "Lina",
	"Luca", "Luis", "Mae", "Maia", "Malik", "Mara", "Marco", "Mateo", "Mei", "Mila", "Milo", "Nadia", "Nia", "Nico",
	"Nils", "Noor", "Olga", "Omar", "Oona", "Oscar", "Pablo", "Pia", "Priya", "Quinn", "Rafa", "Rania", "Ravi", "Rhea",
	"Rio", "Rosa", "Rory", "Ruth", "Sami", "Sanna", "Sara", "Sean", "Sina", "Sofia", "Sven", "Tae", "Tariq", "Tess",
	"Theo", "Tomas", "Uma", "Una", "Vera", "Viktor", "Wanda", "Wei", "Wren", "Xavi", "Yara", "Yusuf", "Zane", "Zara",
]
const LAST_NAMES: Array[String] = [
	"Abara", "Albers", "Andersen", "Arslan", "Baker", "Banda", "Barros", "Berg", "Blackwood", "Brandt", "Byrne", "Castillo",
	"Chen", "Costa", "Dahl", "Dubois", "Eriksen", "Farrow", "Ferreira", "Fischer", "Flint", "Fraser", "Garcia", "Grant",
	"Haddad", "Hale", "Hansen", "Harbour", "Hayashi", "Holm", "Ibrahim", "Ito", "Jansen", "Jensen", "Kahale", "Kaplan",
	"Keel", "Khan", "Kim", "Kowalski", "Lang", "Larsen", "Lee", "Lindqvist", "Lopez", "MacLeod", "Marin", "Mendes",
	"Moreau", "Murphy", "Nakamura", "Navarro", "Nguyen", "Nilsen", "Novak", "Nwosu", "O'Brien", "Okafor", "Olsen",
	"Ortega", "Park", "Patel", "Pereira", "Petrov", "Quayle", "Rahman", "Reyes", "Rossi", "Saito", "Santos", "Schmidt",
	"Shore", "Silva", "Singh", "Sorensen", "Stone", "Storm", "Suzuki", "Tanaka", "Tide", "Torres", "Vance", "Varga",
	"Vos", "Walsh", "Ward", "Wave", "Weber", "Wright", "Yilmaz", "Young", "Zhang",
]


## How many options a part has.
static func option_count(key: String) -> int:
	for part: Array in PARTS:
		if part[0] == key:
			return (part[2] as Array).size()
	return 1


## The name of a look's choice for a part ("Round glasses").
static func option_name(key: String, index: int) -> String:
	for part: Array in PARTS:
		if part[0] == key:
			var names: Array = part[2]
			return str(names[clampi(index, 0, names.size() - 1)])
	return ""


## A look's slider (0 to 100; 50 when it has none: looks from before the sliders).
static func slider(look: Dictionary, key: String) -> int:
	var value: Variant = look.get(key, 50)
	return clampi(int(value) if value is int or value is float else 50, 0, 100)


static func random_name(rng: RandomNumberGenerator) -> String:
	return "%s %s" % [FIRST_NAMES[rng.randi() % FIRST_NAMES.size()], LAST_NAMES[rng.randi() % LAST_NAMES.size()]]


## A character as sent from elsewhere (a joining player's CEO), made safe: its
## name trimmed to MAX_NAME_LENGTH, its look's parts whole numbers within
## their options (missing ones the first) and its sliders within 0 to 100
## (missing ones the middle). {} if it has no name.
static func clean(character: Dictionary) -> Dictionary:
	var name := str(character.get("name", "")).strip_edges().left(MAX_NAME_LENGTH)
	if name.is_empty():
		return {}
	var given: Variant = character.get("look", {})
	var look := {}
	for part: Array in PARTS:
		var key: String = part[0]
		var value: Variant = (given as Dictionary).get(key, 0) if given is Dictionary else 0
		look[key] = clampi(int(value) if value is int or value is float else 0, 0, (part[2] as Array).size() - 1)
	for slide: Array in SLIDERS:
		var key: String = slide[0]
		look[key] = slider(given, key) if given is Dictionary else 50
	return {name = name, look = look}


## A look with every part chosen at random (the parts that can be left off,
## often none: NONE_CHANCES; a female body never a random beard), and the
## sliders mostly middling (the sum of two rolls).
static func random_look(rng: RandomNumberGenerator) -> Dictionary:
	var look := {}
	for part: Array in PARTS:
		var key: String = part[0]
		var count := (part[2] as Array).size()
		if NONE_CHANCES.has(key):
			look[key] = 0 if rng.randf() < float(NONE_CHANCES[key]) else rng.randi_range(1, count - 1)
		else:
			look[key] = rng.randi() % count
	if int(look.body) == 1:
		look.facial_hair = 0
	for slide: Array in SLIDERS:
		look[slide[0]] = rng.randi_range(0, 50) + rng.randi_range(0, 50)
	return look


static func random_character(rng: RandomNumberGenerator) -> Dictionary:
	return {name = random_name(rng), look = random_look(rng)}


## A ship's officers made up for a model: the captain first, then the mates
## (GameState.crew_of()). seed -1 for a random lot.
static func officers_for(model: Dictionary, seed := -1) -> Array:
	var rng := RandomNumberGenerator.new()
	if seed >= 0:
		rng.seed = seed
	else:
		rng.randomize()
	var officers := []
	for i in maxi(int(GameState.crew_of(model)[0]), 1):
		officers.append(random_character(rng))
	return officers


## What an officer is called aboard: the first the Captain, the rest Mates.
static func rank(index: int) -> String:
	return "Captain" if index == 0 else "Mate"
