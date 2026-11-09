# Goblin Compass

A World of Warcraft **Classic Era** addon that puts a guide arrow on your screen (like the Zygor/TomTom arrow) and walks you to ore, herbs and fish.

## Two modes

- **Node mode** - points at the nearest known node for the profession you pick (Mining, Herbalism, Fishing, Treasure). Node locations come from [GatherMate2](https://www.curseforge.com/wow/addons/gathermate2), which you need installed. Nodes you reach are skipped, then come back after 10 minutes.
- **Planned zone routes** - ignores GatherMate2 and walks you around a fixed farming loop for the zone you choose. 19 routes across 16 zones (copper, tin, iron, mithril, thorium), traced from the route maps in Wowhead's [Best Mining and Ore Farming Routes](https://www.wowhead.com/classic/guide/classic-mining-best-farming-basics-early-ores) guide.

## Install

1. Download this repo (green **Code** button, **Download ZIP**) or a release zip.
2. Copy the `GoblinCompass` folder into `World of Warcraft\_classic_era_\Interface\AddOns\`.
3. Start the game. If it shows as out of date, tick **Load out of date AddOns** on the character screen.

## Use

- Click the minimap button (pickaxe) for the menu, or right-click it for options.
- Right-click the arrow for the same menu. Drag the arrow to move it.
- Slash commands (`/gc` or `/goblin`):

| Command | What it does |
| --- | --- |
| `/gc` | open the menu |
| `/gc mining` `herb` `fish` `treasure` | node mode |
| `/gc route` | start the planned route for the zone you're in |
| `/gc route tin barrens` | start a route by name (words in any order) |
| `/gc routes` | list all routes |
| `/gc reverse` | walk routes the other way |
| `/gc skip` `stop` `reset` | skip node/waypoint, stop, clear visited nodes |
| `/gc filter copper` | node mode: only nodes whose name contains this |
| `/gc options` | open the options page |
| `/gc debug` | print map ID and GatherMate2 data info (useful for bug reports) |

## Notes and limitations

- Routes are traced from images, so they are accurate to about 1-2% of the map. Good for following a loop, not exact. The Arathi Highlands mithril route is approximate.
- Routes only guide inside their zone; they don't navigate between zones.
- Developed without access to a live client, so please report anything odd (include the output of `/gc debug`).

## Credits

- Route shapes are traced from maps by the author of Wowhead's ore farming guide. All credit for the routes themselves goes to them.
- Node data is read from GatherMate2 by its authors; GatherMate2 is not bundled.

## License

MIT, see [LICENSE](LICENSE).
