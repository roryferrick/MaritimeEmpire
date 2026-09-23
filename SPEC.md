# Maritime Empire — Beta Spec

## Tech
- Engine: Godot 4 (standard build, GDScript). Target: Windows / Steam, mouse input, landscape only.
- Version control: Git. Keep game data (ports, ship models) in data files, not hard-coded.
- Placeholder visuals only (rectangles, circles, default Godot buttons). Structure UI so custom art can be swapped in later via a single Theme resource.
- Silent (no audio) for beta.

## Economy & time
- Starting money: $10,000.
- NOT an idle game (for beta): time only passes while the game is open, at a constant speed. No speed controls.
- On quit, the game saves and the world freezes. On Continue, everything resumes exactly where it left off. Ships do not move and no money is earned while the game is closed.
- Payment on every port arrival: containers (the ship's capacity) × leg distance in nm × $0.6125. The rate is tuned so a Model 1 earns about $2,000 per minute of sailing; Rome→Tunis pays a Model 1 $2,000.
- Every arrival adds the ship's capacity to the "Containers delivered" total.
- Endless sandbox — no win condition.

## World
- The whole Earth, drawn flat in Web Mercator, wrapping east–west. Pan with drag, zoom with the mouse wheel, from the whole world down to a close view of a harbor.
- Map art: blue sea, sandy land with a darker coastline, thin country borders, and country names that appear as you zoom in (placeholder colors, all in the theme). Built from Natural Earth public-domain data by tools/build_map_data.gd.
- 23 real ports, in data/ports.json with real latitude/longitude:
  - Mediterranean (the 18 biggest container ports): Tanger Med, Valencia, Piraeus, Algeciras, Port Said, Gioia Tauro, Barcelona, Istanbul (Ambarlı), Marsaxlokk (Malta), Genoa, Mersin, Alexandria, Marseille-Fos, Haifa, Izmir (Aliağa), Ashdod, La Spezia, Koper.
  - Also Rome (Civitavecchia) and Tunis (Radès).
  - US East Coast: Boston, New York, Miami.
- Ports are white circles with names; when names would overlap, the bigger port's name wins and the other shows on zoom.
- Ships follow real sea lanes around land (through Gibraltar, the Strait of Messina, the Dardanelles, etc.), pre-computed for every pair of ports into data/sea_lanes.json. All distances are real nautical miles along those lanes. Pacific ports come later (with Models 5 and 6).

## Ship models (data file)
| Model | Price | Speed (nm/s) | Capacity | Range per leg | Max owned |
|---|---|---|---|---|---|
| Model 1 | $2,500 | 5.44 | 10 | 490 nm (≈1 min 30 s) | 10 |
| Model 2 | $25,000 | 3.63 | 100 | 760 nm (≈3 min 30 s) | 10 |
| Model 3 | $100,000 | 3.27 | 200 | 1,175 nm (≈6 min) | 10 |
| Model 4 | $1,000,000 | 6.35 | 1,250 | 6,000 nm (any Med port to the US East Coast) | 10 |
- Speeds keep a 30 : 20 : 18 : 35 ratio, scaled so a Model 1 sails Rome→Tunis (326.6 nm) in 60 s.
- Range is the longest single leg a ship can sail. It's enforced when assigning routes (future: fuel tanks).
- On the map each model is a differently sized and colored rectangle: Model 1 smallest (pale yellow), Model 2 (light blue), Model 3 (orange), Model 4 biggest (magenta).
- The player can own at most 10 of each model (40 ships in total).
- Ship names must be unique (case-insensitive). No renaming or selling in beta.
- Newly bought ships spawn docked at the company's home port with no route.

## Screens

### Main menu
- New Game (confirm before overwriting an existing save) and Continue (greyed out if no save). Saves from before the Earth map can't be loaded; Continue explains this.
- New Game → "Found your company": enter a company name and pick a home port from all ports (default Rome), then Start.
- Autosave on quit and every 30 s.

### Top bar (on World, Ships, Shop screens)
- Company name, money, and total containers delivered.

### Bottom navigation bar
- World | Ships | Shop. Hidden on the Route Assignment screen.

### 1. World (map) screen
- Pan (drag) and zoom (mouse wheel) supported.
- Ports are clickable circles; ships are clickable rectangles moving along their routes.
- Only one popup open at a time; opening a new one closes the old one.

### 2. Ships screen
- Scrolling grid, 3 tiles wide, one tile per owned ship.
- Each tile shows ship name and a status dot: green = running (has route, not paused), red = docked (paused at a port, or no route).
- Clicking a tile opens the ship popup.
- (Later: sorting/filtering.)

### 3. Shop screen
- One card per ship model, showing its stats, price, and how many are owned ("Owned 2 / 10").
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
- Running ships leave a port as soon as they arrive; only paused or route-less ships stay docked.

## Popups

### Port popup (appears above or below the clicked port)
- Title: port name.
- List of the player's ships currently docked there — each clickable to open its ship popup.
- Placeholder line: "Cargo market: coming soon".

### Ship popup (openable from map, Ships screen, and port popups)
- Name (top), Model, top speed, range, capacity.
- Status: e.g. "Docked at Rome" (with "(no route)" or "(paused)" when relevant), "En route to Tunis — 40%", "Stopping at Tunis" (paused while at sea).
- Current route listed if one exists.
- Buttons: Assign Route (opens Route Assignment screen), Pause/Go toggle (greyed out with no route).
- Pause behavior: a ship paused at sea continues to its next port and stays docked there. Go resumes the route from that port.

## Notifications
- Small toast messages, e.g. "Sea Otter arrived at Tunis (+$2,000)".

## Explicitly NOT in beta
- Fuel, crew wages, maintenance, port fees, cargo types, upgrades, speed controls, achievements, selling or renaming ships, offline progress, audio, mobile, multiplayer and clans.
