# Copyright (c) 2026 Rory Ferrick. All rights reserved. Maritime Empire.
class_name Characters
extends RefCounted
## People: the company's CEO (made on the New Company screen) and each ship's
## officers, its captain and mates (GameState.crew_of(): one officer for the
## smaller ships, up to four for the biggest), made up at random when the ship
## is bought. A character is {name, look}, look a choice (an index into
## PARTS' options) for each part; Portrait draws them.

## The parts of a look, in the order the CEO screen lists them: [key, title,
## option names]. Portrait draws each option.
const PARTS := [
	["skin", "Skin", ["Porcelain", "Fair", "Light", "Light olive", "Olive", "Tan", "Bronze", "Brown", "Dark brown", "Deep"]],
	["eyes", "Eyes", ["Round brown", "Round blue", "Round green", "Narrow brown", "Narrow hazel", "Wide blue", "Sleepy grey", "Lashes brown", "Lashes green", "Smiling"]],
	["nose", "Nose", ["Button", "Long", "Wide", "Pointed", "Hooked", "Small", "Roman", "Snub", "Broad", "Freckled"]],
	["mouth", "Mouth", ["Smile", "Grin", "Straight", "Smirk", "Laugh", "Surprised", "Frown", "Red lips", "Cheeky", "Gentle"]],
	["hair", "Hair style", ["Bald", "Buzz cut", "Short", "Side part", "Long", "Bob", "Ponytail", "Curly", "Mohawk", "Bun"]],
	["hair_color", "Hair color", ["Black", "Dark brown", "Brown", "Light brown", "Auburn", "Ginger", "Strawberry blonde", "Blonde", "Platinum", "Grey", "White", "Blue", "Pink", "Green"]],
	["facial_hair", "Facial hair", ["None", "Stubble", "Moustache", "Goatee", "Full beard", "Chinstrap", "Handlebar", "Soul patch", "Mutton chops", "Long beard"]],
	["top", "Top", ["White tee", "Red tee", "Captain's jacket", "Grey hoodie", "Sailor stripes", "Green jumper", "Yellow polo", "Black suit", "Plaid flannel", "Hi-vis vest"]],
	["bottoms", "Bottoms", ["Jeans", "Khakis", "Black trousers", "Navy shorts", "Cargo trousers", "White trousers", "Corduroys", "Red skirt", "Navy skirt", "Denim shorts"]],
	["shoes", "Shoes", ["White trainers", "Black boots", "Brown boots", "Dress shoes", "Red trainers", "Sandals", "Yellow wellies", "Blue trainers", "Loafers", "Green wellies"]],
	["eyewear", "Glasses", ["None", "Round", "Square", "Sunglasses", "Aviators", "Monocle", "Half-rims", "Cat-eye", "Goggles", "Eye patch"]],
	["headwear", "Hat", ["None", "Captain's cap", "Beanie", "Baseball cap", "Bucket hat", "Cowboy hat", "Bandana", "Top hat", "Sailor cap", "Hard hat"]],
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


static func random_name(rng: RandomNumberGenerator) -> String:
	return "%s %s" % [FIRST_NAMES[rng.randi() % FIRST_NAMES.size()], LAST_NAMES[rng.randi() % LAST_NAMES.size()]]


## A look with every part chosen at random (the parts that can be left off,
## often none: NONE_CHANCES).
static func random_look(rng: RandomNumberGenerator) -> Dictionary:
	var look := {}
	for part: Array in PARTS:
		var key: String = part[0]
		var count := (part[2] as Array).size()
		if NONE_CHANCES.has(key):
			look[key] = 0 if rng.randf() < float(NONE_CHANCES[key]) else rng.randi_range(1, count - 1)
		else:
			look[key] = rng.randi() % count
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
