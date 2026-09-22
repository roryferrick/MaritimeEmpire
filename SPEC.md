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
- Payment on every port arrival: the ship's capacity × a per-container rate. Each port has a pay_per_container value; a leg pays the higher of its two ports' values. Beta values: $100/container for A↔B, $200/container for any leg to or from Port C (so a Model 1 earns $1,000 / $2,000).
- Every arrival adds the ship's capacity to the "Containers delivered" total.
- Endless sandbox — no win condition.

## World
- Ports defined in a data file with world coordinates (so a custom or real-world map can replace the placeholder later).
- Beta ports: Port A and Port B on the same latitude, 900 nm apart. Port C directly north of the A–B midpoint, 1,800 nm from each.
- Ports drawn as green circles ("islands") on a blue background.
- Ships travel in straight lines between ports.

## Ship models (data file)
| Model | Price | Speed (nm/s) | Capacity | Range | Max owned |
|---|---|---|---|---|---|
| Model 1 | $2,500 | 30 | 10 | 2,250 nm | 5 |
| Model 2 | $25,000 | 20 | 100 | 2,250 nm | 5 |
| Model 3 | $100,000 | 18 | 200 | 2,250 nm | 5 |
- Leg times on the beta map: Model 1 A↔B 30 s / to-from C 60 s; Model 2 45 s / 90 s; Model 3 50 s / 100 s.
- The player can own at most 5 of each model.
- Range is a displayed number only for now (future: fuel tanks).
- Ship names must be unique (case-insensitive). No renaming or selling in beta.
- Newly bought ships spawn docked at Port A with no route.

## Screens

### Main menu
- New Game (confirm before overwriting an existing save) and Continue (greyed out if no save).
- Autosave on quit and every 30 s.

### Top bar (on World, Ships, Shop screens)
- Money and total containers delivered.

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
- One card per ship model, showing its stats, price, and how many are owned ("Owned 2 / 5").
- Buy → naming popup with a suggested random name (editable, must be unique; a Random button suggests another) → confirm. Disabled if the player can't afford it; shows "Limit reached" at the ownership limit.

### 4. Route Assignment screen
- Full-screen gray version of the map; no nav bar.
- Click ports in order to add waypoints; a side list shows ports in order plus estimated travel time and distance for each leg and the full loop.
- Rules: consecutive waypoints must differ; since routes loop, the last waypoint must also differ from the first.
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
- Status: e.g. "Docked at Port A" (with "(no route)" or "(paused)" when relevant), "En route to Port B — 40%", "Stopping at Port B" (paused while at sea).
- Current route listed if one exists.
- Buttons: Assign Route (opens Route Assignment screen), Pause/Go toggle (greyed out with no route).
- Pause behavior: a ship paused at sea continues to its next port and stays docked there. Go resumes the route from that port.

## Notifications
- Small toast messages, e.g. "Sea Otter arrived at Port B (+$1,000)".

## Explicitly NOT in beta
- Fuel, crew wages, maintenance, port fees, cargo types, upgrades, speed controls, achievements, selling or renaming ships, offline progress, audio, mobile, multiplayer and clans.
