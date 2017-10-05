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
	import std.datetime : SysTime;
	import std.typecons : Nullable, Tuple;
	import virc.common : toParsedTuple, User;
	auto tuple = toParsedTuple!(Tuple!(User, "self", string, "channel", User, "setter", SysTime, "timestamp"))(input);
	if (tuple.isNull) {
		return Nullable!TopicWhoTime.init;
	}
	return Nullable!TopicWhoTime(TopicWhoTime(tuple.channel, tuple.setter, tuple.timestamp));
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