
# BuffReminder
A World of Warcraft: Forever addon that displays user placeable icons on your screen when buffs have expired or are soon to expire. Originally written for WoW 1.12 (Vanilla); the 1.12 version is on the `master` branch.

![example icon image](http://i.imgur.com/i6dGRIO.png)

## Combat behavior
WoW: Forever hides aura data from addons during combat. BuffReminder reads your buffs whenever the game allows it (out of combat) and keeps that snapshot through combat:
- Icons that were showing when combat started keep showing.
- Early warnings and expiry still happen on time in combat, predicted from the expiration times recorded before the pull.
- Buffs gained, lost, dispelled or refreshed during combat are picked up when combat ends.

## Upgrading from 1.x
Your buff groups and options carry over. The saved icon cache is dropped and relearned. Old sound names are converted to sound kit ids where possible.

The config dialog and script editor haven't been ported yet; use the commands below.

#### Notes
- Buffs you want to monitor must be added to buff groups.
- Mutually exclusive buffs should go into common groups.
- Buffs can be given by name (any rank matches) or spell id. `/br auras` lists your current buffs with their ids.
- Temporary weapon enchants (poisons, oils, sharpening stones, etc) are also supported.
- Enclose names with spaces in quotes when using the command line.
- Conditions are tri-state: ignored, hide the icon while true, or hide the icon while false.
- A group script hides the icon while it returns true. Example: `/br group Int script return UnitPower("player") < 2000`

## Command Line Configuration
Group commands:

	/br group <group> add <buff> - adds a buff to a group, creating the group if needed
	/br group <group> remove - removes the group
	/br group <group> disable | enable - stops or allows the group's icon from showing
	/br group <group> <always|dead|instance|party|raid|resting|taxi|combat|mounted> - cycles a condition
	/br group <group> <number> - sets the early warning time in seconds
	/br group <group> script [lua] - hides the icon while the script returns true, no lua clears it
	/br group [group] - lists your groups or shows one group

Buff commands:

	/br buff <buff> remove - stops monitoring a buff
	/br buff [buff] - lists watched buffs or shows the group a buff belongs to
	/br auras - lists your current buffs with their spell ids

Weapon enchants and defaults:

	/br enchant <main|off> - toggles the weapon enchant reminder
	/br default [condition|disable|enable|<number>|script [lua]] - default conditions, used by enchants and new groups
	/br charges <number> - warns when an enchant has this many charges left

General options:

	/br alpha <number> - icon transparency (min 0.0, max 1.0)
	/br size <number> - icon size (min 10, max 400)
	/br lock | unlock - locks or unlocks the icon frame for placement
	/br hide - temporarily hides or shows the icons
	/br sound [id|name] - warning sound when an icon appears, ex: /br sound RAID_WARNING, none turns it off
	/br reseticons - clears the icon cache
	/br NUKE - clears all of your settings
