# Goblin Compass

A World of Warcraft **Classic Era** addon that puts a guide arrow on your screen (like the Zygor/TomTom arrow) and walks you to ore, herbs and fish.

## Three ways to farm

- **Node mode** - points at the nearest known node for the profession you pick (Mining, Herbalism, Fishing, Treasure). Node locations come from [GatherMate2](https://www.curseforge.com/wow/addons/gathermate2), which you need installed. Nodes you reach are skipped, then come back after 10 minutes.
- **Planned zone routes** - ignores GatherMate2 and walks you around a fixed farming loop for the zone you choose. 19 routes across 16 zones (copper, tin, iron, mithril, thorium). Most are traced from the route maps in Wowhead's [Best Mining and Ore Farming Routes](https://www.wowhead.com/classic/guide/classic-mining-best-farming-basics-early-ores) guide; the Mulgore copper route was walked and recorded in game.
- **Generated routes** - builds a loop for any profession and zone from your GatherMate2 data: it groups nearby nodes into spots, keeps the densest ones your skill can gather, and plans a short loop through them. Great for herbs, which have no planned routes yet. Routes go in straight lines between spots, so in hilly zones you may need to walk around the odd obstacle.

## Auto-pick from tracking

Turn on **Find Minerals**, **Find Herbs** or **Find Treasure** and the arrow starts by itself:

- **Find Minerals** in a zone with a planned route starts that route. If the zone has more than one (The Barrens has Copper and Tin), it picks the highest ore your Mining skill can gather.
- Anywhere else, it generates a route from GatherMate2 data (turn this off on the options page), or, if there are too few known nodes, points at the nearest one.
- It re-picks when you change zones or switch tracking. Anything you choose by hand, or **Stop**, stays until you switch tracking again.
- Switch between **Automatic** and **Manual** on the options page, in the right-click quick menu, or with `/gc auto`.

## Install

1. Install from CurseForge (CurseForge app, WowUp, etc.), or download the zip from the latest [GitHub release](https://github.com/MehKoiter/goblin-compass/releases).
2. Manual install: extract the release zip into your game's `Interface\AddOns\` folder, so you end up with `Interface\AddOns\GoblinCompass\GoblinCompass.toc`.
   - The green **Code > Download ZIP** button gives the development version instead. Its files are one folder deeper (move the inner `GoblinCompass` folder into `AddOns`), and its version shows as `@project-version@`.
3. Start the game. If it shows as out of date, tick **Load out of date AddOns** on the character screen.

## Use

- The addon starts **off**. **Left-click** the minimap button (pickaxe) to turn it on or off: the icon is in full color when on, grey when off.
- **Right-click** the minimap button (or the arrow) for a quick menu: Enabled, Automatic / Manual, walk route in reverse, skip this node / waypoint, clear visited nodes, and **Options...**.
- Everything else (picking a profession or route, stopping) is on the options page. Drag the arrow to move it.
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
| `/gc generate` | generate a route for this zone from GatherMate2 data |
| `/gc generate kingsblood` | generate a route for one herb or ore |
| `/gc generate save` | save the generated route you're following, to turn it into a planned route |
| `/gc record` | record a new route by walking it (see [Adding routes](docs/adding-routes.md)) |
| `/gc on` `off` | turn the addon on or off (same as left-clicking the minimap button) |
| `/gc auto` | switch between automatic (from tracking) and manual |
| `/gc options` | open the options page |
| `/gc debug` | print map ID and GatherMate2 data info (useful for bug reports) |

## Adding routes (herbs, fishing, treasure and more)

Routes aren't limited to mining. Any profession can have them, and you can record one by walking it in game:

```
/gc record        start recording (turn on Find Herbs / Find Minerals first)
/gc record point  add a waypoint where you stand
/gc record stop   save it, then /reload and copy it from SavedVariables
```

See **[docs/adding-routes.md](docs/adding-routes.md)** for the route format, the fields, how to test a route, and how to send it in.

## Notes and limitations

- Routes traced from images are accurate to about 1-2% of the map. Good for following a loop, not exact. The Arathi Highlands mithril route is approximate.
- Routes only guide inside their zone; they don't navigate between zones.
- The bundled routes are mining only so far. Herbalism, Fishing and Treasure use node mode until someone adds routes for them.
- Developed without access to a live client, so please report anything odd (include the output of `/gc debug`).

## Testing and releasing

- **Tests:** `lua5.1 tests/run.lua` runs the logic tests. They also run automatically on every pull request.
- **Release:** publish a GitHub release with a tag like `v1.1.0`. The workflow builds the zip and uploads it to CurseForge. Use a tag like `v1.1.0-beta1` to ship a beta first.

Full steps, the in-game test checklist and setup notes: **[docs/releasing.md](docs/releasing.md)**.

What's planned next: **[docs/ROADMAP.md](docs/ROADMAP.md)**.

## Credits

- Most route shapes are traced from maps by the author of Wowhead's ore farming guide. All credit for those routes goes to them.
- Node data is read from GatherMate2 by its authors; GatherMate2 is not bundled.

## License

MIT, see [LICENSE](LICENSE).
