# Changelog

## 2.1

### Added

- Casting one of a group's buffs on yourself during combat marks the group as up right away. Its timer starts from the cast and uses the buff's duration from the last time it was read out of combat. It works in both In combat modes and doesn't need the aura to be readable. Casts on other players don't count.
- Buff durations are now saved with the "Seen before" list, so they're known after logging in.
- `/obr debug` prints what each cast of a group's buff decides and when a combat read marks a buff as gone.

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
