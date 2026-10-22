# Copyright (c) 2026 Rory Ferrick. All rights reserved. Maritime Empire.
## Hand-compiled 2016 production figures for tools/build_world_data.gd: the
## producers making the bulk of world output of each good (the rest of the
## world shares what's left as small producers in the economy), rounded, from
## the published figures: USGS Mineral Commodity Summaries 2017 and 2018 (2016
## columns; public domain), the EIA International Energy Statistics and the BP
## Statistical Review 2017 (oil, gas, refining), FAO fishery yearbooks 2016 (the
## catch by family; farmed salmon included), OICA 2016 production statistics
## (cars and commercial vehicles), and the industry's own figures for steel
## (worldsteel), plastics (PlasticsEurope) and fertilizer (IFA). Close, not exact.
##
## Each good: [unit, {ISO3: amount}]. Units: t (tonnes), t_metal (tonnes of the
## metal contained in the ore), t_oxide (tonnes of rare earth oxide), m3,
## units (vehicles, boats). Manufactured goods with no single source are
## spread by each country's share of world manufacturing value added
## (SPECIALTIES tilt it).

const MILLION := 1000000.0

const GOODS := {
	# --- Ores and minerals (mine output) ---
	"iron": ["t", {"AUS": 858e6, "BRA": 430e6, "CHN": 348e6, "IND": 185e6, "RUS": 101e6, "ZAF": 66e6, "UKR": 63e6, "CAN": 47e6,
		"USA": 42e6, "IRN": 35e6, "SWE": 27e6, "KAZ": 25e6, "CHL": 15e6, "MRT": 13e6, "PER": 10e6, "MEX": 10e6}],
	"coal": ["t", {"CHN": 3410e6, "IND": 690e6, "USA": 660e6, "AUS": 503e6, "IDN": 456e6, "RUS": 385e6, "ZAF": 250e6, "DEU": 176e6,
		"POL": 131e6, "KAZ": 103e6, "COL": 90e6, "TUR": 70e6, "CAN": 62e6, "VNM": 38e6, "MNG": 35e6, "UKR": 41e6}],
	"gold": ["t_metal", {"CHN": 455, "AUS": 290, "RUS": 250, "USA": 222, "CAN": 165, "PER": 153, "ZAF": 145, "MEX": 111, "UZB": 100,
		"GHA": 80, "IDN": 80, "BRA": 85, "KAZ": 75, "PNG": 62, "ARG": 58, "COL": 60, "CHL": 45, "TZA": 45, "MLI": 50, "SDN": 70}],
	"copper_ore": ["t_metal", {"CHL": 5550e3, "PER": 2350e3, "CHN": 1740e3, "USA": 1430e3, "COD": 1020e3, "AUS": 948e3, "ZMB": 763e3,
		"MEX": 766e3, "IDN": 727e3, "CAN": 708e3, "RUS": 702e3, "KAZ": 620e3, "POL": 424e3, "BRA": 300e3, "IRN": 280e3}],
	"bauxite": ["t", {"AUS": 82e6, "CHN": 65e6, "BRA": 34e6, "GIN": 32e6, "IND": 25e6, "JAM": 8.5e6, "RUS": 5.4e6, "KAZ": 5e6,
		"SAU": 4e6, "GRC": 1.8e6, "VNM": 1.5e6, "MYS": 1.5e6, "SUR": 1.6e6, "GUY": 1.5e6}],
	"nickel_ore": ["t_metal", {"PHL": 347e3, "CAN": 236e3, "RUS": 222e3, "NCL": 213e3, "AUS": 204e3, "IDN": 199e3, "BRA": 160e3,
		"CHN": 98e3, "GTM": 56e3, "CUB": 51e3, "ZAF": 49e3, "COL": 37e3}],
	"zinc_ore": ["t_metal", {"CHN": 4500e3, "PER": 1340e3, "AUS": 850e3, "USA": 805e3, "IND": 682e3, "MEX": 669e3, "BOL": 486e3,
		"KAZ": 336e3, "CAN": 322e3, "RUS": 284e3, "SWE": 248e3, "IRL": 115e3}],
	"tin_ore": ["t_metal", {"CHN": 92e3, "MMR": 63e3, "IDN": 52e3, "BRA": 25e3, "BOL": 18e3, "PER": 18e3, "AUS": 7e3, "COD": 7e3,
		"VNM": 5e3, "MYS": 4e3, "RWA": 2e3}],
	"lithium_ore": ["t_metal", {"CHL": 14300, "AUS": 14000, "ARG": 5800, "CHN": 2300, "ZWE": 1000, "PRT": 400, "BRA": 200}],
	"silver_ore": ["t_metal", {"MEX": 5600, "PER": 4400, "CHN": 3600, "CHL": 1500, "AUS": 1400, "POL": 1400, "RUS": 1400, "BOL": 1350,
		"USA": 1100, "KAZ": 950, "ARG": 900}],
	"phosphate": ["t", {"CHN": 138e6, "MAR": 30e6, "USA": 27.8e6, "RUS": 12.4e6, "JOR": 8.3e6, "BRA": 5.2e6, "EGY": 5e6, "SAU": 4.5e6,
		"ISR": 4e6, "PER": 3.8e6, "TUN": 3.6e6, "VNM": 2.8e6, "AUS": 2.6e6, "KAZ": 1.6e6}],
	"manganese_ore": ["t_metal", {"ZAF": 5300e3, "CHN": 2500e3, "AUS": 2200e3, "GAB": 1600e3, "BRA": 1000e3, "IND": 760e3,
		"GHA": 550e3, "UKR": 380e3, "MYS": 250e3, "KAZ": 210e3}],
	"rare_earth_ore": ["t_oxide", {"CHN": 105000, "AUS": 14000, "RUS": 3000, "BRA": 2200, "THA": 1600, "IND": 1500, "MYS": 300, "VNM": 300}],
	"timber": ["m3", {"USA": 360e6, "RUS": 200e6, "CHN": 160e6, "CAN": 155e6, "BRA": 140e6, "SWE": 70e6, "IDN": 70e6, "FIN": 56e6,
		"IND": 50e6, "DEU": 45e6, "CHL": 45e6, "POL": 40e6, "NZL": 30e6, "AUS": 30e6, "FRA": 25e6, "VNM": 25e6, "JPN": 20e6, "ZAF": 16e6,
		"UKR": 15e6, "MYS": 15e6, "NOR": 10e6}],
	# --- Metals and processed materials ---
	"steel": ["t", {"CHN": 808e6, "JPN": 105e6, "IND": 95.5e6, "USA": 78.5e6, "RUS": 70.5e6, "KOR": 68.6e6, "DEU": 42.1e6, "TUR": 33.2e6,
		"BRA": 31.3e6, "UKR": 24.2e6, "ITA": 23.4e6, "TWN": 21.8e6, "MEX": 18.8e6, "IRN": 17.9e6, "FRA": 14.4e6, "ESP": 13.6e6,
		"CAN": 12.6e6, "POL": 9e6, "VNM": 7.8e6, "BEL": 7.7e6, "GBR": 7.6e6, "AUT": 7.4e6, "NLD": 6.9e6, "ZAF": 6.1e6, "SAU": 5.5e6,
		"AUS": 5.3e6, "EGY": 5e6}],
	"aluminium": ["t", {"CHN": 31870e3, "RUS": 3560e3, "CAN": 3210e3, "IND": 2900e3, "ARE": 2470e3, "AUS": 1640e3, "NOR": 1250e3,
		"BHR": 970e3, "ISL": 870e3, "SAU": 869e3, "USA": 818e3, "BRA": 790e3, "ZAF": 717e3, "MYS": 650e3, "QAT": 620e3, "MOZ": 570e3,
		"DEU": 547e3, "ARG": 430e3, "OMN": 380e3, "FRA": 360e3, "NZL": 340e3, "ESP": 340e3}],
	"copper": ["t", {"CHN": 8436e3, "CHL": 2610e3, "JPN": 1553e3, "USA": 1100e3, "RUS": 870e3, "COD": 830e3, "IND": 760e3,
		"DEU": 672e3, "KOR": 607e3, "ZMB": 590e3, "POL": 536e3, "AUS": 467e3, "MEX": 435e3, "KAZ": 410e3, "ESP": 375e3, "BEL": 350e3,
		"PER": 310e3, "CAN": 290e3}],
	"nickel": ["t", {"CHN": 412e3, "RUS": 186e3, "JPN": 185e3, "CAN": 160e3, "AUS": 108e3, "NOR": 92e3, "NCL": 72e3, "BRA": 70e3,
		"FIN": 60e3, "ZAF": 48e3, "MDG": 48e3, "GBR": 39e3}],
	"zinc": ["t", {"CHN": 6273e3, "KOR": 1000e3, "IND": 760e3, "CAN": 691e3, "MEX": 640e3, "JPN": 534e3, "ESP": 509e3, "AUS": 482e3,
		"PER": 330e3, "KAZ": 324e3, "FIN": 290e3, "NLD": 270e3, "BEL": 260e3, "NOR": 160e3, "USA": 115e3}],
	"tin": ["t", {"CHN": 182e3, "IDN": 62e3, "MYS": 27e3, "PER": 18e3, "BOL": 13e3, "BRA": 12e3, "THA": 11e3, "BEL": 9e3}],
	"lithium": ["t", {"CHL": 74e3, "CHN": 50e3, "ARG": 30e3, "USA": 4e3}],
	"gold_bars": ["t", {"CHE": 1500, "CHN": 450, "ARE": 400, "AUS": 300, "IND": 300, "USA": 250, "RUS": 230, "ZAF": 150, "CAN": 150,
		"JPN": 140, "HKG": 120, "TUR": 100}],
	"silver_bars": ["t", {"MEX": 5000, "CHN": 5000, "JPN": 1900, "KOR": 1800, "POL": 1400, "PER": 1300, "RUS": 1200, "IND": 800,
		"AUS": 700, "USA": 600, "DEU": 500}],
	"ferromanganese": ["t", {"CHN": 2600e3, "IND": 900e3, "ZAF": 700e3, "KOR": 450e3, "UKR": 400e3, "JPN": 300e3, "NOR": 300e3,
		"RUS": 250e3, "BRA": 200e3, "AUS": 200e3, "KAZ": 100e3}],
	"rare_earths": ["t_oxide", {"CHN": 100000, "MYS": 15000, "EST": 3000, "RUS": 2000, "IND": 1000}],
	"fertilizer": ["t", {"CHN": 60e6, "RUS": 20e6, "USA": 22e6, "IND": 18e6, "CAN": 14e6, "MAR": 8e6, "BLR": 7e6, "IDN": 7e6,
		"SAU": 5e6, "EGY": 5e6, "DEU": 4e6, "PAK": 4e6, "TTO": 3.5e6, "QAT": 3e6, "IRN": 3e6, "BRA": 3e6, "NLD": 3e6, "POL": 2.5e6,
		"UKR": 2.5e6, "VNM": 2.5e6, "AUS": 2e6, "OMN": 2e6, "JOR": 2e6}],
	"plastics": ["t", {"CHN": 98e6, "USA": 60e6, "DEU": 20e6, "KOR": 15e6, "IND": 15e6, "SAU": 14e6, "JPN": 13e6, "TWN": 10e6,
		"BRA": 7e6, "RUS": 7e6, "IRN": 7e6, "THA": 7e6, "BEL": 6e6, "NLD": 6e6, "SGP": 5e6, "FRA": 5e6, "ITA": 5e6, "CAN": 5e6,
		"ESP": 4e6, "MYS": 4e6, "MEX": 4e6, "ARE": 3e6, "QAT": 2e6, "KWT": 2e6}],
	# --- Energy (crude and condensate in tonnes: 1 million barrels a day is about 49.8 Mt a year) ---
	"oil": ["t", {"RUS": 548e6, "SAU": 521e6, "USA": 441e6, "IRQ": 219e6, "IRN": 229e6, "CAN": 222e6, "CHN": 199e6, "ARE": 154e6,
		"KWT": 149e6, "BRA": 129e6, "MEX": 122e6, "VEN": 115e6, "NOR": 100e6, "NGA": 95e6, "QAT": 95e6, "AGO": 90e6, "KAZ": 82e6,
		"DZA": 80e6, "OMN": 50e6, "GBR": 50e6, "COL": 44e6, "IDN": 44e6, "IND": 43e6, "AZE": 42e6, "MYS": 34e6, "EGY": 34e6,
		"ARG": 30e6, "ECU": 27e6, "LBY": 20e6, "AUS": 18e6, "VNM": 16e6, "COG": 14e6, "GNQ": 13e6, "GAB": 10e6, "SSD": 6e6, "TTO": 4e6}],
	# Natural gas (as LNG tonnes: 1 billion cubic metres is about 0.735 Mt).
	"gas": ["t", {"USA": 551e6, "RUS": 470e6, "IRN": 148e6, "QAT": 133e6, "CAN": 112e6, "CHN": 101e6, "NOR": 86e6, "SAU": 80e6,
		"DZA": 67e6, "AUS": 67e6, "MYS": 54e6, "IDN": 51e6, "TKM": 49e6, "UZB": 46e6, "ARE": 45e6, "NLD": 35e6, "MEX": 35e6,
		"NGA": 33e6, "EGY": 31e6, "GBR": 31e6, "PAK": 30e6, "ARG": 28e6, "THA": 28e6, "TTO": 26e6, "OMN": 26e6, "IND": 21e6,
		"BRA": 17e6, "BOL": 15e6, "AZE": 13e6, "MMR": 13e6, "KWT": 12e6, "BHR": 12e6, "LBY": 11e6, "PER": 10e6, "BRN": 9e6,
		"PNG": 8e6, "IRQ": 7e6}],
	"ammonia": ["t", {"CHN": 46e6, "RUS": 13e6, "IND": 11e6, "USA": 10e6, "IDN": 5e6, "TTO": 5e6, "SAU": 4e6, "CAN": 4e6, "UKR": 3e6,
		"EGY": 3e6, "QAT": 3e6, "PAK": 3e6, "IRN": 3e6, "DEU": 2.5e6, "POL": 2e6, "NLD": 2e6, "DZA": 2e6, "OMN": 2e6, "MYS": 1.5e6,
		"AUS": 1.5e6}],
	# Hydrogen wasn't shipped in 2016: none, until technology brings it.
	"hydrogen": ["t", {}],
	# --- Seafood (tonnes caught, by family; salmon includes farmed) ---
	"tuna": ["t", {"IDN": 750e3, "JPN": 400e3, "TWN": 400e3, "CHN": 400e3, "PHL": 350e3, "ESP": 300e3, "KOR": 300e3, "ECU": 250e3,
		"USA": 200e3, "PNG": 200e3, "IRN": 200e3, "KIR": 150e3, "MEX": 130e3, "FRA": 100e3, "MDV": 100e3, "LKA": 100e3}],
	"billfish": ["t", {"TWN": 30e3, "ESP": 30e3, "JPN": 20e3, "IDN": 20e3, "CHN": 20e3, "MEX": 10e3, "CHL": 10e3, "ECU": 10e3,
		"KOR": 10e3, "PHL": 10e3, "LKA": 10e3, "USA": 5e3}],
	"salmon": ["t", {"NOR": 1230e3, "CHL": 730e3, "USA": 450e3, "RUS": 430e3, "GBR": 160e3, "CAN": 150e3, "JPN": 130e3,
		"FRO": 80e3, "AUS": 60e3, "ISL": 10e3, "NZL": 10e3}],
	"whitefish": ["t", {"RUS": 2000e3, "USA": 1600e3, "NOR": 750e3, "ISL": 500e3, "CHN": 400e3, "ARG": 300e3, "NAM": 300e3,
		"JPN": 200e3, "KOR": 200e3, "ZAF": 150e3, "GBR": 150e3, "CAN": 100e3, "CHL": 100e3, "DNK": 100e3, "FRO": 100e3}],
	"flatfish": ["t", {"USA": 300e3, "CHN": 150e3, "RUS": 100e3, "NLD": 100e3, "NOR": 50e3, "JPN": 50e3, "KOR": 50e3, "GBR": 40e3,
		"DNK": 40e3, "CAN": 30e3, "ISL": 30e3}],
	"small_pelagic": ["t", {"PER": 3000e3, "CHN": 1500e3, "MAR": 1000e3, "CHL": 900e3, "NOR": 600e3, "IDN": 600e3, "MEX": 600e3,
		"RUS": 500e3, "IND": 500e3, "JPN": 400e3, "USA": 400e3, "MRT": 400e3, "VNM": 300e3, "PHL": 300e3, "DNK": 300e3, "ECU": 300e3,
		"ZAF": 300e3, "ISL": 200e3, "GBR": 200e3}],
	"mackerel": ["t", {"CHN": 500e3, "JPN": 400e3, "CHL": 400e3, "IDN": 400e3, "NOR": 250e3, "RUS": 200e3, "GBR": 200e3, "ISL": 170e3,
		"KOR": 150e3, "FRO": 120e3, "THA": 100e3, "IRL": 70e3, "PER": 70e3}],
	"game_fish": ["t", {"IDN": 300e3, "PHL": 100e3, "VNM": 100e3, "IND": 100e3, "MEX": 50e3, "THA": 50e3, "MYS": 50e3, "PER": 50e3,
		"USA": 30e3, "BRA": 30e3, "ECU": 30e3, "TWN": 30e3, "LKA": 30e3, "AUS": 20e3}],
	"king_crab": ["t", {"RUS": 50e3, "USA": 10e3, "JPN": 3e3, "NOR": 2e3}],
	"snow_crab": ["t", {"CAN": 100e3, "RUS": 70e3, "USA": 40e3, "JPN": 30e3, "KOR": 20e3, "NOR": 10e3, "GRL": 5e3}],
	"dungeness_crab": ["t", {"USA": 30e3, "CAN": 10e3}],
	"blue_crab": ["t", {"USA": 70e3, "MEX": 10e3}],
	"stone_crab": ["t", {"USA": 1200, "MEX": 500, "BHS": 200}],
	"rock_crab": ["t", {"GBR": 30e3, "IRL": 8e3, "FRA": 6e3, "NOR": 6e3, "USA": 5e3, "CAN": 5e3}],
	"swimming_crab": ["t", {"CHN": 400e3, "IDN": 100e3, "PHL": 40e3, "IND": 40e3, "THA": 30e3, "VNM": 30e3, "KOR": 20e3,
		"MYS": 10e3, "LKA": 5e3, "AUS": 3e3}],
	"deepwater_crab": ["t", {"JPN": 10e3, "NAM": 4e3, "USA": 3e3, "ZAF": 1e3, "AUS": 500}],
	"crayfish": ["t", {"CHN": 900e3, "USA": 50e3, "AUS": 10e3, "BRA": 8e3, "BHS": 5e3, "CUB": 4e3, "NZL": 3e3, "ZAF": 2e3}],
	# --- Vehicles (units made) ---
	"cars": ["units", {"CHN": 24.4e6, "JPN": 7.9e6, "DEU": 5.7e6, "USA": 3.9e6, "KOR": 4.0e6, "IND": 3.7e6, "ESP": 2.35e6, "MEX": 1.99e6,
		"BRA": 1.78e6, "GBR": 1.72e6, "FRA": 1.63e6, "CZE": 1.34e6, "RUS": 1.12e6, "IRN": 1.07e6, "SVK": 1.04e6, "IDN": 0.97e6,
		"TUR": 0.95e6, "CAN": 0.8e6, "THA": 0.8e6, "ITA": 0.71e6, "POL": 0.55e6, "MYS": 0.47e6, "HUN": 0.47e6, "ROU": 0.36e6,
		"BEL": 0.35e6, "ZAF": 0.33e6, "TWN": 0.25e6, "ARG": 0.24e6, "SWE": 0.2e6, "AUS": 0.16e6, "SVN": 0.13e6}],
	"trucks": ["units", {"USA": 8.3e6, "CHN": 3.7e6, "MEX": 1.6e6, "CAN": 1.6e6, "JPN": 1.3e6, "THA": 1.2e6, "IND": 0.8e6, "ESP": 0.53e6,
		"TUR": 0.53e6, "FRA": 0.45e6, "ITA": 0.39e6, "BRA": 0.37e6, "DEU": 0.34e6, "ZAF": 0.27e6, "ARG": 0.23e6, "KOR": 0.2e6,
		"IDN": 0.21e6, "RUS": 0.18e6, "POL": 0.13e6, "VNM": 0.13e6, "IRN": 0.1e6, "GBR": 0.09e6}],
	"boats": ["units", {"USA": 250e3, "CHN": 50e3, "ITA": 30e3, "FRA": 30e3, "CAN": 20e3, "POL": 20e3, "JPN": 20e3, "NLD": 10e3,
		"GBR": 10e3, "DEU": 10e3, "FIN": 10e3, "SWE": 10e3, "NOR": 10e3, "AUS": 10e3, "TUR": 10e3, "BRA": 10e3, "TWN": 5e3, "NZL": 5e3}],
}

## Refining: crude run in tonnes a year (2016 throughput, million barrels a day
## x 49.8 Mt); diesel, gasoline, jet fuel and LPG are its shares of that.
const REFINING := {"USA": 807e6, "CHN": 538e6, "RUS": 279e6, "IND": 244e6, "JPN": 164e6, "KOR": 149e6, "SAU": 134e6, "BRA": 95e6,
	"DEU": 95e6, "IRN": 90e6, "CAN": 90e6, "ITA": 70e6, "ESP": 65e6, "SGP": 60e6, "FRA": 55e6, "GBR": 55e6, "NLD": 55e6, "THA": 55e6,
	"ARE": 55e6, "MEX": 46e6, "TWN": 45e6, "KWT": 45e6, "VEN": 45e6, "IDN": 42e6, "BEL": 32e6, "IRQ": 30e6, "DZA": 30e6, "TUR": 27e6,
	"EGY": 25e6, "POL": 25e6, "GRC": 25e6, "ZAF": 22e6, "AUS": 20e6}
const REFINED_SHARES := {"diesel": 0.35, "gasoline": 0.30, "jet_fuel": 0.08, "lpg": 0.04}

## Manufactured goods spread by manufacturing value added, tilted: good ->
## {ISO3: weight} (everyone else OTHER_WEIGHT).
const OTHER_WEIGHT := 0.4
const SPECIALTIES := {
	"toys": {"CHN": 6.0, "VNM": 2.0, "IDN": 1.5, "MEX": 1.2, "THA": 1.0},
	"clothing": {"BGD": 6.0, "KHM": 6.0, "VNM": 4.0, "CHN": 3.0, "LKA": 3.0, "MMR": 3.0, "IND": 2.0, "TUR": 2.0, "PAK": 2.0, "IDN": 1.5, "ITA": 1.0},
	"furniture": {"CHN": 3.0, "VNM": 3.0, "POL": 3.0, "ITA": 2.0, "MYS": 2.0, "IDN": 1.5, "DEU": 1.0, "USA": 1.0},
	"electronics": {"CHN": 4.0, "TWN": 4.0, "KOR": 3.0, "VNM": 3.0, "MYS": 3.0, "SGP": 2.0, "PHL": 2.0, "JPN": 1.5, "THA": 1.5, "MEX": 1.5},
	"appliances": {"CHN": 3.0, "KOR": 2.0, "THA": 2.0, "TUR": 2.0, "MEX": 2.0, "ITA": 1.5, "POL": 1.5, "DEU": 1.0},
	"machine_parts": {"DEU": 2.5, "JPN": 2.0, "CHE": 2.0, "AUT": 2.0, "ITA": 1.8, "CZE": 1.5, "USA": 1.2, "KOR": 1.2, "CHN": 1.0},
	"batteries": {"CHN": 4.0, "KOR": 3.0, "JPN": 3.0, "USA": 0.6, "POL": 0.5},
	"solar_panels": {"CHN": 8.0, "MYS": 4.0, "VNM": 2.0, "THA": 2.0, "TWN": 2.0, "KOR": 1.5, "JPN": 0.8, "IND": 0.6, "DEU": 0.4, "USA": 0.3},
	"tools": {"CHN": 3.0, "TWN": 3.0, "DEU": 1.5, "JPN": 1.0, "USA": 1.0},
	"sporting_goods": {"CHN": 4.0, "TWN": 2.0, "VNM": 2.0, "PAK": 2.0, "IDN": 1.5},
	"footwear": {"VNM": 5.0, "CHN": 4.0, "IDN": 3.0, "IND": 2.0, "BGD": 2.0, "KHM": 2.0, "BRA": 1.5, "ITA": 1.5, "MEX": 1.0},
	"cosmetics": {"FRA": 3.0, "KOR": 2.5, "JPN": 1.5, "ITA": 1.5, "DEU": 1.3, "USA": 1.2, "GBR": 1.2, "BRA": 1.2, "CHN": 1.0},
	"medicine": {"CHE": 4.0, "IRL": 4.0, "BEL": 2.5, "DNK": 2.5, "IND": 2.0, "SGP": 2.0, "USA": 1.5, "DEU": 1.5, "GBR": 1.5, "FRA": 1.3, "ITA": 1.2, "JPN": 1.0, "CHN": 0.8},
}
