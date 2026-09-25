# Maritime Empire — Beta Spec

## Tech
- Engine: Godot 4 (standard build, GDScript). Target: Windows / Steam, mouse input, landscape only.
- Version control: Git. Keep game data (ports, ship models) in data files, not hard-coded.
- Placeholder visuals only (rectangles, circles, default Godot buttons). Structure UI so custom art can be swapped in later via a single Theme resource.
- Silent (no audio) for beta.

## Data & tools
- Game data lives in data/: ports.json (ports), ship_models.json (models, prices, speeds, ranges, limits, map look), ship_names.json (suggested ship names), game_config.json (starting money, XP and levels, autosave interval, initial map zoom), markets.json (commodities, regions and prices), canals.json (canals and locks).
- Generated data: data/world_map.res (land, coastline, lakes, rivers, borders, country names) and data/sea_lanes.res (a lane and distance for every pair of ports). Both are built by tools/build_map_data.gd from Natural Earth public-domain downloads kept in tools/source_data/ (not in git).
- After changing ports.json, rerun the tool (about 25-30 minutes; add `-- --lanes-only` to skip rebuilding the map art, or `-- --map-only` to rebuild only the map art after changing its source data). Source data in tools/source_data/: ne_10m_land, ne_50m_admin_0_countries, ne_10m_lakes and ne_10m_rivers_lake_centerlines (GeoJSON):
  `Godot --headless --path . -s tools/build_map_data.gd`
- Narrow straits and river approaches the pathfinding grid is too coarse to see are listed in the tool (CHANNELS) and carved as water; add to that list if a new port ends up with odd routes. Canals with locks are in data/canals.json: the tool carves each canal's centerline and lays it exactly into every lane that crosses it. A lane crosses a canal if it crosses the canal's divide (a line along the land between the two seas) an odd number of times; an even number is a stray detour over the isthmus and back, which is cut out. After changing only canals.json, `-- --canals-only` re-lays the canals into the existing lanes in seconds (3,881 lanes go through Panama).
- Saves record port and model ids, so renaming models or adding ports keeps existing saves working; removing or renaming a port id does not.

## Economy & time
- Starting money: $2,500,000. Saves from before trading can't be loaded.
- NOT an idle game (for beta): time only passes while the game is open, at a constant speed, or 2x or 4x with fast forward (see Top bar).
- On quit, the game saves and the world freezes. On Continue, everything resumes exactly where it left off. Ships do not move and no money is earned while the game is closed.
- Ships trade (see Trading): they buy a commodity at one port and sell it at the next. Profit is the price difference, less fuel, repairs and canal tolls.
- Every container delivered adds to the "Containers delivered" total.
- Ships buy their own fuel at each port's local price, which follows the oil price there (cheapest in the Gulf, dearest on remote islands); on average it's half the old $2.40. Repair costs are half what they were.
- Endless sandbox — no win condition.

## Trading
- 12 commodities (data/markets.json): Toys, Clothing, Furniture and Coffee (container ships); Oil and Gas (tankers); Iron ore, Coal and Gold ore (ore carriers); Grain (grain carriers); Livestock (livestock carriers); Vehicles (vehicle carriers). Container ships, tankers and ore carriers pick whichever of their goods pays best at each stop; the others carry their one good.
- Every port buys and sells everything. Prices come from 16 regions (0.5x where a good is produced to 2x where it's scarce: toys cheap in China, oil and gas in the Gulf, gold at Tema, Durban, Callao, Magadan, Port Moresby and Juneau, iron ore on the Great Lakes, in Brazil and Australia, vehicles in Japan, Korea, Germany and Detroit...), evened out between nearby ports (as competing traders would, over about 1,200 nm) so prices build up with distance, with a gentle local variation (up to 16%, varying over thousands of miles) and a coastal variation (typically up to about 3% either way, varying over about 1,600 nm, so neighbouring coasts differ a little and a Scooter can find a margin on most coasts) and a slow drift (up to 5% over about 20 minutes, neighbours drifting together). Buying costs 5% more than selling at the same port. Your own trades nudge prices by up to 1% (for a very large load), recovering within a couple of minutes. Island groups (Hawaii, Japan, Fiji–Tonga–Samoa, the Azores and Madeira; markets.json island_markets) get small local gaps on top, so inter-island hops can pay: imports land cheaper at the main port (Honolulu, Suva, Pago Pago, Ponta Delgada) and cost more on the outer islands, and local products are cheaper where they are made (Kona coffee on the Big Island, Kobe coffee and Osaka clothing, Fiji gold); each group has at least one profitable container trade and one ore trade.
- Halfway through each stop a ship sells its cargo, then buys the most profitable cargo it can carry to its next stop (after the canal tolls on the way): a full hold (less what a canal makes it leave behind), or as much as the money allows, always keeping enough for the whole fleet to fill its fuel tanks. Nothing if no cargo makes a profit (it sails empty).
- Canal tolls are a share of the cargo's value at the destination (none for an empty ship). The rough-seas bonus (+50%), the upper-lakes bonus (+20%) and a hub's Sale prices upgrade add to a profitable trade's profit.
- Balance: a good route earns about what the same ship earned under the old flat pay, the best about twice that; short hops earn a little, long hauls between the right regions a lot.
- Markets tab: pick a commodity to see the cheapest ports to buy it, the dearest to sell, and the best trades anywhere and within 800 nm (port names go to the map). The port popup shows every commodity's buy and sell price there (green cheap, red dear). The World map's Prices picker colors every port by a commodity's price; its menu groups the commodities by ship line, each group on a faint tint of the line's color and each commodity with a swatch in it (containers orange, tankers teal, ore grey, grain gold, livestock pink, vehicles blue: the line's middle ship's map color, brightened a little), and the chosen one's name is shown in that color. The route screen shows what each leg would load and its expected profit.

## Fuel, maintenance and port stops
- Every ship has a fuel tank and a maintenance level (0–100%). Both start full when the ship is bought.
- Fuel burns at a fixed rate per second at sea, whatever the ship's speed.
- Maintenance drops 1% per minute while a running ship is at sea (the Dominator and Mammoth: 0.5% per minute). It doesn't drop while docked or while paused.
- Speed = top speed × maintenance, so a ship at 0% stops dead.
- A slower, worn ship takes longer and so burns more fuel per leg. Tanks are sized so a ship leaving at 100% can just finish a leg of its full range (plus 1 s of spare fuel) while wearing on the way.
- Random breakdowns start at company level 6. Every 5 s, each ship at sea (never a recovery boat, and never inside a canal) rolls its own chance of losing 50 points of maintenance: 0.15% a roll at 100% maintenance, rising to 1.5% at 0% (worn ships break far more often). That's times the model's sturdiness (breakdown_factor: 1.0 for a Scooter down to 0.59 for a Dominator or Supertanker), times its age (+10% for every hour it has spent at sea, up to double), less its durability skill. A new Scooter at 100% breaks down about once an hour at sea. At 0% it's lost at sea. A ship that's slowed down can also run out of fuel before it arrives.
- Port stop: after arriving, a ship docks for a set time: Scooter 20 5 s, GE 100 10 s, Greenline 200 15 s, Trans Atlantic 30 s, Dominator 1 min.
  - Cargo unloads over the first half of the stop (the cargo bar drains), and the ship is paid when unloading finishes. Cargo loads over the second half (the bar refills).
  - With auto-repair on, maintenance refills to 100% over the first 5 s, paid as it goes. With auto-refuel on, the tank refills over the next 5 s. The Scooter 20 does each in 2.5 s to fit its 5 s stop.
  - The ship can leave when the stop ends.
- Auto-repair, auto-refuel and auto-recovery are per-ship toggles in the ship popup, all on for new ships (and for saved ships from before a toggle existed).
- Ships buy cargo only with money beyond the fleet's fuel reserve: what it would cost to top up every ship's tank where it is (or, for a cargo ship at sea, where it's going, counting the fuel it will burn getting there). A ship already full in port reserves nothing, so big idle tanks (a Buffalo's 645,000 units) don't lock up the money.
- Full loads (the ship popup's Full toggle, on for new and saved cargo ships): a ship only buys a full hold (less anything a canal makes it leave behind), never a part load, and with an empty hold it waits in port until it can afford one ("Docked at Rome — waiting for money for a full load to Marsaxlokk"). A leg where no cargo makes a profit is sailed empty straight away. Waiting isn't treated as a problem (no red dot or log message). With it off, a ship buys as much as the money allows and sails.
- A ship only leaves if it has enough fuel for the whole next leg (plus 1 s spare), allowing for the wear it will pick up on the way. So only a breakdown can leave it stranded at sea. Otherwise it is held in port (red dot, a toast, and the reason in its status): refuel is off, it's waiting for money, it's too worn to make the leg on a full tank (turn on repair), or the leg is beyond its range (for routes set before ranges shrank; assign a new one).
- Money never goes below $0. Refills buy what the player can afford, and held ships keep buying as money comes in, until they have enough fuel (with auto-refuel on, until the tank is full or the money runs out).

## Lost ships and recovery boats
- A ship at sea that runs out of fuel or hits 0% maintenance is lost. It stops where it is, gets a red "!" above it on the map and a red dot on the Ships screen, and a toast says so.
- The Mammoth is a recovery boat ($10,000,000, at most 8). It's the biggest ship, as fast as a Trans Atlantic (6.35 nm/s), and the most expensive to run: 4,500 fuel units/s ($10,800/s) and $300,000 per 1% of repair.
- The Buffalo is a smaller recovery boat ($1,250,000, but only $150,000 for the company's first ever Buffalo; at most 8), the size of a Trans Atlantic and as fast. It can only carry Scooter 20s, GE 100s, Greenline 200s and Coastal tankers, costs about a tenth as much to run (450 fuel units/s, $1,080/s, and $30,000 per 1% of repair), wears 1% per minute, and does jobs up to 8,000 nm.
- A lost ship's popup has a Send Recovery button. It shows the estimated cost (the recovery boat's fuel and repairs, including its trip home), which boat would go, where it would take the ship, and about how long. You choose whether it's worth it.
- The nearest free boat that can carry the ship goes (the cheaper one if two are as near): one that's docked, not refueling, and not on a job. Boats sailing to their base count as busy. A boat only sets off if it has the fuel and maintenance to finish the job.
- Auto-recovery ("Rescue" toggle in the ship popup, on for new ships): when the ship is lost, the cheapest capable free boat is sent automatically. If none is free, lost ships wait in a queue (longest-lost first) and the next free boat takes them.
- A ship at sea that no longer has the fuel or maintenance to reach port (usually after a breakdown) gets an amber "!" on the map, "won't make it!" in its status, and a toast.
- The Mammoth sails the sea lanes to the lost ship's position, through whichever end of the ship's leg is closer. It stops over the ship, turns to line up with it (2 s), and takes it aboard. If it's carrying the ship back the way it came, the pair then turn around (2 s more).
- It carries the ship to the nearer end of its leg. The carried ship is drawn in the middle of the Mammoth.
  - At the ship's destination, it unloads and is paid as usual.
  - Back at its origin, it gets no pay. It docks (repair and refuel as its toggles say) and tries the leg again.
- The Mammoth then docks there (repair and refuel like any ship), sails home, and waits for the next job. Its bars show maintenance, fuel, and "Tow" (the ship it's carrying).
- Each recovery boat is based at the HQ or a hub, and returns there after a job. Boats are spread evenly across the HQ and hubs, model by model (each location gets its share; locations that already have the most keep any extra one). It rebalances when a hub is founded or a recovery boat is bought or sold: boats already at a location within its share stay, and the rest are re-based to the nearest location still short that a full tank can reach. A re-based boat sails there (paying its own fuel and repairs) once it's free. The Hubs screen lists the boats based at each location.
- Recovery boats have no route and no Assign Route or Pause buttons, and never break down at random. They pay their own fuel and repairs: those show on the recovery boat's own line in the Finances tab.

## Company and ship levels (XP)
- Every delivery (when unloading finishes) gives XP to the company and to the ship for the work done: units delivered × leg distance × 0.01, weighted by the commodity's base price against a container of toys (a ton of oil counts for less). It doesn't depend on the profit, so a trade at a loss still earns XP. Levelling is about twice as fast as before the trading update (company level costs, hub level costs and each model's first ship level all halved), so level 100 takes about 20 hours.
- The company levels from 1 to 100 (Level and an XP bar in the top bar; toast on level-up with what it unlocked). Each level's cost is set so it takes roughly 3 minutes at level 1, rising to about 47 minutes at level 99, of what a full fleet at that level earns. So bigger ships don't make levels fly by, and level 100 takes about 40 hours (about 1 hour to level 10, 11 hours to 50, 24 hours to 75).
- Ship slots are per model: each container ship and gas tanker can be owned 3 at a time when it unlocks, plus 1 more every 3 company levels, up to its max of 8 (so 15 levels after unlocking). The Scooter 20 and GE 100 gain a slot every 2 levels instead (full 10 levels after unlocking). Recovery boats start at 1 and gain 1 every 5 levels, up to 8. Level-up messages say which models got a slot ("+1 slot: Scooter 20, GE 100").
- Models unlock by company level: Scooter 20 at 1, GE 100 at 5, Buffalo at 8, Greenline 200 at 12, Coastal at 15, Trans Atlantic and Mammoth at 25, Aframax at 35, Dominator at 50, Supertanker at 60. Ships already owned are kept even if they're above the current slots or unlocks.
- Ships level from 0 to 30. A model's first level needs xp_first_level XP (Scooter 20: 100, GE 100: 1,250, Greenline 200: 6,000, Trans Atlantic: 75,000, Dominator: 900,000; growing faster than the price, so small ships level fastest), and each level after costs 5% more.
- Each ship level gives a skill point, spent in the ship popup's Skills view on three paths of up to 10 levels each: Speed (+2% top speed per level), Durability (−5% wear and −5% chance of taking a random breakdown per level), and Gas efficiency (−3% fuel burn per level). Range on the route screen stays at the model's base range.
- Saves from before XP get the XP their past income would have earned.

## Headquarters and hubs
- The company starts with its headquarters (HQ) at its home port. It gets one more hub every 15 company levels (15, 30, 45, 60, 75, 90: 7 locations in all). A hub is founded from any port's popup ("Build a hub here", click again to confirm) and is permanent.
- Each HQ/hub levels from 0 to 40 on the XP of every delivery unloaded at its port (the same XP the company gets), and of every full load shipped out of it by a ship that arrived empty (a one-way route out of the hub: the hub gets the XP the load will earn where it's delivered, when it's loaded; the company and ship still get theirs on delivery). Level L to L+1 costs (5 + 0.7 x L) minutes of a quarter of a full fleet's XP at the current company level, so a hub taking about a quarter of the fleet's deliveries maxes out in about 12.5 hours.
- Each level is an upgrade point, spent in the port popup on four paths of up to 10 points each. Each point also costs money: $2M for a path's first point, then $500k more for each point already in that path ($2.5M, $3M ... $6.5M for the 10th; $42.5M for a full path). The buttons show the price and grey out when you can't afford it; the Finances tab totals it as "Hub upgrades". They boost every ship docking there: Ship XP +5% per point (ship XP only, not company or hub XP), Fuel & repairs -3% price, Port stops -5% time (unloading, repairs and refueling all speed up), Pay +2% on deliveries unloaded there. The HQ's bonuses are 1.5x a hub's.
- Every delivery unloaded at an HQ or hub also earns the company extra XP, free with the hub's level: +10%, plus 10% more for every 10 hub levels (+20% at level 10 ... +50% at level 40). The HQ's is 1.5x (+15% up to +75%). The hub's own XP and the ship's aren't boosted by it. The Hubs cards and port popup show it, e.g. "Company XP +30% on deliveries here (+40% at level 30)".
- On the map, the HQ and hubs have a ring in the company color around their port (heavier for the HQ; gray on the Route Assignment map). A small red dot sits just up and to the right of any HQ or hub with an upgrade you can buy now. The Hubs tab shows a red dot while a hub has an upgrade you can buy (a point and the money) or a new hub can be founded.
- New ships launch at the HQ or any hub, chosen when buying; recovery boats are then re-based across the hubs (see Lost ships and recovery boats). Saves from before hubs get an HQ at their home port.

## World
- The whole Earth, drawn flat in Web Mercator, wrapping east–west. Pan with drag, zoom with the mouse wheel, from the whole world down to a close view of a harbor.
- Map art: blue sea, sandy land with a darker coastline, thin country borders, lakes (drawn as water with a shoreline; islands in them are land), thin blue rivers (the biggest show zoomed out, smaller ones appear as you zoom in; visual only, ships don't sail them), and country names that appear as you zoom in (placeholder colors, all in the theme). Built from Natural Earth public-domain data by tools/build_map_data.gd.
- 227 real ports, in data/ports.json with real latitude/longitude, ranked roughly by container volume:
  - The world's biggest container ports (the top 100, plus the next several so that 100 are new beyond the original Mediterranean set). Ranks 1–25 follow the published 2023 figures; the rest follow recent Lloyd's List rankings as best known (the full list is paywalled), so a few borderline ports may differ from the official list.
  - The 18 biggest Mediterranean container ports, plus Rome (Civitavecchia) and Tunis (Radès).
  - Mediterranean islands: Limassol (Cyprus), Palermo (Sicily), Cagliari (Sardinia), Bastia (Corsica), Palma (Mallorca).
  - Also: Boston, Miami, Monterey, Anchorage, Seattle-Tacoma, Cabo San Lucas.
  - Added for coverage: New Orleans, Havana, Port-au-Prince, San Juan, Bridgetown, Cancun, Puerto Quetzal (Guatemala), Puntarenas (Costa Rica), Puerto Ayora (Galapagos); Honolulu, Nawiliwili (Kauai), Apia (Samoa), Pago Pago (American Samoa), Nuku'alofa (Tonga), Suva (Fiji), Papeete (French Polynesia), Auckland, Wellington, Apra Harbor (Guam), Port Moresby, Cebu, Muara (Brunei); Toamasina (Madagascar), Praia (Cabo Verde); Dublin, Douglas (Isle of Man), Reykjavik, Nuuk, Juneau, Dutch Harbor (Aleutians); Gothenburg, Oslo, Copenhagen, Aarhus, Bergen, Tallinn, Riga, Klaipeda; Durres; Constanta, Odesa, Novorossiysk.
  - Added to reach 200: Saint-Pierre, Portland (Maine), Nain (Labrador), Hamilton (Bermuda), Ponta Delgada and Faja Grande (Azores), Funchal (Madeira), Porto, Nantes-Saint-Nazaire; Portland (Oregon), Hilo and Kawaihae (Big Island of Hawaii), Malakal (Palau), Vladivostok, Korsakov (Sakhalin), Magadan, Petropavlovsk-Kamchatsky; Rio de Janeiro, Salvador, Fortaleza, Buenaventura, Antofagasta, Punta Arenas; Banjul, Freetown, Luanda, Maputo.
  - Added with Suez and the Great Lakes: Ain Sokhna and Port Tewfik (Egypt, south end of the Suez Canal), Eilat (Israel), Noumea (New Caledonia), Flying Fish Cove (Christmas Island), Midway Atoll; the 15 biggest Great Lakes ports (Duluth-Superior, Two Harbors, Thunder Bay, Presque Isle on Superior; Chicago, Indiana Harbor, Burns Harbor, Gary, Milwaukee on Michigan; Calcite on Huron; Detroit, Toledo, Cleveland on Erie; Toronto, Hamilton on Ontario); and six Antarctic stations (King George Island, Palmer, Rothera, McMurdo, Davis, Mawson).
- The map opens centered on the company's home port (45 degrees of longitude across); the route screen opens centered on the ship.
- Ports are white circles with names; when names would overlap, the HQ's or a hub's name wins, then the bigger port's, and the other shows on zoom.
- Ships follow real sea lanes around land, pre-computed for every pair of ports (25,651 lanes) into data/sea_lanes.res. Lanes use the Suez and Panama canals and the main straits and river approaches (Gibraltar, Messina, Bonifacio, the Dardanelles, Singapore, the Great Belt, the Elbe to Hamburg, the Scheldt to Antwerp, the Golden Gate, Puget Sound, the Bosphorus to the Black Sea, the Mississippi to New Orleans, Icy Strait to Juneau, the Oslofjord, the Columbia River to Portland, the Strait of Magellan, and others). All distances are real nautical miles along those lanes. Routes cross the Pacific without a seam.

## Panama Canal
- The canal is defined in data/canals.json: its centerline (Limón Bay → Gatún Locks → Gatún Lake → Culebra Cut → Pedro Miguel Locks → Miraflores Locks → Balboa), its locks, and its tuning. Every lane through it follows that centerline exactly.
- Three sets of locks, six chambers: Gatún (3, lifting ships from the Atlantic to Gatún Lake), Pedro Miguel (1) and Miraflores (2, lowering them to the Pacific). Chambers are drawn about 1.5 nm apart, several times real size, so they're visible at full zoom (like the ships).
- Each chamber has two lanes side by side, one per direction, and holds one ship per lane. A ship sails into a chamber and sits for 3 s while the water rises or falls, then sails on. If the next chamber is close (the rest of the same flight, or Pedro Miguel to Miraflores), it stays in its chamber until that one is free. Northbound and southbound ships never block each other.
- A ship coming up to a busy chamber waits in line behind it, 1.6 nm behind the ship ahead, first come first served (recovery boats too). No cap on the line.
- Engines are off in a chamber, in line and at the toll: no fuel burned, no wear. Nothing breaks down anywhere between the canal's entrance and exit. Fuel checks before departure only count sailing time, so they're unchanged.
- Toll: a cargo ship entering the canal pays 20% of the leg's base pay (before any hub Pay bonus). It's logged, counted in Finances ("Canal tolls", per ship and overall), and taken off the profit reported when the ship leaves the port at the end of that leg. A ship without the money waits at the entrance ("Waiting for toll money", a red dot on the Ships tab) and goes once it can pay. Recovery boats (and ships they carry) pay nothing.
- XP bonus: a delivery from a leg through the canal earns +50% XP for the company, the ship and the hub where it's unloaded, added to the other bonuses (a hub's +30% company XP becomes +80%).
- On the map the canal is always drawn as a water channel across the isthmus, wider as you zoom in. From 120 px per degree its chambers appear: two lanes each, with gates at the ends, the water darkening or lightening as a ship inside is lowered or lifted. Ships in the canal keep to the right-hand lane. "Panama Canal" is labeled at mid zoom, and each lock's name when zoomed in close.
- Clicking a lock (once its chambers are drawn) opens a popup: for each direction, each chamber's ship ("Ever Bright, rising (2 s)", "coming in", "waiting to move on" or "empty") and who's waiting in line.
- Saves from before the canal load fine; ships already partway through it carry on without paying a toll.

- A leg can pass several canals (Duluth to Rotterdam goes through the Soo Locks, the Welland Canal and the St. Lawrence Seaway). Each charges its own toll as the ship enters it, and each adds its XP bonus to the delivery.

## Suez Canal
- A sea-level canal with no locks, in data/canals.json like Panama: its centerline from the Mediterranean off Port Said to Suez Bay (about 96 nm), with the doubled stretches (the Port Said approaches, the Ballah bypass through the New Suez Canal to the Great Bitter Lake, and Suez Bay) and two single-lane stretches (El Qantara, and the Little Bitter Lake to Suez).
- Convoys: ships reaching the canal drop anchor in a cluster at the Port Said anchorage (southbound) or the Suez Bay anchorage (northbound), engines off. Every 90 s a convoy leaves each way at once; a ship arriving within 10 s after its convoy left still joins it. The toll (25% of the leg's base pay) is paid as the convoy leaves; a ship without the money stays at anchor for the next one ("waiting for toll money", red dot on the Ships tab). Recovery boats join convoys but pay nothing.
- Convoy ships enter one after another, fastest first, and sail at half their own speed. In the single-lane stretches they keep 1.6 nm behind the ship ahead (no overtaking); in the doubled stretches they can pass. A ship won't enter a single-lane stretch while a ship the other way is in it, and waits in the doubled stretch before it. The two convoys normally meet in the long doubled middle. A ship held up behind a slower one burns fuel and wears only for the distance it makes, so the fuel check before leaving port (which counts the half-speed canal) always holds.
- Supertankers are too deep for Suez fully loaded: they unload 25% of their cargo to pass (like the real SUMED pipeline), so the leg pays 25% less, and the toll is on the reduced pay.
- Deliveries through Suez get +50% XP. No breakdowns between the anchorages and the exit.
- On the map: the canal is drawn as one channel in single-lane stretches and two side by side in doubled ones (ships keep right); ships at anchor sit in rings round the anchorage. Zoomed in: "Port Said anchorage · next convoy 45 s" and "Suez Bay anchorage · ...", plus Great Bitter Lake, New Suez Canal and Ismailia. Clicking the canal or an anchorage opens a popup: time to the next convoys, and each way the ships at anchor, those waiting for toll money, those entering, and the convoy under way.
- Ship status: "At Port Said anchorage, next southbound convoy in 45 s", "Joining the southbound Suez Canal convoy (2nd in line to enter)", "In the southbound Suez Canal convoy (3rd of 7), held behind Big Blue", "Waiting in a passing stretch for the northbound convoy to clear".
- The route screen shows each Suez leg's toll, +50% XP, "up to 1 min 30 s waiting for a convoy", and a Supertanker's "unloads 25% to pass".

## Great Lakes
- The five Great Lakes (and Lake St. Clair) are water, reached up the St. Lawrence from its estuary, with the Welland Canal (Ontario to Erie), the Detroit and St. Clair rivers (Erie to Huron), the Straits of Mackinac (Huron to Michigan) and the St. Marys River (Huron to Superior).
- Only ships that fit the St. Lawrence Seaway (about 226 m long) can sail to a Great Lakes port: the Scooter 20, GE 100, Greenline 200 and Coastal, and the Buffalo so lake ships can be rescued. Bigger ships can't be given routes there, can't be bought at a lake hub, and Mammoths are never based at one. Only a Buffalo can recover a ship lost on a lake route.
- Three lock systems (type locks in data/canals.json), 3 s per lock step as at Panama:
  - St. Lawrence Seaway (Montreal to Lake Ontario): 7 single-chamber locks (St. Lambert, Côte-Sainte-Catherine, Lower and Upper Beauharnois, Snell, Eisenhower, Iroquois). Toll 10% of the leg's base pay, +25% XP.
  - Welland Canal (Lake Ontario to Lake Erie): single-chamber Locks 1–3, 7 and 8, and the twinned Flight Locks 4–6 (a lane each way). Toll 10%, +25% XP.
  - Soo Locks (Lake Huron to Lake Superior): one step with 3 parallel chambers, each taking a ship either way. No toll, +25% XP.
- Single (shared) chambers take one ship at a time either way. A chamber is left at the level for the other way, so a ship the same way waits 3 s while it's turned around; with ships waiting both ways, a lock alternates direction. Otherwise the Panama rules apply: lines, engines off, no breakdowns in the lock systems, toll on entering (or wait at the entrance).
- Legs between two ports on the upper lakes (Superior, Michigan, Huron) pay +20% (the ore and grain trade).

## Rough seas
- South of 60°S, ships wear twice as fast. The fuel check before leaving port and route ranges allow for it, so some long Antarctic legs within a ship's nominal range are refused ("too far for one tank").
- Legs to or from a port south of 60°S (the Antarctic stations) pay +50%, and so earn +50% XP for the ship, the company and the hub where they're unloaded.
- The route screen marks those legs "rough seas: +50% pay and XP, 2x wear".

## Ship models (data file)
- Six lines: container ships (Scooter 20, GE 100, Greenline 200, Trans Atlantic, Dominator), tankers (Coastal, Aframax, Supertanker), and new ore carriers (Laker L2, Panamax Bulker L20, Capesize L45), grain carriers (Grain Laker L8, Kamsarmax L28, Post-Panamax Bulker L52), livestock carriers (Cattle Coaster L12, Livestock Carrier L30, Ocean Shearer L55) and vehicle carriers (Car Hopper L18, Car Carrier L38, Giant Car Carrier L58), plus the recovery boats. The Scooter 20 now carries 20 containers (up from 15, with no change to its fuel use). Seaway-sized models (by length): Scooter, GE, Greenline, Coastal, Laker, Grain Laker, Cattle Coaster, Livestock Carrier, Car Hopper and the Buffalo (which can now also carry the small new models).
| Model | Price | Speed (nm/s) | Capacity | Range per leg | Max owned |
|---|---|---|---|---|---|
| Scooter 20 | $12,500 | 5.44 | 20 | 490 nm (≈1 min 30 s) | 8 |
| GE 100 | $125,000 | 4.82 | 100 | 760 nm (≈2 min 40 s) | 8 |
| Greenline 200 | $500,000 | 3.27 | 200 | 1,175 nm (≈6 min) | 8 |
| Trans Atlantic | $5,000,000 | 6.35 | 1,250 | 4,080 nm (Rome→New York is 4,073 nm) | 8 |
| Dominator | $50,000,000 | 3.99 | 10,000 | 9,000 nm | 8 |
| Buffalo | $1,250,000 | 6.35 | carries 1 lost Scooter 20, GE 100, Greenline 200 or Coastal | recovery jobs up to 8,000 nm | 8 |
| Coastal (gas tanker) | $1,500,000 | 6.35 | 5,000 tons of fuel | 1,175 nm | 8 |
| Aframax (gas tanker) | $15,000,000 | 5.40 | 50,000 tons of fuel | 4,080 nm | 8 |
| Supertanker (gas tanker) | $150,000,000 | 4.59 | 500,000 tons of fuel | 9,000 nm | 8 |
| Mammoth | $10,000,000 | 6.35 | carries 1 lost ship | recovery jobs up to 23,300 nm | 8 |

| Model | Fuel tank (units) | Burn (units/s) | Wear (%/min) | Repair per 1% | Port stop |
|---|---|---|---|---|---|
| Scooter 20 | 510 | 5.55 | 1 | $200 | 5 s |
| GE 100 | 7,950 | 37 | 1 | $1,330 | 10 s |
| Greenline 200 | 25,000 | 67 | 1 | $2,400 | 15 s |
| Trans Atlantic | 555,000 | 810 | 1 | $29,200 | 30 s |
| Dominator | 10,300,000 | 4,070 | 0.5 | $293,000 | 1 min |
| Buffalo | 645,000 | 450 | 1 | $30,000 | 10 s |
| Coastal | 50,500 | 265 | 1 | $9,500 | 15 s |
| Aframax | 1,830,000 | 2,250 | 1 | $81,000 | 30 s |
| Supertanker | 41,300,000 | 19,125 | 0.5 | $1,375,000 | 1 min |
| Mammoth | 20,400,000 | 4,500 | 0.5 | $300,000 | 10 s |
- Speeds keep a 30 : 20 : 18 : 35 : 22 ratio (except the GE 100, since sped up from 3.63 to 4.82 nm/s), scaled so a Scooter 20 sails Rome→Tunis (324.9 nm) in about 60 s. A Dominator's longest leg (9,000 nm) takes about 42 minutes with wear.
- Range is the longest single leg a ship can sail at 100% maintenance. It's enforced when assigning routes; fuel is checked again at every departure.
- On the map each model is a differently sized and colored rectangle with a pointed bow. Smaller ships are drawn on top of bigger ones where they overlap (and a click there picks the smaller one). Colors by family, smallest to biggest: container ships yellow to red (Scooter 20, GE 100, Greenline 200, Trans Atlantic, Dominator), gas tankers light green to dark blue (Coastal, Aframax, Supertanker), recovery boats brown, darker = bigger (Buffalo, Mammoth). Docked ships (all models) are drawn as small dots in their model color, in rings around the port (outer rings hold more), to save room.
- The player can own at most 10 of each container ship and gas tanker, and 5 of each recovery boat, once the company level has opened all their slots.
- Ship names must be unique (case-insensitive). No renaming in beta.
- Selling: a docked ship (not lost, not on a recovery job) sells for 50% of what was paid for it × its maintenance (so a first Buffalo bought for $150,000 sells for up to $75,000), from the ship popup's Sell button (click again to confirm).
- Newly bought ships spawn docked with no route at the port picked in the buy popup ("Launch at": the HQ, the default, or any hub).

## Screens

### Main menu
- 3 save slots, each its own file (user://save_1.json to save_3.json), then Quit. A slot with a save shows its company name (in the company color), money and game date; click it to continue that company, which then autosaves to the same slot. An empty slot says New Game. Each saved slot has a Delete button (with a confirmation). Saves that can't be loaded (from before commodity trading) show greyed out with the reason and can only be deleted. The single save from before slots becomes slot 1.
- New Game → "Found your company": enter a company name, pick a home port and a company color (red, orange, yellow, green, blue or purple; default purple), then Start. The home port list starts with 25 "Great starts" (3 Scooters clear about $40,000 or more in their first 10 minutes: West Africa, Pacific Mexico, the US East Coast and Caribbean, Panama, the China coast and Korea, the Mediterranean, Ireland, Portugal, the Gulf, Chennai) and 25 "Harder starts" (about $10,000-$30,000, often island hopping: Hawaii, Samoa, Fiji, the Azores, Japan, the Malacca Strait, eastern Australia, Rotterdam and the Channel, Colombia and Jamaica, Manila, Istanbul, the Baltic), then every other port (default Rome); data/starts.json, picked by simulating each HQ. 83 ports are left out of the list: those with no port within a Scooter's range and those where a Scooter finds no profitable trade (the US West Coast and Gulf, the Great Lakes, Karachi and Mumbai, Antarctica...); they are still normal ports. A note under the picker says what kind of start the port is and why; the rest say Scooters find only thin trade in range. The color is used for the company name in the top bar and the rings around the HQ and hubs. Saves from before colors are purple.
- Autosave on quit and every 30 s.

### Top bar (on World, Ships, Finances, Shop screens)
- Left: company level with an XP bar, and money. Middle: the company name (in the company color) above the calendar date and time ("Sat 1 Jan 2000, 14:30"). Right: the game speed button and total containers delivered.
- Calendar: a new company starts on 1 January 2000 at midnight. The clock runs 20 calendar minutes per second of play at 1x (game_config calendar), matched to real ship speeds (a Scooter's 5.44 nm a second is about 16 knots), so voyages take realistic calendar times: Rome to Tunis about 20 hours, Shanghai to Rotterdam about a month; a calendar day passes in about 72 seconds. It follows the game speed (stops when paused). The route screen shows each leg's calendar time too ("1 min 1 s (about 20 h)"), a ship at sea shows when it arrives ("arrives 3 Jan 09:10"), and activity log lines are stamped with the calendar time.
- Game speed: the button (or the F key) cycles Paused, 1x, 2x, 4x, 8x. Paused freezes the world; faster speeds run it that much faster (ships, breakdowns, XP, finances, prices); each session starts at 1x.
- Clicking the level (or its bar) opens a popup below it (click again to close): XP into the level and XP needed for the next, the company's XP per minute over the last 10 minutes, and "Coming up": the next level and the next few levels that unlock something (models, "+1 slot: ...", "a new hub"), each with an estimate of how long until you reach it at that rate. Refreshes every second.
- Clicking the money opens the Finances screen.

### Bottom navigation bar
- World | Ships | Finances | Hubs | Shop. Hidden on the Route Assignment screen.
- The Ships tab shows a red dot while any ship needs the player: lost with no recovery boat on the way, held in port, waiting at a canal for toll money, docked and paused, a docked cargo ship with no route, or upgrade points to spend. Its tooltip counts each reason and names the ships ("1 held in port (Tundra Godwit)", up to 3 names then "and 2 more"). The Ships screen filter "Needs attention" shows just those ships.
- The Shop tab shows a red dot while any ship can be bought (unlocked, a free slot, and affordable); its tooltip lists them.

### 1. World (map) screen
- Pan (drag) and zoom (mouse wheel) supported.
- Ports are clickable circles; ships are clickable pointed rectangles moving along their routes.
- A panel in the map's top-right corner holds the Routes switch and, under it, the Prices picker. The "Routes" switch (on by default, saved with the game) draws every sea lane the fleet uses as a faint line in the color of a ship using it: each cargo ship's route loop, any new route waiting to replace it, and the leg it's sailing now. A lane shared by several ships is drawn once.
- Only one popup open at a time; opening a new one closes the old one.

### 2. Ships screen
- Scrolling list grouped by model (in shop order), each group on a faint tint of its ship line's color (the same colors as the Prices menu and Finances) under the model name in that color, 8 compact tiles wide, one tile per owned ship. Groups with no ships (or none matching the filter) are hidden.
- Each tile has two lines: the ship name (cut short with "..." if it doesn't fit), then its cargo and level in smaller text ("Coffee · Lv 7", in green with "+2" while it has upgrade points to spend; recovery boats say "Recovery"). A ship that needs the player for anything but upgrade points says why instead, in red ("Held in port", "Paused", "No route", "Lost at sea", "Waiting for toll money"). Hovering a tile shows the full name and its status line (e.g. "Docked at Korsakov — not enough fuel for Hong Kong; turn on refuel").
- Each tile shows the ship name, a status dot, and thin maintenance / fuel / cargo bars. Green = running (has route, not paused, not held); amber = waiting in port for money for a full load; red = docked (paused at a port, no route, or held in port).
- Clicking a tile opens the ship popup.
- Sort (within each model) by name, status (lost, then at risk, then held, then stopped, then running) or profit; show all ships, running, stopped, lost, or recovery boats. A count shows how many are shown. Tiles re-sort when the fleet or the sort changes, not live.
- An "Upgrade all (N)" button (with a red dot while any ship has points to spend) spends every ship's upgrade points at once, round-robin: each point goes to the ship's lowest skill path, ties in the order speed, efficiency, durability (so speed 1, efficiency 1, durability 1, speed 2, ... up to all 30). Greyed out when there are none.
- Mega upgrade: once the company owns all 8 of a cargo model and every one is at level 30, a "Mega upgrade: $1,000,000" button appears to the right of the model's name (red dot when affordable; greyed, with the reason, when not). It costs 80x the model's price (Scooter 20 $1,000,000, GE 100 $10,000,000, Greenline 200 $40,000,000...; game_config mega) and can be bought once per model. Every ship of that model, including later ones, then gets +50% top speed and +50% profit on each profitable trade (on top of other bonuses). The name then shows a gold "★ Mega: +50% speed and profit" badge, and the activity log announces it. Recovery boats can't have one. Mega upgrades are a line in the Finances totals and are saved.

### Hubs screen
- A card for the HQ, then each hub: port name, Headquarters/Hub, level (of 40) with an XP bar and XP to the next level, the upgrade tree (points to spend, the four paths with pips, their bonuses and + buttons), and traffic (ships docked there now, deliveries unloaded there, pay received there), with a "Show on map" button that centers the World map on it.
- Then a "New hub available" card (how to found one, with a button to the map) while a hub can be founded, and a "Next hub" card with the company level that unlocks the next one.

### Finances screen
- At the top, "Keep in the bank" (Nothing, $100,000, $250,000, $500,000, $1M, $2.5M, $5M, $10M, $25M, $50M or $100M; saved with the company, default Nothing): ships won't spend that money on cargo, so it builds up for buying ships or upgrades. Fuel and repairs can still use it, so no ship is stranded. A ship waiting for a full load says so ("... (keeping $250,000 in the bank)").
- Totals for the last 10 minutes and all time: cargo sales, cargo bought, fuel, repairs, canal tolls, ships bought, ships sold, hub upgrades, mega upgrades, and operating profit (sales − cargo bought − fuel − repairs − tolls). Smaller text and tighter columns so it all fits.
- Then a card per canal the fleet has used: "Panama Canal: 12 crossings · tolls −$48,000 · bonus XP 3,100" (bonus XP is the extra company XP from the canal bonus).
- A table of every ship: model, sales, cargo bought, fuel, repairs, tolls, lifetime profit and profit over the last 10 minutes, grouped by ship line in shop order (container ships, ore, grain, livestock, tankers, vehicles, recovery boats). Each group sits on a faint band of its line's color and starts with a total row: the line's name in its color, its number of ships, and each column summed, in slightly bigger text. Click a column to sort the ships within each group; click a ship's name to open its ship popup. Refreshes every second.
- The totals and the 10-minute window are saved with the game.

### 3. Shop screen
- Three sections, "Container ships", "Gas tankers" and "Recovery boats", each a grid of compact cards up to 5 across (as many as fit beside the activity log: 5 at the default window, so 5 container ships, then 3 tankers, then 2 recovery boats, cheapest first), one card per ship model, showing its stats, price, and how many are owned ("Owned 2 / 10"). Each section title fades letter by letter through its models' map colors, smallest ship first, and each card's name is in its model's map color (dark colors brightened a little so they read on the cards). Each section sits on a faint tint of its ship line's color (the same colors as the Ships tab, Finances and the Prices menu).
- Each card shows owned / slots at the current level (and the max, while it can still grow). A full model shows "Next slot at level N"; a locked model shows "Unlocks at level N". A red dot sits on each Buy button that can be used right now (unlocked, a free slot, and affordable).
- A model with a first-purchase price shows it on the card ("$150,000 for your first, then $1,250,000"). Buy → naming popup with a suggested random name (editable, must be unique; a Random button suggests another) → confirm. Disabled if the player can't afford it: hovering it then shows a small note straight away, "You can't afford this ship ($1,300 short)." Shows "Limit reached" at the ownership limit.

### 4. Route Assignment screen
- Full-screen gray version of the map; no top bar or nav bar. The side panel shows the ship's current route, its range, and the port it starts from.
- Click ports in order to add waypoints; a side list shows ports in order plus estimated travel time and distance for each leg and the full loop. Legs through a canal add the lock time (6 chambers × 3 s through Panama, not counting any wait) and show the toll and XP bonus: "to Balboa · 44 nm · 30 s · Panama Canal: toll $4,200, +50% XP".
- Rules: consecutive waypoints must differ; since routes loop, the last waypoint must also differ from the first. Every leg, including the one back to the start, must be within the ship's range.
- Ports the ship can't reach from the last waypoint (or, before any are added, from the port it's docked at or heading to) are greyed out; clicking one explains why. Out-of-range legs show in red in the side list.
- Buttons: Cancel (always available), Undo last waypoint, Accept (enabled once 2+ waypoints and the route is valid).
- Assigning a new route to a ship at sea: it finishes its current leg, then follows the new route.
- Assigning a route also un-pauses the ship.
- A ship docked at a port that isn't on its new route first sails to the route's first port (a normal, paid leg).
- Running ships leave a port when their port stop ends (and they have fuel for the next leg); paused or route-less ships stay docked.

## Popups

### Port popup (appears above or below the clicked port)
- Title: port name.
- List of the player's ships currently docked there, each with thin maintenance / fuel / cargo bars and clickable to open its ship popup.
- Placeholder line: "Cargo market: coming soon".

### Ship popup (openable from map, Ships screen, Finances and port popups)
- Name (top) with an Upgrades button (showing unspent points, with a red dot while there are any) and X; Model, current speed (with top speed), range, capacity, and level with XP into it (cargo ships).
- Click the name to rename the ship: it becomes a text box (up to 24 characters); Enter saves, Esc or clicking away cancels. A name another ship already has (ignoring case) or a blank one shows in red with the reason in its tooltip. The new name shows everywhere at once (tiles, Finances, the map) and the ship's last-10-minutes finances carry over.
- The Upgrades button swaps the bars and toggles for the three skill paths (10 pips each, the bonus so far, and a + button to spend a point). Paths are listed Speed, Efficiency, Durability.
- Maintenance, Fuel and Cargo bars with live values (recovery boats: Tow instead of Cargo), then the Repair, Refuel, Rescue (auto-recovery) and Full (full loads) toggles. While docked: this stop's summary, e.g. "Sold $1,990 · Fuel −$800 · Repair −$200 / Profit $990".
- Lost ships: a Send Recovery button (see Lost ships and recovery boats).
- Status: e.g. "Docked at Rome" (with "(no route)", "(paused)", or why it's held when relevant), "Unloading at Tunis" / "Loading at Tunis", "En route to Tunis — 40%", "Stopping at Tunis" (paused while at sea). In a canal: "In Gatún Locks (chamber 2 of 3), rising — to Balboa", "In Pedro Miguel Locks, waiting for Miraflores Locks", "Waiting for Gatún Locks (2nd in line)", "Waiting for toll money at the Panama Canal". A stop's summary includes the toll paid on the leg that brought the ship there.
- Current route listed if one exists.
- Buttons: Assign Route (opens Route Assignment screen), Pause/Go toggle (greyed out with no route), Sell (first click shows the price, second click sells), View on Map (switches to the World map with the ship just above the middle and its popup open below it; from any screen).
- Pause behavior: a ship paused at sea continues to its next port and stays docked there. Go resumes the route from that port.

## Activity log
- Messages go into an activity log down the left of the game screen (272 px wide, beside the World, Ships, Finances and Shop screens; hidden on the Route Assignment screen). Newest first, in small text (size 8; about three-quarters of messages fit on one line, and longer ones like "held at" warnings wrap to two), each with the play time it happened (e.g. "02:10"). Text is in the color of the ship it's about (lightened if too dark to read; company-wide messages stay white). Bad news (breakdowns, lost ships, ships held in port or that won't make it) has a red highlight behind it; good news (level-ups, recoveries) a green one. It keeps the last 100 messages and starts empty each session.
- Messages, e.g. "Sea Otter sold Toys at Rotterdam: +$2,300 profit (bought $1,200, sold $3,500)" (in red for a loss), "Sea Otter loaded 15 containers of Toys for Rotterdam ($45,000)", "Sea Otter is held at Tunis: not enough fuel for Rome; turn on refuel", "Sea Otter broke down at sea! Maintenance now 30%", "Sea Otter is lost at sea (out of fuel)", "Big Mo carried Sea Otter to Tunis", "Auto-recovery: Little Mo sent for Sea Otter (about $160,000)", "Sea Otter won't make it to Tunis at this rate!", "Sold Big Blue for $10,000", "Sea Otter entered the Panama Canal: toll $4,200 (+50% XP on this delivery)".

## Explicitly NOT in beta
- Crew wages, port fees, fuel prices that differ by port, cargo types, upgrades, achievements, renaming ships, offline progress, audio, mobile, multiplayer and clans.

<sub><sup>p.s. the company name in the top bar is worth a click, once per company: a hidden gem, $10,000,000.</sup></sub>
