# Goblin Compass

**A goblin's nose for ore, herbs and treasure.** Goblin Compass puts a big, easy-to-read arrow on your screen and walks you to your next gathering node, or around a ready-made mining route for the zone you're in.

Turn on **Find Minerals** and it gets going by itself.

---

## Features

### Follows your tracking
Switch on **Find Minerals**, **Find Herbs** or **Find Treasure** and the arrow starts on its own, no menus needed.

- **Find Minerals** in a zone with a planned route starts that route. If the zone has more than one, it picks the best ore your Mining skill can gather (e.g. Tin over Copper in The Barrens once you reach 65).
- Anywhere else, it points you to the nearest known node for that profession.
- Changes zone or tracking? It picks again. Prefer to choose yourself? Switch to **Manual** in the options.

### Two ways to farm
- **Node mode:** points at the nearest known Mining, Herbalism, Fishing or Treasure node, using the node database from **GatherMate2**. Nodes you've just visited are skipped for 10 minutes while they respawn.
- **Planned routes:** walks you around a proven farming loop, waypoint by waypoint. No GatherMate2 needed.

### 19 mining routes across 16 zones

| Ore | Zones |
| --- | --- |
| **Copper** | Elwynn Forest, Dun Morogh, Darkshore, Durotar, Mulgore, Tirisfal Glades, The Barrens |
| **Tin** | The Barrens, Wetlands |
| **Iron** | Thousand Needles, Arathi Highlands |
| **Mithril** | Arathi Highlands, Badlands (2 routes), Tanaris, Blasted Lands |
| **Thorium** | Un'Goro Crater, Winterspring, Silithus |

### Clean, readable arrow
- One bold arrow, colored by profession: **orange** for Mining, **green** for Herbalism, **blue** for Fishing, **gold** for Treasure.
- Just two lines of text: where you're going (e.g. *The Barrens - Copper*) and how far (*266 yd*).
- Drag it anywhere, lock it in place and resize it.

### Easy to control
- **Minimap button:** left-click to turn Goblin Compass on or off (the icon goes grey when it's off), right-click for the quick menu. It starts off after install, so it never gets in your way until you want it.
- **Right-click the arrow** for the same quick menu.
- **Options page** (Esc → Options → AddOns → Goblin Compass): automatic or manual mode, profession and route pickers, node name filter, reverse route direction, arrow size, arrival distance and waypoint radius.

---

## Slash commands

Use `/gc` or `/goblin`.

| Command | What it does |
| --- | --- |
| `/gc` | Open the quick menu |
| `/gc on` / `off` | Turn the addon on or off |
| `/gc mining` / `herb` / `fish` / `treasure` | Point at the nearest node of that type |
| `/gc route` | Start the planned route for the zone you're in |
| `/gc route tin barrens` | Start a route by name (words in any order) |
| `/gc routes` | List all routes |
| `/gc reverse` | Walk routes the other way round |
| `/gc skip` | Skip the current node or waypoint |
| `/gc stop` | Stop guiding |
| `/gc reset` | Forget visited nodes |
| `/gc filter copper` | Node mode: only nodes whose name contains this text |
| `/gc auto` | Switch between automatic (from tracking) and manual |
| `/gc options` | Open the options page |
| `/gc debug` | Print diagnostic info (handy for bug reports) |

---

## Requirements

- **World of Warcraft Classic Era.**
- **[GatherMate2](https://www.curseforge.com/wow/addons/gathermate2)** (optional): needed for node mode. Planned routes work without it.

---

## Good to know

- Routes were traced from map images, so they're accurate to about 1-2% of the map: great for following a loop, but not pixel-perfect. The Arathi Highlands Mithril route is approximate.
- Routes guide you within their zone. They don't navigate you between zones.
- Planned routes currently cover mining only. Herbalism, Fishing and Treasure use node mode.

---

## Feedback and bug reports

Found a bug or have an idea? Please leave a comment or open an issue. For bugs, please include the output of `/gc debug`.

---

## Credits

- Route shapes are traced from the maps in Wowhead's [Best Mining and Ore Farming Routes](https://www.wowhead.com/classic/guide/classic-mining-best-farming-basics-early-ores) guide. All credit for the routes themselves goes to its author.
- Node data comes from **GatherMate2** and its authors. GatherMate2 is not bundled with this addon.

Licensed under the MIT License.
