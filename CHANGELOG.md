# Changelog

## Unreleased

### Added

- Icons that cast a spell when clicked show the global cooldown swipe, like an action button, so you can see when the next one can be clicked. Party reminder icons too.
- A chat warning when you cast a buff group's spell on yourself at a lower rank than you know (casts on low level players, which the game lowers by itself, don't count), ex: an action bar still holding the old rank after a visit to the trainer. The Cooldown Manager follows only your highest rank, so an old one can't be followed in combat. It warns once per rank each session.

### Fixed

- A Cooldown Manager buff group, ex: Power Word: Fortitude, could show its icon in every fight while the buff was up. The manager's frame for the buff can stop following it, and a "gone" read from it was believed for the rest of the session once it had shown the buff up. Now that frame has to show the buff up in the same fight, and the rank it follows has to be the one last read on you. Otherwise the buff group is predicted.

## 2.7

### Added

- "Time left text" on the Options tab puts the time left on the icon, as before, or just above or below it. It applies to every icon, Blizzard Auras and alerts included, but not party reminders.
- "Combat badge" on the Options tab puts crossed swords in the bottom left corner of every icon while you're in combat, alerts included. Off by default.

### Fixed

- An alert set to the Spell alert glow caused a "blocked by secret aspects" error. The game's spell alert can't be shown on Blizzard's aura button, so alerts no longer offer it, and ones set to it now Pulse.

### Changed

- An alert's swipe now darkens the icon as the aura runs out, instead of starting dark and lighting up.

## 2.6

### Added

- Alerts, on a new Alerts tab: an icon that shows while an aura is on you, ex: Clearcasting from Omen of Clarity. Add one by name (every rank) or spell id, or browse the buffs you have now or have had. It's Blizzard's own aura button, so it shows in combat too with the exact time and stacks. Each alert has its own size, opacity, glow and color, time left, conditions and script, and a sound the game plays as the aura is put on. Unlock the icons to place it with the others.
- "Auto" under Charges used by, the new default, sets it up for you for Lightning Shield, Inner Fire and Shadowguard, every rank. Other buffs aren't counted, as with Off. Buff groups that were on Off are now on Auto, and ones set by hand keep their settings.
- "Hits + absorbed" under Charges used by, for buffs like Shadowguard whose charges are used even by hits Power Word: Shield absorbs.
- With `/obr debug` on, each fight ends with a line comparing the charges counted by hits to the real count, to help set a buff group's Cooldown.

### Fixed

- Blizzard Auras showed a stack count of 1 on buffs without stacks. Counts now start at 2, like Blizzard's own buttons, or at 1 when the buff group has Warn at stacks set.
- The hit that starts a fight could be missed by Charges used by, leaving the count one charge too high.
- Recasting a Cooldown Manager buff in combat could lose its charges, so Charges used by stopped counting until combat ended. The manager still shows the buff as gone for a moment after the cast, and that read undid the cast.
- Recasting a buff in combat started its Cooldown over, so the next hit used a charge even when the game's own cooldown was still running.

## 2.5

### Changed

- "Hit cooldown" became a "Charges used by" row under In combat: Off, Hits, or Physical hits (melee and ranged only, for Inner Fire), with a Cooldown that can be 0 for buffs where every hit uses a charge. Buff groups with a hit cooldown set in 2.4 count any hit, as before. The options window is a little taller to fit it.

### Fixed

- A buff tracked on the Cooldown Manager that the manager doesn't actually follow, ex: Mark of the Wild, showed as missing all through combat while you had it. Buff Reminder now only believes the manager says a buff is gone once it has seen the manager show that buff as up, and predicts it until then.
- The Cooldown Manager follows only one rank of some buffs, ex: Mark of the Wild rank 2 when you have rank 3, and adding the buff again doesn't change it. The Buff groups tab and the login message now say when that happens, so the buff group can be switched to Blizzard Auras.
- A buff whose spell was on cooldown, ex: Berserking, showed in combat, since the game hides cooldowns then. A cooldown read before the pull is now kept through it, and a cast in combat is timed with the spell's cooldown as last read, even when the buff's own duration isn't known yet.
- Hits fully absorbed by a shield, ex: Power Word: Shield, used a charge of Inner Fire or Lightning Shield.
- Blizzard Auras showed a stack count of 0 on buffs without stacks, ex: Mark of the Wild.

## 2.4

### Added

- Charges used by hits, for buffs like Lightning Shield whose charges can't be read in combat. Give a Cooldown Manager buff group a "Hit cooldown" on the Buff groups tab, ex: 3, and its charges count down from the pull, one for each hit you take that lands at least that long after the last charge was used. At 0 the icon shows the buff as gone, and Warn at stacks warns before that. Recasting it in combat starts over with full charges.

## 2.3

### Added

- Click a weapon enchant icon to put the same poison, oil, sharpening stone or imbue on that hand again. Buff Reminder remembers what you last put on each hand out of combat. "Click to apply" on the Buff groups tab shows it and can turn it off. Out of combat, the icon's corner shows how many are left in your bags (red at 0), or "?" while nothing is remembered. "Count" beside it shows the count all the time, in combat too. When the icon can't be clicked, ex: in combat or with none left in your bags, its tooltip shows what was last used and why.
- Named saves. "Save / load..." on the Options tab saves this character's settings under a name, and any character on the account can load them. Copying from another character is still there, in the same list.

### Changed

- The options window switches between Buff groups and Options with tabs under the window, like the character window's, instead of buttons.

## 2.2

### Added

- Click a buff group's icon to cast its spell on yourself. Each buff group picks the spell under "Click to cast" on the Buff groups tab: Auto (the first of your own spells in the buff group), one of them, or Off. Icons can't be clicked in combat or while they're unlocked. "Click to cast" on the Options tab turns it off for every buff group, or sets the click by doing it: any mouse button, with Shift, Ctrl or Alt if you like.
- Each buff group can have its own opacity for a missing buff and for a warning. Empty follows the Options tab.
- Icons warning that a buff is running out or low on stacks can have a glow and color too, ex: a pulse. Set it on the Options tab, or for each buff group on the Buff groups tab.
- Party reminders. Once you've given a party member a buff from one of your buff groups, a panel shows their name and the buff's icon when it's gone, with an optional early warning. Buff groups can opt out with "Party" on the Buff groups tab. Nothing is saved, and it's hidden in combat. Unlocked, the panel shows four made up members to place it by. The icons show by Blizzard's party frames, standard or raid-style, on a side picked from how the frames are laid out (beside them when stacked, above or below when side by side). They can be put on a set side, or on the panel, instead (Options tab).
- Click to dismiss: right click an icon, yours or a party member's, to hide it until the buff is put on again. Works in combat. The click can be changed or turned off on the Options tab.
- A preview icon beside the missing and warning glow and color buttons shows how the icon will look, opacity included.

## 2.1

### Added

- Casting one of a buff group's buffs on yourself during combat marks the buff group as up right away. Its timer starts from the cast and uses the buff's duration from the last time it was read out of combat. It works in both In combat modes and doesn't need the aura to be readable. Casts on other players don't count.
- Buff durations are now saved with the "Seen before" list, so they're known after logging in.
- `/obr debug` prints what each cast of a buff group's buff decides and when a combat read marks a buff as gone.

### Fixed

- The login message and the Cooldown Manager notice said `/br` instead of `/obr`.

## 2.0

- Ported to WoW: Forever.
- Buffs are followed in combat, when aura data is hidden from addons, by direct lookups, the Cooldown Manager, or Blizzard's own aura buttons.
- Options window, opened with `/obr`, the minimap button or the addon compartment.
- Icons snap together on a grid, with per-group icon sizes.
- Weapon enchant groups for each hand.
- Buff picker with your spells, active buffs and buffs seen before.
- Copy settings from another character.
- Renamed to Opcow's Buff Reminder.
