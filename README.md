
# BuffReminder
A World of Warcraft 1.12 (Vanilla WoW) addon that displays user placeable icons on your screen when buffs have expired or are soon to expire.

![example icon image](http://i.imgur.com/i6dGRIO.png)
![BuffReminder Button Image](http://i.imgur.com/gCf7Ygj.png)

## :exclamation: Warning :exclamation:
**Saved variable format has changed in version 1.2. Saved configurations will be lost if you upgrade.**

#### New
- Experimental: Lua script conditional.
- A script should return a value that can evaluate as true or false.
- Example: return UnitMana("player") < 2000

#### Notes
- The config dialog is opened by left-clicking the BR icon.
- Buffs you want to monitor must be added to buff groups.
- Mutually exclusive buffs should go into common groups.
- Until a buff is seen by the addon it will have a '?' icon.
- Temporary weapon enchants (shaman enchants, poisons, wizard oil, sharpening, etc) also supported.
- Icons can be temporarily hidden by right-clicking the BR icon.
- Enclose names with spaces in quotes when using the command line.
- The icon frame lock can be toggled by shift-clicking the BR icon.
- Checkboxes are tri-state. If the background is red then the icon will be hidden if the state is _not_ true.
- If you've used a previous version and you get errors then you may need to NUKE your config (see gen opts).

## Config Dialog
![config dialog image](http://i.imgur.com/XmMvP0U.png)

##Command Line Configuration
Group commands:

	/br group <groupname> add <buffname> - adds a buff to a group. If the group doesn't exist it will be created
	/br group <groupname> remove - removes the buff group
	/br group <groupname> disable - prevents the group's icon from being displayed when one of it's buffs are missing
	/br group <groupname> enable - allows the group's icon to be displayed when one of it's buffs are missing
	/br group <number> - sets the early warning timer for the group
    /br group [dead|instance|party|raid|resting|taxi] - toggles the given conditional for the group
    /br group - prints a listing of your buff groups


Buff commands:

	/br buff <buffname> remove - removes a buff from being monitored
	/br buff <buffname> - prints the group info of the group a buff belongs to
	/br buff - prints a list of your watched buffs


General options:

	/br alpha <number> - changes the icon transparency (min 0.0, max 1.0)
	/br config - opens the config dialog
	/br <lock|unlock> - locks or unlocks the icon frame for user placement
	/br NUKE - clears all of your settings
    /br size <number> - changes the icon size (min 10, max 400)
	/br sound <sound name> - sets the warning sound or turns it off if no name given. ex: /br sound RaidWarning
	/br time <number> - sets the default early warning time setting for new buff groups
