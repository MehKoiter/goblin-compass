# Roadmap

What we're working on next, and roughly in what order. This is a plan, not a promise: priorities change as people use the addon. If you'd like to help, see [Contributing](#contributing) at the bottom.

**Released:** v1.0.0 (November 2026)
**In progress:** v1.1 (generated routes)

---

## v1.0.0: released

Arrow guidance for gatherers:
- **Node mode:** points at the nearest node, using GatherMate2 data.
- **Planned routes:** 19 hand-made mining routes across 16 zones.
- **Automatic mode:** your tracking ability (Find Minerals, Find Herbs, Find Treasure) picks what to follow.
- **Controls:** a minimap on/off button, a quick menu and an options page.
- **Route recorder:** `/gc record` lets you walk your own routes.
- **Release automation:** publishing a GitHub release uploads it to CurseForge.

## v1.1: generated routes (in progress)

**Goal:** a route for every profession in every zone, especially herbs, which have no planned routes.

- [x] Generate a loop from GatherMate2 data. It groups nodes into spots, keeps the densest ones the player's skill can gather, and plans a short loop with no crossings.
- [x] Automatic mode generates a route when the zone has no planned one, with an option to turn this off.
- [x] `/gc generate [herb/ore]`, `/gc generate save`, and a **Generate route** button on the options page.
- [x] Logic tests (`tests/run.lua`) and a GitHub check on every pull request.
- [x] Testing and release guide (`docs/releasing.md`).
- [ ] **Test in game** with real GatherMate2 data (see the checklist in `docs/releasing.md`).
- [ ] Release `v1.1.0-beta1`, then `v1.1.0`.

**Known limitation:** generated routes go in straight lines between spots, so they can run into cliffs or water in hilly zones. A map overlay (v1.2) will make that easy to see; recording a corrected loop with `/gc record` fixes it for good.

## v1.2: see the route on the map

**Goal:** see the whole loop, not just the next step.

- [ ] **World map overlay:**
  - Draw the current route as lines, in the profession's color.
  - Highlight the next waypoint.
  - A checkbox to show or hide it.
  - Works for planned and generated routes.
- [ ] **Minimap marker** for the next waypoint, or the next few.

**Notes for whoever picks this up:**
- The world map is the easier part: it doesn't rotate, and routes are already stored as map coordinates.
- The minimap is harder: it can rotate, zoom, and change size indoors. The common solution is the HereBeDragons library. Check its license before bundling it, and consider whether a simple next-waypoint marker is enough without it.
- The automated tests can't check drawing, so this release depends on in-game testing.

## v1.3: track real gathering

**Goal:** know what you actually gathered, not just where you walked.

- [ ] **Count real gathers:** mark a node as visited when it's actually looted (the gathering spell succeeds), not just when you walk past it.
- [ ] **Session stats:** nodes gathered, nodes per hour, and items collected, shown on the options page or a small summary.
- [ ] **Skill-aware node mode:** skip nodes your skill can't gather, reusing the skill table from v1.1.

## Later ideas (not scheduled)

Roughly in order of how useful they'd be:

- **Routes for two professions:** a mixed loop for characters with both Mining and Herbalism, built on route generation.
- **Share routes in game:** export a route as a text string that others can import, with no GitHub needed.
- **More curated routes:** hand-recorded herb, fishing and treasure routes for popular zones, to replace generated ones where those struggle with terrain.
- **Non-English clients:** profession and node names are partly assumed to be English. Localize the skill table and name checks.
- **Better use of route data:** e.g. avoid known elite camps, or prefer roads.

## Open questions

- **Route credit:** the bundled mining routes were traced from Wowhead guide maps and credited. Should we gradually replace them with routes recorded in game, so the addon doesn't depend on someone else's work?
- **Ore skill values:** the herb skill table is solid; a few ore values (e.g. the Thorium tiers) should be checked in game.
- **Game version naming:** the client reports interface 16001, which the packager tags as "1.60.1 (forever)". Make sure the CurseForge listing and description name the game version correctly.

---

## Contributing

- **Routes:** the easiest way to help. See [adding-routes.md](adding-routes.md). `/gc record` and `/gc generate save` both produce entries you can paste in.
- **Code:** pick an unticked item above, and open an issue saying you're on it so work isn't duplicated. Follow [releasing.md](releasing.md): branch, tests (`lua5.1 tests/run.lua`), in-game check, then a pull request.
- **Bugs and ideas:** open an issue on GitHub. For bugs, include the output of `/gc debug`.

When an item ships, tick it here in the same pull request, and move finished releases into the "released" section.
