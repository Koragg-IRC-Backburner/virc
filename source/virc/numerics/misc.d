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
/++
+ Parser for RPL_WHOISSECURE
+
+ Format is `671 <client> <nick> :is using a secure connection`
+/
auto parseNumeric(Numeric numeric : Numeric.RPL_WHOISSECURE, T)(T input) {
	import virc.numerics.magicparser : autoParse;
	import virc.numerics.rfc1459 : InfolessWhoisReply;
	return autoParse!InfolessWhoisReply(input);
}
///
@safe pure nothrow unittest {
	import virc.common : User;
	import std.range : only, takeNone;
	{
		auto reply = parseNumeric!(Numeric.RPL_WHOISSECURE)(only("someone", "whoisuser", "is using a secure connection"));
		assert(reply.user == User("whoisuser"));
	}
	{
		immutable reply = parseNumeric!(Numeric.RPL_WHOISSECURE)(only("someone", "whoisuser"));
		assert(reply.isNull);
	}
	{
		immutable reply = parseNumeric!(Numeric.RPL_WHOISSECURE)(only("someone"));
		assert(reply.isNull);
	}
	{
		immutable reply = parseNumeric!(Numeric.RPL_WHOISSECURE)(takeNone(only("")));
		assert(reply.isNull);
	}
}
/++
+ Parser for RPL_WHOISREGNICK
+
+ Format is `307 <client> <nick> :is a registered nick`
+/
auto parseNumeric(Numeric numeric : Numeric.RPL_WHOISREGNICK, T)(T input) {
	import virc.numerics.magicparser : autoParse;
	import virc.numerics.rfc1459 : InfolessWhoisReply;
	return autoParse!InfolessWhoisReply(input);
}
///
@safe pure nothrow unittest {
	import virc.common : User;
	import std.range : only, takeNone;
	{
		auto reply = parseNumeric!(Numeric.RPL_WHOISREGNICK)(only("someone", "whoisuser", "is a registered nick"));
		assert(reply.user == User("whoisuser"));
	}
	{
		immutable reply = parseNumeric!(Numeric.RPL_WHOISREGNICK)(only("someone", "whoisuser"));
		assert(reply.isNull);
	}
	{
		immutable reply = parseNumeric!(Numeric.RPL_WHOISREGNICK)(only("someone"));
		assert(reply.isNull);
	}
	{
		immutable reply = parseNumeric!(Numeric.RPL_WHOISREGNICK)(takeNone(only("")));
		assert(reply.isNull);
	}
}
struct WhoisAccountReply {
	import virc.common : User;
	User me;
	///User who is being queried.
	User user;
	///Account name for this user.
	string account;
	///Human-readable numeric message.
	string message;
}
/++
+ Parser for RPL_WHOISACCOUNT
+
+ Format is `330 <client> <nick> <account> :is logged in as`
+/
auto parseNumeric(Numeric numeric : Numeric.RPL_WHOISACCOUNT, T)(T input) {
	import virc.numerics.magicparser : autoParse;
	return autoParse!WhoisAccountReply(input);
}
///
@safe pure nothrow unittest {
	import virc.common : User;
	import std.range : only, takeNone;
	{
		auto reply = parseNumeric!(Numeric.RPL_WHOISACCOUNT)(only("someone", "whoisuser", "accountname", "is logged in as"));
		assert(reply.user == User("whoisuser"));
		assert(reply.account == "accountname");
	}
	{
		immutable reply = parseNumeric!(Numeric.RPL_WHOISACCOUNT)(only("someone", "whoisuser", "accountname"));
		assert(reply.isNull);
	}
	{
		immutable reply = parseNumeric!(Numeric.RPL_WHOISACCOUNT)(only("someone", "whoisuser"));
		assert(reply.isNull);
	}
	{
		immutable reply = parseNumeric!(Numeric.RPL_WHOISACCOUNT)(only("someone"));
		assert(reply.isNull);
	}
	{
		immutable reply = parseNumeric!(Numeric.RPL_WHOISACCOUNT)(takeNone(only("")));
		assert(reply.isNull);
	}
}