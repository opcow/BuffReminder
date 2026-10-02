# Changelog

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
