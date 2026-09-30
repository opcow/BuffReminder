
# BuffReminder
A World of Warcraft: Forever addon that displays user placeable icons on your screen when buffs have expired or are soon to expire. Originally written for WoW 1.12 (Vanilla); the 1.12 version is on the `master` branch.

![example icon image](docs/screen_1.png)

## Combat behavior
WoW: Forever hides aura data from addons during combat, and the list of your buffs can't be read at all. Out of combat BuffReminder reads every buff and records its expiration time. Each group has an **In combat** setting that picks how it's followed during a fight.

**Cooldown Manager** (the default). The group is checked once a second and on every aura change, using the best source available:

1. **Direct lookup.** The addon asks about each of the group's spells by id. The game still answers for spells it flags as never secret, so these buffs update live in combat: dropped, dispelled, refreshed, and stack counts. Buffs given by name are looked up by the spell id last seen on the aura, or by any rank of your own spell of that name.
2. **Cooldown Manager.** If the spell is secret but it's one of your class buffs tracked on the Cooldown Manager's buff bars or icons, and the Cooldown Manager is turned on, BuffReminder reads whether that buff is active from the manager's frames. When the manager's remaining time is readable it's used for the countdown, otherwise the old expiration time is kept.
3. **Prediction.** Otherwise the group keeps the state it had when combat started. Its own timer runs from the expiration time recorded before the pull, so early warnings and expiry still show on time. Buffs lost or refreshed early aren't seen until combat ends.

If a group can only be predicted, because the Cooldown Manager isn't available for your class, is turned off, or doesn't track the buff, BuffReminder says so in chat after you log in and on the Buff groups tab.

**Blizzard Auras**, for buffs the Cooldown Manager can't track, like a shaman's Lightning Shield. Blizzard's own aura button is placed over the group's icon and shows the buff with its exact time and stack count for the whole fight, with the count in red at or under the group's low stack warning. When the buff drops the button disappears and the reminder icon underneath shows. Addon code can't read what Blizzard's button shows, so in combat the group's icon is always shown, not only when the buff is missing or low. Use the group's conditions to limit when that is. The button is set up out of combat and needs the buff's spell id, which is known once you've had the buff or when you add it by id.

When combat ends everything is read again, which corrects any prediction.

## Low stack warning
A group can warn when its buff is down to a number of stacks or charges, ex: Inner Fire at 3 (Buff groups tab). The icon shows with the count in the lower right corner and the time left at the top. The time left text, the cooldown swipe and the stack count can each be turned off, and when an icon has both texts you can pick which one shows (Options tab). Each group can override how it shows the time left: text, swipe, both or none (Buff groups tab). In combat the count only updates when the buff can be read live (source 1 or 2 above, when the manager exposes the aura), or on Blizzard's button in Blizzard Auras groups. Otherwise it's refreshed after combat.

## Weapon enchants
Temporary weapon enchants, like poisons, oils, sharpening stones and shaman imbues, have two built-in groups at the top of the Buff groups list: **Main hand enchant** and **Off hand enchant**. They start turned off; set **Show** to Normal to use one. Each hand has its own conditions, early warning time, low charges warning, script, time left and icon size, the same as a buff group. They can't be deleted and have no In combat setting, since weapon enchants can always be read.

## Upgrading from 1.x
Your buff groups and options carry over. A weapon enchant that was turned on becomes its hand's enchant group, with the old default conditions, warning time, charges warning and script. The saved icon cache is dropped and relearned. Old sound names are converted to sound kit ids where possible.

## Placing icons
Icons snap together on a grid, into rows, columns, squares or any other shape. At first every icon is in one row. Unlock the icons (the Options tab or Shift-click the minimap button) and every icon shows, grey when it isn't needed right now:
- Drag an icon to move it together with the icons snapped to it.
- Shift-drag an icon to pull it away on its own, like taking a button off an action bar.
- Drop icons touching others, above, below or beside them, and they snap on. Dropped into a row or column they push the rest along.

A straight row or column closes up and centers the icons it's showing, like the 1.x row did. Any other shape keeps its gaps, so each icon keeps its spot.

Each group can have its own icon size (Buff groups tab). Every row is as tall and every column as wide as its biggest icon. A smaller icon lines up with the top, middle or bottom of its row, or the left, center or right of its column, whichever is nearest where you drop it. Dropping a big icon beside smaller ones lines them up the same way. "Icons in one row" on the Options tab puts every icon back in one row. Lock the icons again when you're done.

## Options window
Everything is set up here. Open it with `/br`, the minimap button or the addon compartment (the addons button by the minimap). Drag the minimap button to move it around the minimap, the Options tab hides it. Clicking either button:
- Left-click opens the options window.
- Right-click temporarily hides or shows the icons.
- Shift-click unlocks or locks the icons for moving.

The **Buff groups** tab manages groups and the weapon enchant groups, their buffs, conditions, early warning time, low stack warning, script, how the time left shows, how a missing buff is marked, icon size and how they're followed in combat, with a line saying how well that works for the group. "Browse..." picks a buff from a searchable list with three tabs:
- **My spells**: spells in your spellbook that look like buffs, going by their description. "Show all spells" lists every spell if one is missed.
- **Active now**: the buffs you have right now.
- **Seen before**: buffs you've had on this character, including food, elixirs and buffs other players cast on you. The last 200 are kept.

Buffs already in a group are greyed out with the group's name.

The **Options** tab has the defaults new groups start with, the default icon size, the opacity of icons whose buff is missing and of ones warning it's running out or low on stacks, how icons whose buff is missing are marked, the warning sound and a reset button. "Browse..." beside the warning sound lists the game's sounds, click one to use it and hear it.

"Copy from..." on the Options tab replaces this character's settings (buff groups, weapon enchants, options and icon placement) with another character's. A character is listed once it has logged in with BuffReminder, and its list shows the settings it had when it last logged out. The X beside a character forgets it.

A missing buff can be marked with a glow (pulse, flash, steady, or the game's spell alert glow like a proc on an action button) and a color washed over the icon, ex: red. Each group picks its own or follows the Options tab. Icons that are only running out or low on stacks aren't marked.

Text fields save when you press Enter, Escape undoes the edit. Text shows yellow until it's saved.

Condition checkboxes cycle through three states: off, hide the icon while true, and hide the icon while false (red check).

#### Notes
- Buffs you want to monitor must be added to buff groups.
- Mutually exclusive buffs should go into common groups.
- A buff that's one of your own spells isn't shown while the spell is on cooldown, ex: Berserking, since it can't be cast yet. When the game hides the cooldown in combat it's predicted from when you cast the buff. A group that also has a buff you don't cast, like food, always shows.
- Buffs can be given by name (any rank matches) or spell id.
- Conditions are tri-state: ignored, hide the icon while true, or hide the icon while false.
- A group script hides the icon while it returns true. Example: `return UnitPower("player") < 2000`
