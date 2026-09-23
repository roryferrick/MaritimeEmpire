# Maritime Empire — Beta Spec

## Tech
- Engine: Godot 4 (standard build, GDScript). Target: Windows / Steam, mouse input, landscape only.
- Version control: Git. Keep game data (ports, ship models) in data files, not hard-coded.
- Placeholder visuals only (rectangles, circles, default Godot buttons). Structure UI so custom art can be swapped in later via a single Theme resource.
- Silent (no audio) for beta.

## Data & tools
- Game data lives in data/: ports.json (ports), ship_models.json (models, prices, speeds, ranges, limits, map look), ship_names.json (suggested ship names), game_config.json (starting money, pay rate, autosave interval, initial map zoom).
- Generated data: data/world_map.res (land, coastline, borders, country names) and data/sea_lanes.res (a lane and distance for every pair of ports). Both are built by tools/build_map_data.gd from Natural Earth public-domain downloads kept in tools/source_data/ (not in git).
- After changing ports.json, rerun the tool (about 17 minutes; add `-- --lanes-only` to skip rebuilding the map art):
  `Godot --headless --path . -s tools/build_map_data.gd`
- Narrow canals, straits and river approaches the pathfinding grid is too coarse to see are listed in the tool (CHANNELS) and carved as water; add to that list if a new port ends up with odd routes.
- Saves record port and model ids, so renaming models or adding ports keeps existing saves working; removing or renaming a port id does not.

## Economy & time
- Starting money: $10,000.
- NOT an idle game (for beta): time only passes while the game is open, at a constant speed. No speed controls.
- On quit, the game saves and the world freezes. On Continue, everything resumes exactly where it left off. Ships do not move and no money is earned while the game is closed.
- Payment for every leg, credited when the ship finishes unloading at the far port: containers (the ship's capacity) × leg distance in nm × $0.6125. The rate is tuned so a Scooter 10 earns about $2,000 per minute of sailing; Rome→Tunis pays a Scooter 10 about $2,000.
- Every delivery adds the ship's capacity to the "Containers delivered" total.
- Fuel costs $2.40 per unit at every port (game_config.json). Fuel costs about 40% of a leg's pay, and repairs about 10%.
- When a ship leaves a port, a toast shows what it sold its cargo for and its profit there (sale − (fuel + repair)).
- Endless sandbox — no win condition.

## Fuel, maintenance and port stops
- Every ship has a fuel tank and a maintenance level (0–100%). Both start full when the ship is bought.
- Fuel burns at a fixed rate per second at sea, whatever the ship's speed.
- Maintenance drops 1% per minute while a running ship is at sea (the Dominator and Mammoth: 0.5% per minute). It doesn't drop while docked or while paused.
- Speed = top speed × maintenance, so a ship at 0% stops dead.
- A slower, worn ship takes longer and so burns more fuel per leg. Tanks are sized so a ship leaving at 100% can just finish a leg of its full range (plus 1 s of spare fuel) while wearing on the way.
- Random breakdowns: every 5 s there's a 1% chance that one random ship at sea (never a Mammoth) loses 50 points of maintenance. At 0% it's lost at sea. A ship that's slowed down can also run out of fuel before it arrives.
- Port stop: after arriving, a ship docks for a set time: Scooter 10 5 s, GE 100 10 s, Greenline 200 15 s, Trans Atlantic 30 s, Dominator 1 min.
  - Cargo unloads over the first half of the stop (the cargo bar drains), and the ship is paid when unloading finishes. Cargo loads over the second half (the bar refills).
  - With auto-repair on, maintenance refills to 100% over the first 5 s, paid as it goes. With auto-refuel on, the tank refills over the next 5 s. The Scooter 10 does each in 2.5 s to fit its 5 s stop.
  - The ship can leave when the stop ends.
- Auto-repair, auto-refuel and auto-recovery are per-ship toggles in the ship popup, all on for new ships (and for saved ships from before a toggle existed).
- A ship only leaves if it has enough fuel for the whole next leg (plus 1 s spare), allowing for the wear it will pick up on the way. So only a breakdown can leave it stranded at sea. Otherwise it is held in port (red dot, a toast, and the reason in its status): refuel is off, it's waiting for money, it's too worn to make the leg on a full tank (turn on repair), or the leg is beyond its range (for routes set before ranges shrank; assign a new one).
- Money never goes below $0. Refills buy what the player can afford, and held ships keep buying as money comes in, until they have enough fuel (with auto-refuel on, until the tank is full or the money runs out).

## Lost ships and recovery boats
- A ship at sea that runs out of fuel or hits 0% maintenance is lost. It stops where it is, gets a red "!" above it on the map and a red dot on the Ships screen, and a toast says so.
- The Mammoth is a recovery boat ($2,000,000, at most 5). It's the biggest ship, as fast as a Trans Atlantic (6.35 nm/s), and the most expensive to run: 4,500 fuel units/s ($10,800/s) and $300,000 per 1% of repair.
- The Mini Mammoth is a smaller recovery boat ($250,000, at most 5), the size of a Trans Atlantic and as fast. It can only carry Scooter 10s, GE 100s and Greenline 200s, costs about a tenth as much to run (450 fuel units/s, $1,080/s, and $30,000 per 1% of repair), wears 1% per minute, and does jobs up to 8,000 nm.
- A lost ship's popup has a Send Recovery button. It shows the estimated cost (the recovery boat's fuel and repairs, including its trip home), which boat would go, where it would take the ship, and about how long. You choose whether it's worth it.
- The cheapest free boat that can carry the ship goes: one that's docked, not refueling, and not on a job. Boats sailing home count as busy. A boat only sets off if it has the fuel and maintenance to finish the job.
- Auto-recovery ("Rescue" toggle in the ship popup, on for new ships): when the ship is lost, the cheapest capable free boat is sent automatically. If none is free, lost ships wait in a queue (longest-lost first) and the next free boat takes them.
- A ship at sea that no longer has the fuel or maintenance to reach port (usually after a breakdown) gets an amber "!" on the map, "won't make it!" in its status, and a toast.
- The Mammoth sails the sea lanes to the lost ship's position, through whichever end of the ship's leg is closer. It stops over the ship, turns to line up with it (2 s), and takes it aboard. If it's carrying the ship back the way it came, the pair then turn around (2 s more).
- It carries the ship to the nearer end of its leg. The carried ship is drawn in the middle of the Mammoth.
  - At the ship's destination, it unloads and is paid as usual.
  - Back at its origin, it gets no pay. It docks (repair and refuel as its toggles say) and tries the leg again.
- The Mammoth then docks there (repair and refuel like any ship), sails home, and waits for the next job. Its bars show maintenance, fuel, and "Tow" (the ship it's carrying).
- Recovery boats have no route and no Assign Route or Pause buttons, and never break down at random. What they spend from being sent until they've refilled back at home is charged to the ship they recovered.

## World
- The whole Earth, drawn flat in Web Mercator, wrapping east–west. Pan with drag, zoom with the mouse wheel, from the whole world down to a close view of a harbor.
- Map art: blue sea, sandy land with a darker coastline, thin country borders, and country names that appear as you zoom in (placeholder colors, all in the theme). Built from Natural Earth public-domain data by tools/build_map_data.gd.
- 131 real ports, in data/ports.json with real latitude/longitude, ranked roughly by container volume:
  - The world's biggest container ports (the top 100, plus the next several so that 100 are new beyond the original Mediterranean set). Ranks 1–25 follow the published 2023 figures; the rest follow recent Lloyd's List rankings as best known (the full list is paywalled), so a few borderline ports may differ from the official list.
  - The 18 biggest Mediterranean container ports, plus Rome (Civitavecchia) and Tunis (Radès).
  - Mediterranean islands: Limassol (Cyprus), Palermo (Sicily), Cagliari (Sardinia), Bastia (Corsica), Palma (Mallorca).
  - Also: Boston, Miami, Monterey, Anchorage, Seattle-Tacoma, Cabo San Lucas.
- The map opens centered on the company's home port (45 degrees of longitude across); the route screen opens centered on the ship.
- Ports are white circles with names; when names would overlap, the bigger port's name wins and the other shows on zoom.
- Ships follow real sea lanes around land, pre-computed for every pair of ports (8,515 lanes) into data/sea_lanes.res. Lanes use the Suez and Panama canals and the main straits and river approaches (Gibraltar, Messina, Bonifacio, the Dardanelles, Singapore, the Great Belt, the Elbe to Hamburg, the Scheldt to Antwerp, the Golden Gate, Puget Sound, and others). All distances are real nautical miles along those lanes. Routes cross the Pacific without a seam.

## Ship models (data file)
| Model | Price | Speed (nm/s) | Capacity | Range per leg | Max owned |
|---|---|---|---|---|---|
| Scooter 10 | $2,500 | 5.44 | 10 | 490 nm (≈1 min 30 s) | 10 |
| GE 100 | $25,000 | 3.63 | 100 | 760 nm (≈3 min 30 s) | 10 |
| Greenline 200 | $100,000 | 3.27 | 200 | 1,175 nm (≈6 min) | 10 |
| Trans Atlantic | $1,000,000 | 6.35 | 1,250 | 4,080 nm (Rome→New York is 4,073 nm) | 10 |
| Dominator | $10,000,000 | 3.99 | 10,000 | 9,000 nm | 10 |
| Mammoth | $2,000,000 | 6.35 | carries 1 lost ship | recovery jobs up to 22,500 nm | 5 |
| Mini Mammoth | $250,000 | 6.35 | carries 1 lost Scooter 10, GE 100 or Greenline 200 | recovery jobs up to 8,000 nm | 5 |

| Model | Fuel tank (units) | Burn (units/s) | Wear (%/min) | Repair per 1% | Port stop |
|---|---|---|---|---|---|
| Scooter 10 | 510 | 5.55 | 1 | $200 | 5 s |
| GE 100 | 7,950 | 37 | 1 | $1,330 | 10 s |
| Greenline 200 | 25,000 | 67 | 1 | $2,400 | 15 s |
| Trans Atlantic | 555,000 | 810 | 1 | $29,200 | 30 s |
| Dominator | 10,300,000 | 4,070 | 0.5 | $293,000 | 1 min |
| Mammoth | 19,500,000 | 4,500 | 0.5 | $300,000 | 10 s |
| Mini Mammoth | 645,000 | 450 | 1 | $30,000 | 10 s |
- Speeds keep a 30 : 20 : 18 : 35 : 22 ratio, scaled so a Scooter 10 sails Rome→Tunis (324.9 nm) in about 60 s. A Dominator's longest leg (9,000 nm) takes about 42 minutes with wear.
- Range is the longest single leg a ship can sail at 100% maintenance. It's enforced when assigning routes; fuel is checked again at every departure.
- On the map each model is a differently sized and colored rectangle with a pointed bow, smallest to biggest: Scooter 10 (pale yellow), GE 100 (light blue), Greenline 200 (orange), Trans Atlantic (magenta), Mini Mammoth (teal, the same size as a Trans Atlantic), Dominator (red), Mammoth (steel gray). Docked recovery boats are drawn as small dots in their model color on a tight ring around the port (inside the ring of docked cargo ships) to save room.
- The player can own at most 10 of each cargo model and 5 of each recovery boat (60 ships in total).
- Ship names must be unique (case-insensitive). No renaming in beta.
- Selling: a docked ship (not lost, not on a recovery job) sells for 50% of its price × its maintenance, from the ship popup's Sell button (click again to confirm).
- Newly bought ships spawn docked at the company's home port with no route.

## Screens

### Main menu
- New Game (confirm before overwriting an existing save) and Continue (greyed out if no save). Saves from before the Earth map can't be loaded; Continue explains this.
- New Game → "Found your company": enter a company name and pick a home port from all ports (default Rome), then Start.
- Autosave on quit and every 30 s.

### Top bar (on World, Ships, Finances, Shop screens)
- Company name, money, and total containers delivered.

### Bottom navigation bar
- World | Ships | Finances | Shop. Hidden on the Route Assignment screen.

### 1. World (map) screen
- Pan (drag) and zoom (mouse wheel) supported.
- Ports are clickable circles; ships are clickable pointed rectangles moving along their routes.
- Only one popup open at a time; opening a new one closes the old one.

### 2. Ships screen
- Scrolling list grouped by model (in shop order), each group under a divider with the model name, 5 tiles wide, one tile per owned ship. Groups with no ships (or none matching the filter) are hidden.
- Each tile shows the ship name, a status dot, and thin maintenance / fuel / cargo bars. Green = running (has route, not paused, not held); red = docked (paused at a port, no route, or held in port).
- Clicking a tile opens the ship popup.
- Sort (within each model) by name, status (lost, then at risk, then held, then stopped, then running) or profit; show all ships, running, stopped, lost, or recovery boats. A count shows how many are shown. Tiles re-sort when the fleet or the sort changes, not live.

### Finances screen
- Totals for the last 10 minutes and all time: cargo income, fuel, repairs, recoveries, ships bought, ships sold, and operating profit (income − fuel − repairs − recoveries).
- A table of every ship: model, income, fuel, repairs, recoveries, lifetime profit and profit over the last 10 minutes. Click a column to sort. Refreshes every second.
- The totals and the 10-minute window are saved with the game.

### 3. Shop screen
- Two sections, "Cargo ships" and "Recovery boats", each a grid of cards 3 across, one card per ship model, showing its stats, price, and how many are owned ("Owned 2 / 10").
- Buy → naming popup with a suggested random name (editable, must be unique; a Random button suggests another) → confirm. Disabled if the player can't afford it; shows "Limit reached" at the ownership limit.

### 4. Route Assignment screen
- Full-screen gray version of the map; no top bar or nav bar. The side panel shows the ship's current route, its range, and the port it starts from.
- Click ports in order to add waypoints; a side list shows ports in order plus estimated travel time and distance for each leg and the full loop.
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

### Ship popup (openable from map, Ships screen, and port popups)
- Name (top), Model, current speed (with top speed), range, capacity.
- Maintenance, Fuel and Cargo bars with live values (recovery boats: Tow instead of Cargo), then the Repair, Refuel and Rescue (auto-recovery) toggles. While docked: this stop's summary, e.g. "Sold $1,990 · Fuel −$800 · Repair −$200 / Profit $990".
- Lost ships: a Send Recovery button (see Lost ships and recovery boats).
- Status: e.g. "Docked at Rome" (with "(no route)", "(paused)", or why it's held when relevant), "Unloading at Tunis" / "Loading at Tunis", "En route to Tunis — 40%", "Stopping at Tunis" (paused while at sea).
- Current route listed if one exists.
- Buttons: Assign Route (opens Route Assignment screen), Pause/Go toggle (greyed out with no route), Sell (first click shows the price, second click sells).
- Pause behavior: a ship paused at sea continues to its next port and stays docked there. Go resumes the route from that port.

## Notifications
- Small toast messages, e.g. "Sea Otter left Tunis: sold $1,990, profit $990", "Sea Otter is held at Tunis: not enough fuel for Rome; turn on refuel", "Sea Otter broke down at sea! Maintenance now 30%", "Sea Otter is lost at sea (out of fuel)", "Big Mo carried Sea Otter to Tunis", "Auto-recovery: Little Mo sent for Sea Otter (about $160,000)", "Sea Otter won't make it to Tunis at this rate!", "Sold Big Blue for $10,000".

## Explicitly NOT in beta
- Crew wages, port fees, fuel prices that differ by port, cargo types, upgrades, speed controls, achievements, renaming ships, offline progress, audio, mobile, multiplayer and clans.
