
#BuffReminder
A World of Warcraft 1.12 (Vanilla WoW) addon that displays icons on your screen when buffs have expired.

![example icon image]({{site.baseurl}}/http://i.imgur.com/yGQt273.png)


Buffs you want to monitor must be added to buff groups.

Mutually exclusive buffs should go into common groups.

Until a buff is seen by the addon it will have a '?' icon.

Enclose names with spaces in quotes.

Group commands:

	/br group <groupname> add <buffname> - Adds a buff to a group. If the group doesn't exist it will be created.

	/br group <groupname> remove - Removes the buff group.

	/br group <groupname> disable - Prevents the group's icon from being displayed when one of it's buffs are missing.

	/br group <groupname> enable - Allows the group's icon to be displayed when one of it's buffs are missing.

	/br group <number> - Sets the early warning timer for the group.

    /br group [dead|instance|party|raid|resting|taxi] - Toggles the given conditional for the group.

    /br group - Prints a listing of your buff groups.


Buff commands:

	/br buff <buffname> remove - Removes a buff from being monitored.

	/br buff <buffname> - Prints the group info of the group a buff belongs to.

	/br buff - Prints a list of your watched buffs.


General options:

	/br alpha <number> - changes the icon transparency (min 0.0, max 1.0).

	/br <lock|unlock> - locks or unlocks the icon frame for user placement.

	/br NUKE - clears all of your settings.

    /br size <number> - changes the icon size (min 10, max 400).

	/br sound <sound name> - sets the warning sound or turns it off if no name given. ex: /br sound RaidWarning

	/br time <number> - sets the default early warning time setting for new buff groups.
