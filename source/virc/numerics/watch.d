/++
+
+/
module virc.numerics.watch;

import std.algorithm.comparison : among;

import virc.numerics.definitions;
/++
+
+/
//600 <nickname> <username> <hostname> <signontime> :logged on
//601 <nickname> <username> <hostname> <lastnickchange> :logged off
//602 <nickname> <username> <hostname> <lastnickchange> :stopped watching
//604 <nickname> <username> <hostname> <lastnickchange> :is online
//605 <nickname> <username> <hostname> <lastnickchange> :is offline
//609 <nickname> <username> <hostname> <awaysince> :is away
auto parseNumeric(Numeric numeric, T)(T input) if (numeric.among(Numeric.RPL_LOGON, Numeric.RPL_LOGOFF, Numeric.RPL_WATCHOFF, Numeric.RPL_NOWOFF, Numeric.RPL_NOWON, Numeric.RPL_NOWISAWAY)) {
	import std.conv : to;
	import std.datetime : SysTime, UTC;
	import std.typecons : tuple;
	import virc.common : User;
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
		immutable logon = parseNumeric!(Numeric.RPL_LOGON)(only("someone", "someIdent", "example.net", "911248013", "logged on"));
		assert(logon.user.mask.nickname == "someone");
		assert(logon.user.mask.ident == "someIdent");
		assert(logon.user.mask.host == "example.net");
		static immutable date = SysTime(DateTime(1998, 11, 16, 20, 26, 53), UTC());
		assert(logon.timeOccurred == date);
	}
}