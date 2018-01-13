/++
+
+/
module virc.numerics.misc;

import virc.numerics.definitions;
/++
+
+/
auto parseNumeric(Numeric numeric)() if (numeric.among(noInformationNumerics)) {
	static assert(0, "Cannot parse "~numeric~": No information to parse.");
}
/++
+
+/
struct TopicWhoTime {
	import std.datetime : SysTime;
	import virc.common : User;
	User me;
	///Channel that the topic was set on.
	string channel;
	///The nickname or full mask of the user who set the topic.
	User setter;
	///The time the topic was set. Will always be UTC.
	SysTime timestamp;
}
/++
+ Parse RPL_TOPICWHOTIME (aka RPL_TOPICTIME) numeric replies.
+
+ Format is `333 <user> <channel> <setter> <timestamp>`
+/
auto parseNumeric(Numeric numeric : Numeric.RPL_TOPICWHOTIME, T)(T input) {
	import virc.numerics.magicparser : autoParse;
	return autoParse!TopicWhoTime(input);
}
///
@safe pure nothrow unittest {
	import std.datetime : DateTime, SysTime, UTC;
	import std.range : only, takeNone;
	{
		immutable result = parseNumeric!(Numeric.RPL_TOPICWHOTIME)(only("Someone", "#test", "Another!id@hostmask", "1496101944"));
		assert(result.channel == "#test");
		assert(result.setter.nickname == "Another");
		assert(result.setter.ident == "id");
		assert(result.setter.host == "hostmask");
		static immutable time = SysTime(DateTime(2017, 05, 29, 23, 52, 24), UTC());
		assert(result.timestamp == time);
	}
	{
		immutable badResult = parseNumeric!(Numeric.RPL_TOPICWHOTIME)(takeNone(only("")));
		assert(badResult.isNull);
	}
	{
		immutable badResult = parseNumeric!(Numeric.RPL_TOPICWHOTIME)(only("Someone"));
		assert(badResult.isNull);
	}
	{
		immutable badResult = parseNumeric!(Numeric.RPL_TOPICWHOTIME)(only("Someone", "#test"));
		assert(badResult.isNull);
	}
	{
		immutable badResult = parseNumeric!(Numeric.RPL_TOPICWHOTIME)(only("Someone", "#test", "Another!id@hostmask"));
		assert(badResult.isNull);
	}
	{
		immutable badResult = parseNumeric!(Numeric.RPL_TOPICWHOTIME)(only("Someone", "#test", "Another!id@hostmask", "invalidTimestamp"));
		assert(badResult.isNull);
	}
}

struct NoPrivsError {
	import virc.common : User;
	User me;
	///The missing privilege that prompted this error reply.
	string priv;
	///Human-readable error message.
	string message;
}
/++
+ Parse ERR_NOPRIVS numeric replies.
+
+ Format is `723 <user> <priv> :Insufficient oper privileges.`
+/
auto parseNumeric(Numeric numeric : Numeric.ERR_NOPRIVS, T)(T input) {
	import virc.numerics.magicparser : autoParse;
	return autoParse!NoPrivsError(input);
}
///
@safe pure nothrow unittest {
	import std.range : only, takeNone;
	{
		immutable result = parseNumeric!(Numeric.ERR_NOPRIVS)(only("Someone", "rehash", "Insufficient oper privileges."));
		assert(result.priv == "rehash");
		assert(result.message == "Insufficient oper privileges.");
	}
	{
		immutable badResult = parseNumeric!(Numeric.ERR_NOPRIVS)(takeNone(only("")));
		assert(badResult.isNull);
	}
	{
		immutable badResult = parseNumeric!(Numeric.ERR_NOPRIVS)(only("Someone"));
		assert(badResult.isNull);
	}
}