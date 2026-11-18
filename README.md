# IWIN

One button that casts the next spell in your rotation, for World of Warcraft: Forever. Press it over and
over and it works through your class's damage priority for you, a little like Retail's Single-Button
Assistant.

## How it works

Blizzard does not let an addon pick a spell during combat. A button's action can only be changed out of
combat, so IWIN does the choosing ahead of time:

1. Out of combat, IWIN reads your spellbook and talents and builds a **priority macro** for your class
   and spec: one `/cast` line per spell, best first.
2. That macro goes on a secure button (`IWIN_Button`).
3. In combat, every press runs the macro. The game tries each line in turn and skips any spell that is on
   cooldown, out of range, short on mana or rage, or not usable yet (Execute above 20%, Overpower with no
   dodge, Revenge with no block). The first spell that can go off goes off.

It rebuilds whenever you learn a spell, spend a talent point or gain a druid form, and waits for the end
of combat if that happens mid-fight.

A macro cannot see buffs or debuffs in combat, so damage-over-time spells are handled with
`/castsequence`: Serpent Sting, Corruption, Shadow Word: Pain and the like are reapplied after a fixed
number of filler casts, and the sequence starts over on a new target.

If the client offers Blizzard's own Single-Button Assistant (`C_AssistedCombat`), IWIN uses it in `auto`
mode, since it can see the things a macro cannot. Use `/iwin mode macro` to keep IWIN's own priority.

## Install

Copy or link this folder into `World of Warcraft\_forever_\Interface\AddOns\IWIN`, then restart the game.

## Use

- **The button**: a square on screen showing the spell it expects to cast next. Drag it to move it.
- **A key**: Options, Keybindings, IWIN, "Cast the next spell".
- **An action bar slot**: `/iwin bar` puts an `IWIN` macro (`/click IWIN_Button`) on your cursor.

| Command | Does |
| --- | --- |
| `/iwin` | Prints the spec and the macro in use |
| `/iwin lock` / `unlock` | Stops or allows dragging the button |
| `/iwin show` / `hide` | Shows or hides the button; the key binding works either way |
| `/iwin bar` | Makes the action bar macro |
| `/iwin mode auto` / `macro` / `blizzard` | Which engine picks the spell |
| `/iwin target` | Toggles picking the nearest enemy when you have no target |
| `/iwin spec <name>` / `auto` | Forces one of your class's priorities |
| `/iwin scale <0.5-2>` / `reset` | Size and position |

Hovering the button lists the macro lines.

## Priorities

Spec is the talent tree you have put the most points in, so a Protection Paladin at level 15 gets the
Protection priority before learning any Protection spell. With no points spent, or a tree with no
priority of its own (Assassination, Survival, Discipline, Restoration), a talent spell you know decides,
and failing that the last one in the list applies. `/iwin` says which rule picked it.

The Paladin priorities follow WoW: Forever's changes: Judgement no longer uses up the Seal, and Holy
Strike is learned at level 6. The Seal goes up at the start of a fight and again after every third
Judgement, about the 30 seconds it lasts; Protection uses Seal of Fury once it is learned.

| Class | Specs | Picked by |
| --- | --- | --- |
| Warrior | Arms, Fury, Protection, Leveling | Mortal Strike, Bloodthirst, Shield Slam |
| Rogue | Subtlety, Combat | Hemorrhage |
| Hunter | Marksmanship, Beast Mastery | Aimed Shot or Trueshot Aura |
| Mage | Fire, Arcane, Frost | Pyroblast, Blast Wave or Combustion; Arcane Power or Presence of Mind |
| Priest | Shadow, Holy | Mind Flay or Shadowform |
| Warlock | Affliction, Destruction, Demonology | Siphon Life, Dark Pact or Amplify Curse; Conflagrate or Shadowburn |
| Paladin | Protection, Retribution, Holy | Holy Shield, Blessing of Sanctuary, Templar's Bulwark or Swift Judgement; Seal of Command or Repentance |
| Shaman | Enhancement, Elemental, Leveling | Stormstrike; Elemental Mastery |
| Druid | Balance, Feral | Moonkin Form. Both follow your form: cat, bear or caster lines |

All of them live in `Rotations.lua` as plain data, with the rules for editing them at the top of the file.

## Limits

- Damage only. Healing has no single right answer, so healers get their damage priority.
- Spell names are English; another client language needs `Rotations.lua` translated.
- A secure macro is capped at 255 characters. `/iwin target` adds a line, and the lowest-value lines
  are left out to make room; `/iwin` lists anything left out.
- Pressing a macro that tries several spells makes the game print "not ready yet" errors. IWIN clears the
  red text after each press; the spoken error can be turned off in Sound settings (Error Speech).
- Off-global-cooldown abilities (Heroic Strike, Maul, Raptor Strike) are queued on every press when you
  have the rage or mana, which can starve the bigger hits of rage at low gear levels.

## Tests

The macro builder is pure Lua and is tested without the game:

```bash
luajit tests/run_tests.lua                 # from this folder
IWIN_PRINT=1 luajit tests/run_tests.lua    # also print every class's level 60 macro
```

CI runs them on every push and pull request (`.github/workflows/tests.yml`).

## Releasing

`.github/workflows/release.yml` cuts a release whenever a pull request is merged into `main`, or by hand
from the Actions tab (Release, Run workflow, with a patch, minor or major bump). It tags the next `v*`
version and runs [BigWigs' packager](https://github.com/BigWigsMods/packager), which writes the version
into the toc, zips the addon without `tests/` (see `.pkgmeta`), and publishes a GitHub release with a
changelog built from the commits.

The same run uploads to CurseForge once two things are set up:

1. The project's ID in `IWIN.toc` as `## X-Curse-Project-ID: <id>` (shown on the project's page on
   CurseForge, under About Project).
2. A CurseForge API token (CurseForge account settings, API Tokens) saved as the repository secret
   `CF_API_KEY`: `gh secret set CF_API_KEY -R kirbycope/IWIN`.

Without them the release still goes to GitHub and the CurseForge step is skipped.

## Licence

MIT, see [LICENSE](LICENSE).
