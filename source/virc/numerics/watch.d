/++
+
+/
module virc.numerics.watch;

import std.algorithm.comparison : among;

import virc.numerics.definitions;
/++
+ Parses most of the WATCH numerics. Most of them have the same format, so the
+ majority of the magic happens in this function.
+
+ Formats are:
+
+ `600 <client> <nickname> <username> <hostname> <signontime> :logged on`
+
+ `601 <client> <nickname> <username> <hostname> <lastnickchange> :logged off`
+
+ `602 <client> <nickname> <username> <hostname> <lastnickchange> :stopped watching`
+
+ `604 <client> <nickname> <username> <hostname> <lastnickchange> :is online`
+
+ `605 <client> <nickname> <username> <hostname> <lastnickchange> :is offline`
+
+ `609 <client> <nickname> <username> <hostname> <awaysince> :is away`
+
+ Standards: Conforms to https://raw.githubusercontent.com/grawity/irc-docs/master/client/draft-meglio-irc-watch-00.txt
+/
auto parseNumeric(Numeric numeric, T)(T input) if (numeric.among(Numeric.RPL_LOGON, Numeric.RPL_LOGOFF, Numeric.RPL_WATCHOFF, Numeric.RPL_NOWOFF, Numeric.RPL_NOWON, Numeric.RPL_NOWISAWAY)) {
	import std.conv : to;
	import std.datetime : SysTime, UTC;
	import std.typecons : tuple;
	import virc.common : User;
	input.popFront();
	auto user = User();
	user.mask.nickname = input.front;
	input.popFront();
	user.mask.ident = input.front;
	input.popFront();
	user.mask.host = input.front;
	input.popFront();
	auto timeOccurred = SysTime.fromUnixTime(input.front.to!long, UTC());
	return tuple!("user", "timeOccurred")(user, timeOccurred);
}
///
@safe pure /+nothrow @nogc+/ unittest { //Numeric.RPL_LOGON
	import std.datetime : DateTime, SysTime, UTC;
	import std.range : only;
	{
		immutable logon = parseNumeric!(Numeric.RPL_LOGON)(only("someone", "someoneElse", "someIdent", "example.net", "911248013", "logged on"));
		assert(logon.user.mask.nickname == "someoneElse");
		assert(logon.user.mask.ident == "someIdent");
		assert(logon.user.mask.host == "example.net");
		static immutable date = SysTime(DateTime(1998, 11, 16, 20, 26, 53), UTC());
		assert(logon.timeOccurred == date);
	}
}