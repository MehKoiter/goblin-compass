# Testing and releasing

This is the process for getting a change from an idea to players without breaking anything. Each step:

1. **Branch:** make the change on a branch and open a pull request.
2. **Automated tests:** they run on the pull request by themselves.
3. **In-game test:** try the branch in your own game.
4. **Beta:** ship it to beta testers first (optional, recommended for bigger changes).
5. **Release:** ship it to everyone.

## 1. Work on a branch

Keep `main` releasable: everything on it should be something you'd be happy to ship. Make each change on its own branch and open a pull request to merge it.

## 2. Automated tests

Every pull request, and every push to `main`, runs the **Tests** workflow (`.github/workflows/tests.yml`):

- **Syntax check:** `luac5.1 -p` on every addon file. Lua 5.1 is the version the game uses.
- **Logic tests:** `tests/run.lua` loads the addon against a stand-in WoW API and checks:
  - the on/off switch;
  - Automatic / Manual mode;
  - route choice by skill;
  - the quick menu;
  - the route recorder;
  - that the bundled routes are well-formed.

A red check on the pull request means something broke; open the run to see which test failed. To run the tests locally (needs Lua 5.1), from the repository root:

```bash
lua5.1 tests/run.lua
```

The tests can't see anything visual: textures, layout, where the arrow points. That's what the in-game test is for.

When you add a feature, add a test for it to `tests/run.lua`. Each test is a `test("what it checks", function() ... end)` block.

## 3. Test the branch in game

### Install the branch

1. On GitHub, switch to the branch, then **Code > Download ZIP**.
2. The zip has one extra folder level. Move the inner `GoblinCompass` folder into `Interface\AddOns`, replacing the installed one.
3. **Restart the game** if any image file changed (e.g. `arrow.tga`). Otherwise `/reload` is enough.

In the addon list, the version shows as `@project-version@`. That's normal for branch downloads: only packaged releases fill in the real number.

### See every error

Lua errors are hidden by default. Either:
- install **BugGrabber** and **BugSack**, which collect every error with a full stack trace (recommended); or
- type `/console scriptErrors 1` once.

### Check a fresh install too

Upgrades keep your old settings, so also test as a brand-new user would see it:

1. Log out.
2. Rename `<game folder>\WTF\Account\<ACCOUNT>\SavedVariables\GoblinCompass.lua` to something else.
3. Log in and test.
4. Afterwards, log out and rename the file back to keep your settings.

### Checklist

Spend most of your time on the area you changed, but run through all of it:

- [ ] Loads with no errors on login and after `/reload`
- [ ] Minimap icon is grey when off and full color when on; left-click toggles it
- [ ] Right-click menu: all 7 items work; **Options...** opens the options page
- [ ] Options page: everything fits and every control works
- [ ] **Automatic:** Find Minerals in a zone with a route starts the right route; switching tracking switches it
- [ ] **Manual:** picking a profession or route on the options page works
- [ ] **Node mode** (GatherMate2 installed): the arrow points at a real node, and the node is skipped after gathering
- [ ] **Route mode:** the arrow walks the loop; Skip and reverse work
- [ ] Changing zone, and `/reload` in the middle of a route, don't break anything
- [ ] `/gc debug` prints sensible output

If something's wrong, fix it on the branch. The pull request updates by itself; test again.

When it's all good, merge the pull request.

## 4. Ship a beta (optional)

The tag name decides which CurseForge channel a release goes to:

| Tag | CurseForge file type | Who gets it |
| --- | --- | --- |
| `v1.1.0-beta1` (contains `beta`) | Beta | Only people who set Goblin Compass to Beta in their addon manager |
| `v1.1.0-alpha1` (contains `alpha`) | Alpha | Only people who set it to Alpha |
| `v1.1.0` | Release | Everyone |

1. On GitHub: **Releases > Draft a new release**.
2. Create the tag `v1.1.0-beta1` on `main` and tick **Set as a pre-release**.
3. Publish. The **Release** workflow builds the zip and uploads it.
4. In the **CurseForge app**, set Goblin Compass to **Beta** and update it. This tests the real packaged zip and the update path, which a branch download doesn't.
5. Play with it for a session or two. If you find problems, fix them through a pull request, then release `v1.1.0-beta2`.

## 5. Release

1. **Releases > Draft a new release**, then create the tag `v1.1.0` on `main`. Release it from the same commit as the last good beta.
2. Write short release notes and publish.
3. Check that the **Release** run in the **Actions** tab is green. Its log should show `Uploading ... to https://wow.curseforge.com/projects/1794969 ... Success!`.
4. Check the file appears on CurseForge's **Files** tab. New files can wait briefly for moderation.

### Version numbers

- `v1.0.1`: bug fixes only.
- `v1.1.0`: new features (new routes, new options).
- `v2.0.0`: changes that would surprise existing users (settings reset, controls changed).

Never delete or reuse a tag; always move forward to a new number.

### If a release goes wrong

- **Bad file on CurseForge:** mark it **Archived** on the Files tab so nobody new installs it, then fix it through a pull request and release `v1.1.1`.
- **Release run failed:** open it in the **Actions** tab. Once the cause is fixed, **Re-run all jobs** rebuilds the same tag; no new tag is needed.

## How the release workflow works

`.github/workflows/release.yml` runs when a `v*` tag is pushed (which publishing a GitHub release does). It uses the [BigWigs packager](https://github.com/BigWigsMods/packager), configured by `.pkgmeta`, to:

- package only the `GoblinCompass/` folder, as `GoblinCompass-<tag>-forever.zip` (README, docs, media, tests and tools are left out);
- replace `@project-version@` in the TOC with the tag;
- write a `CHANGELOG.md` from the commits since the last tag;
- attach the zip to the GitHub release, and upload it to CurseForge.

### One-time setup

- **CurseForge project ID:** set in the TOC as `## X-Curse-Project-ID: 1794969`. Nothing to configure.
- **CurseForge upload token:** GitHub **Settings > Secrets and variables > Actions > Secrets**, secret `CF_API_KEY`.
  - It must be an **upload API token** from your CurseForge account's **API Tokens** page.
  - A CurseForge Core API key from `console.curseforge.com` won't work.
  - If uploads start failing with `Error fetching game version info`, the token is wrong or expired: generate a new one and update the secret.
- **GitHub Actions:** must be enabled, and the account must be in good standing. A billing lock stops every run, even though Actions are free for public repositories.
