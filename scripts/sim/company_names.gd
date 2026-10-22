# Copyright (c) 2026 Rory Ferrick. All rights reserved. Maritime Empire.
class_name CompanyNames
## Made-up names for the world's AI companies (Producers, ShippingFirms),
## styled by country and trade: "Kyma Maritime", "Seto Kaiun", "Elbe
## Reederei", "Minas Ironworks". Built from place and flavour words, never real
## company names; a name already taken gets the next combination.

## Shipping firms: country -> [first words, last words].
const SHIPPING := {
	"GRC": [["Aegean", "Ionian", "Cycladic", "Kyma", "Thalassa", "Argo", "Delos", "Saronic", "Thermaic", "Ithaca", "Kalamata", "Lesvos", "Chios", "Andros", "Pelagos", "Zephyros"], ["Maritime", "Shipping", "Navigation", "Bulkers", "Tankers", "Carriers", "Shipmanagement"]],
	"JPN": [["Seto", "Kanmon", "Sakura", "Hokuto", "Tsurumi", "Kaiyo", "Shiokaze", "Asahi", "Hayate", "Kurenai", "Aozora", "Minato", "Nagisa", "Umikaze"], ["Kaiun", "Kisen", "Marine", "Line", "Shosen"]],
	"CHN": [["Huanghai", "Donghai", "Nanhai", "Changjiang", "Haixing", "Bohai", "Minjiang", "Zhujiang", "Huaxia", "Tianhai", "Jinhai", "Ruihai"], ["Shipping", "Ocean", "Maritime", "Navigation", "Lines"]],
	"DEU": [["Hanseatic", "Elbe", "Weser", "Nordsee", "Ostsee", "Alster", "Jade", "Ems", "Kiel", "Trave", "Helgoland", "Fehmarn"], ["Reederei", "Schiffahrt", "Linie", "Bulk", "Shipping"]],
	"NOR": [["Fjord", "Nordkapp", "Skagerrak", "Hordaland", "Lofoten", "Vestland", "Haugland", "Trondelag", "Nordlys", "Sognefjord"], ["Rederi", "Shipping", "Tankers", "Gas", "Bulk"]],
	"DNK": [["Kattegat", "Oresund", "Jutland", "Skagen", "Funen", "Limfjord", "Bornholm", "Lillebaelt"], ["Rederi", "Line", "Tankers", "Shipping"]],
	"SGP": [["Merlion", "Straits", "Jurong", "Sentosa", "Raffles Quay", "Tanjong", "Pasir"], ["Shipping", "Maritime", "Navigation", "Tankers"]],
	"HKG": [["Victoria", "Kowloon", "Lantau", "Tsing Yi", "Harbour", "Pearl River", "Stonecutters", "Lamma"], ["Shipping", "Maritime", "Navigation", "Lines"]],
	"KOR": [["Hanbada", "Donghae", "Namhae", "Seohae", "Gaya", "Baekje", "Jeju", "Taebaek", "Hallim"], ["Shipping", "Marine", "Line", "Kaiun"]],
	"TWN": [["Formosa Sea", "Kaohsiung", "Keelung", "Penghu", "Tamsui", "Alishan", "Jade Mountain"], ["Marine", "Shipping", "Line"]],
	"USA": [["Freeport", "Chesapeake", "Gulf Coast", "Pacific Rim", "Great Lakes", "Delaware", "Puget", "Atlantic Star", "Bayou", "Columbia"], ["Shipping", "Marine", "Lines", "Tankers", "Navigation"]],
	"GBR": [["Albion", "Solent", "Mersey", "Clyde", "Thames", "Tyne", "Humber", "Severn", "Channel"], ["Shipping", "Line", "Steamship", "Navigation", "Tankers"]],
	"TUR": [["Marmara", "Bosphorus", "Anatolia", "Ege", "Karadeniz", "Izmir", "Trabzon"], ["Denizcilik", "Shipping", "Maritime"]],
	"ITA": [["Tirreno", "Adriatica", "Liguria", "Sicilia", "Partenope", "Lanterna", "Capri"], ["Navigazione", "Shipping", "Marittima"]],
	"NLD": [["Zeeland", "Maas", "Waddenzee", "Scheldt", "Ijssel", "Friesland"], ["Shipping", "Scheepvaart", "Maritime"]],
	"BEL": [["Schelde", "Flanders", "Ostend", "Zeebrugge"], ["Shipping", "Maritime"]],
	"FRA": [["Armorique", "Iroise", "Gascogne", "Provence", "Normandie", "Loire"], ["Maritime", "Navigation", "Armement"]],
	"IND": [["Konkan", "Coromandel", "Malabar", "Kutch", "Ganga", "Kaveri"], ["Shipping", "Maritime", "Lines"]],
	"RUS": [["Baltika", "Neva", "Volga", "Primorye", "Kamchatka", "Severny"], ["Shipping", "Fleet", "Tankers"]],
	"BRA": [["Atlantico Sul", "Guanabara", "Amazonas", "Paranagua", "Bahia"], ["Navegacao", "Maritima", "Shipping"]],
	"IDN": [["Nusantara", "Samudra", "Java Sea", "Sunda", "Makassar", "Bahari"], ["Shipping", "Pelayaran", "Lines"]],
	"MYS": [["Selat", "Melaka", "Borneo", "Penang", "Langkawi"], ["Shipping", "Maritime"]],
	"ARE": [["Gulf Pearl", "Al Bahr", "Dhow", "Jumeirah", "Saadiyat"], ["Shipping", "Maritime", "Tankers"]],
	"SAU": [["Red Sea", "Al Khaleej", "Najd", "Hejaz"], ["Shipping", "Tankers", "Maritime"]],
	"IRN": [["Persian Gulf", "Caspian", "Hormuz", "Kish"], ["Shipping", "Tankers"]],
	"CAN": [["Laurentian", "Maritimes", "Pacific Coast", "Fundy", "Hudson"], ["Shipping", "Marine", "Steamship"]],
	"CHE": [["Leman", "Helvetia", "Rhine", "Alpine"], ["Shipping", "Maritime"]],
	"VNM": [["Ha Long", "Mekong", "Saigon River", "Hai Phong"], ["Shipping", "Maritime"]],
}
## Shipping firms elsewhere: [the port or country name] + one of these.
const SHIPPING_LAST := ["Shipping", "Maritime", "Lines", "Navigation", "Marine"]

## Producers by trade: trade -> last words (after a place name).
const TRADES := {
	"mining": ["Mining", "Minerals", "Resources", "Ore Company", "Mines"],
	"energy": ["Petroleum", "Energy", "Oil & Gas", "Hydrocarbons", "Petroleum Company"],
	"metals": ["Steel", "Metals", "Ironworks", "Smelting", "Alloys"],
	"farming": ["Agro", "Farms", "Growers", "Agricultural", "Harvest Co."],
	"fishing": ["Fisheries", "Seafoods", "Fishing Company", "Ocean Harvest"],
	"chemicals": ["Chemicals", "Petrochemicals", "Fertilizers", "Polymers"],
	"manufacturing": ["Industries", "Manufacturing", "Works", "Products", "Group"],
	"forestry": ["Timber", "Forest Products", "Lumber"],
}
## Multinationals' first words (with their trade's last words).
const GLOBAL_FIRST := ["Meridian", "Polaris", "Orion", "Atlas", "Solstice", "Zenith", "Equator", "Tropic", "Boreal", "Austral", "Halcyon",
	"Vantage", "Summit", "Keystone", "Lodestar", "Cardinal", "Paragon", "Pinnacle", "Horizon", "Crestline", "Bedrock", "Ironbark", "Silverline",
	"Northgate", "Southwind", "Evergreen", "Granite", "Obsidian", "Amberline", "Cobalt Bay"]
## Company-type endings by country (the rest: COMPANY_DEFAULT).
const COMPANY_ENDINGS := {"DEU": "AG", "AUT": "AG", "CHE": "AG", "FRA": "SA", "ESP": "SA", "BRA": "SA", "MEX": "SA", "ARG": "SA", "CHL": "SA",
	"PER": "SA", "COL": "SA", "ITA": "SpA", "NLD": "NV", "BEL": "NV", "SWE": "AB", "NOR": "ASA", "DNK": "A/S", "FIN": "Oy", "JPN": "KK",
	"CHN": "Co.", "KOR": "Co.", "IND": "Ltd", "GBR": "plc", "AUS": "Ltd", "ZAF": "Ltd", "USA": "Inc.", "CAN": "Inc.", "RUS": "PJSC", "IDN": "Tbk"}


## A shipping firm's name for a country (a port for its fallback), not in taken.
static func shipping(country: String, place: String, rng: RandomNumberGenerator, taken: Dictionary) -> String:
	var words: Array = SHIPPING.get(country, [[place], SHIPPING_LAST])
	return _pick(words[0], words[1], rng, taken)


## A producer's name: a place word and its trade's ending (and the country's company type, now and then).
static func producer(place: String, trade: String, country: String, rng: RandomNumberGenerator, taken: Dictionary) -> String:
	var ending := " " + str(COMPANY_ENDINGS.get(country, "")) if rng.randf() < 0.35 and COMPANY_ENDINGS.has(country) else ""
	var name := _pick([place], TRADES.get(trade, TRADES.manufacturing), rng, taken)
	if not ending.is_empty() and not taken.has(name + ending):
		taken.erase(name)
		name += ending
		taken[name] = true
	return name


## A multinational's name for a trade.
static func multinational(trade: String, rng: RandomNumberGenerator, taken: Dictionary) -> String:
	return _pick(GLOBAL_FIRST, TRADES.get(trade, TRADES.manufacturing), rng, taken)


## "First Last" from the lists, the first free combination from a random start.
static func _pick(first: Array, last: Array, rng: RandomNumberGenerator, taken: Dictionary) -> String:
	var a := rng.randi() % first.size()
	var b := rng.randi() % last.size()
	for i in first.size() * last.size():
		var name := "%s %s" % [first[(a + i / last.size()) % first.size()], last[(b + i) % last.size()]]
		if not taken.has(name):
			taken[name] = true
			return name
	var n := 2
	while taken.has("%s %s %d" % [first[a], last[b], n]):
		n += 1
	var numbered := "%s %s %d" % [first[a], last[b], n]
	taken[numbered] = true
	return numbered
