# Adding planned routes

Goblin Compass ships with mining routes, but the route system works for any gathering profession: **Mining, Herbalism, Fishing or Treasure**. This guide shows how to add a route: record it in game, add it to `GoblinCompass/Routes.lua`, check it, and send it in.

## How routes work

A route is a loop of waypoints in one zone. The arrow points at the next waypoint, moves on when you get within the waypoint radius (50 yd by default, set in the options), and goes back to the start after the last point.

With the addon switched on (left-click the minimap button) and **Automatic** mode on, tracking picks the profession and the route:
- **Find Minerals** starts a `Mining` route in your zone.
- **Find Herbs** starts a `Herbalism` route.
- **Find Treasure** starts a `Treasure` route.

If a zone has several routes for that profession, the addon picks the highest one the player's skill allows (see `skill` below). Zones without a route fall back to GatherMate2 node mode.

There's no fish-tracking ability in Classic, so `Fishing` routes are only started by hand, from the route list on the options page or with `/gc route`.

## Shortcut: start from a generated route

If GatherMate2 knows the zone well, `/gc generate` (or `/gc generate <herb or ore name>`) builds a route from its node data, and `/gc generate save` saves the one you're following in the same format as a recording (step 1, part 6). Generated routes take straight lines between spots, so walk it once to check it doesn't run into cliffs or water; if it does, record a corrected loop instead.

## 1. Record the route in game

The easiest way to get accurate coordinates is to walk the loop yourself.

1. Go to the zone. Turn on the tracking for the profession (e.g. **Find Herbs**) so the recording is labeled correctly.
2. Type `/gc record` to start.
3. Walk your loop at a normal pace. A waypoint is added every 40 yards.
   - `/gc record point` adds a waypoint right where you stand, useful at sharp turns or next to a node cluster.
   - `/gc record step 30` changes the spacing. Use smaller steps for twisty paths and bigger ones for open ground.
4. Finish close to where you started; the route loops back to the first point by itself.
5. Type `/gc record stop` to save. Use `/gc record cancel` to throw a recording away.
6. Log out or `/reload`, which writes the recording to disk. Then open:
   ```
   <your game folder>\WTF\Account\<ACCOUNT>\SavedVariables\GoblinCompass.lua
   ```
   Under `["recorded"]` you'll find a ready-made entry, e.g.:
   ```lua
   { id="the-barrens-herbalism", zone="The Barrens", map=1413, prof="Herbalism", ore="CHANGE ME", levels="?",
       pts={ 40.1,30.2, 45.3,30.0, 45.2,36.4, ... } },
   ```
7. `/gc record clear` deletes your saved recordings once you've copied them.

Other notes on recording:
- Points are only taken while you're on the zone you started in. Caves and city sub-maps count as a different map, so walk around them rather than through them.
- Recording works with or without the arrow showing.

### Prefer not to record?

You can also write the points by hand, for example by tracing a route map from a guide. Coordinates are the same zone-map percentages you see in coordinate addons, from 0 to 100. Go round the loop in order. Only use maps you have permission to use, and credit the source (see below).

## 2. Add it to `Routes.lua`

Paste the entry into the `GoblinCompassRoutes = { ... }` list in `GoblinCompass/Routes.lua` and fill in the fields:

| Field | Required | What it is |
| --- | --- | --- |
| `id` | yes | Unique, lowercase, dashes only, e.g. `"the-barrens-peacebloom"`. `/gc route <id>` starts it. |
| `zone` | yes | Zone name as the game shows it, e.g. `"The Barrens"`. |
| `map` | yes | The zone's uiMapID. The recorder fills it in; otherwise `/gc debug` prints it as `current uiMapID`. |
| `prof` | no | `"Mining"` (default), `"Herbalism"`, `"Fishing"` or `"Treasure"`. Sets the arrow color and which tracking starts it. |
| `ore` | yes | What the route gathers: an ore, herb, fish or treasure, e.g. `"Peacebloom"`. It's called `ore` for historical reasons but works for anything. Shown on the arrow and used to group the route list. |
| `skill` | no | Skill needed for this route. Used to pick the best route when a zone has several. Ores default to their mining requirement (Copper 1, Tin 65, Iron 125, Mithril 175, Thorium 230); everything else defaults to 1. |
| `levels` | yes | Suggested character level range, e.g. `"10-25"`. Shown in the route list. |
| `note` | no | Short label to tell routes in the same zone apart, e.g. `"northern loop"`. |
| `faction` | no | `"Alliance"` or `"Horde"` if the route sits mostly in one faction's territory. Shown as a hint in the route list. |
| `pts` | yes | The waypoints, as `x,y` pairs in walking order. At least 3 points. |

Example herb route:

```lua
{ id="the-barrens-peacebloom", zone="The Barrens", map=1413, prof="Herbalism", ore="Peacebloom", skill=1,
  levels="10-25", note="Crossroads loop",
  pts={ 52.1,30.4, 55.0,27.8, 57.9,31.2, 56.3,36.0, 52.4,35.1 } },
```

Routes appear in the route list (options page) grouped by `ore`. The known ores come first, then everything else in the order it appears in the file, so keep routes for the same herb or fish together.

## 3. Check it in game

1. `/reload`.
2. `/gc routes` should list your route.
3. Start it with `/gc route <id>`. Or turn on the matching tracking in that zone, with **Automatic** on.
4. Walk part of the loop and check:
   - the arrow points the right way;
   - waypoints are reached and passed smoothly;
   - the route doesn't run through walls, deep water or elite camps.

If the arrow skips around or doubles back, there are probably points out of order, or two points too close together. `/gc reverse` walks the loop the other way, which is handy for checking both directions.

## 4. Send it in

- **Pull request (preferred):** fork the repo, add your route to `GoblinCompass/Routes.lua`, and open a pull request. Say in the description:
  - which profession, zone and resource it's for;
  - which skill and level range it suits;
  - whether you walked it yourself or traced it, and from where.
- **No GitHub experience?** Open an issue, or leave a comment on the CurseForge page, and paste your recorded entry.

### Credit and permission

Routes you record yourself are yours to share. If you trace a route from someone else's guide or map, credit them: add a comment above the route in `Routes.lua`, and add a line under **Credits** in the README. Only submit routes you're allowed to share. The existing mining routes were traced from the route maps in Wowhead's [Best Mining and Ore Farming Routes](https://www.wowhead.com/classic/guide/classic-mining-best-farming-basics-early-ores) guide, which is credited in the README.
