/++
+
+/
module virc.numerics.rfc1459;

import virc.modes : ModeType;
import virc.numerics.definitions;

/++
+
+/
struct LUserClient {
	///
	string message;
	///
	this(string msg) pure @safe {
		message = msg;
	}
}
/++
+
+/
struct LUserMe {
	///
	string message;
	///
	this(string msg) pure @safe {
		message = msg;
	}
}
/++
+
+/
struct LUserChannels {
	///
	ulong numChans;
	///
	string message;
	///
	this(string chans, string msg) pure @safe {
		import std.conv : to;
		numChans = chans.to!ulong;
		message = msg;
	}
}
/++
+
+/
struct LUserOp {
	///
	ulong numOpers;
	///
	string message;
	///
	this(string ops, string msg) pure @safe {
		import std.conv : to;
		numOpers = ops.to!ulong;
		message = msg;
	}
}

/++
+
+/
//251 :There are <users> users and <services> services on <servers> servers
//TODO: Find out if this is safe to parse
auto parseNumeric(Numeric numeric : Numeric.RPL_LUSERCLIENT, T)(T input) {
	return LUserClient(input.front);
}
///
@safe pure /+nothrow @nogc+/ unittest { //Numeric.RPL_LUSERCLIENT
	import std.range : only;
	{
		immutable luser = parseNumeric!(Numeric.RPL_LUSERCLIENT)(only("There are 42 users and 43 services on 44 servers"));
		assert(luser.message == "There are 42 users and 43 services on 44 servers");
	}
}
/++
+
+/
//252 <opers> :operator(s) online
auto parseNumeric(Numeric numeric : Numeric.RPL_LUSEROP, T)(T input) {
	auto ops = input.front;
	input.popFront();
	auto msg = input.front;
	auto output = LUserOp(ops, msg);
	return output;
}
///
@safe pure /+nothrow @nogc+/ unittest { //Numeric.RPL_LUSEROP
	import std.range : only;
	{
		immutable luser = parseNumeric!(Numeric.RPL_LUSEROP)(only("45", "operator(s) online"));
		assert(luser.numOpers == 45);
		assert(luser.message == "operator(s) online");
	}
}

/++
+
+/
//254 <channels> :channels formed
auto parseNumeric(Numeric numeric : Numeric.RPL_LUSERCHANNELS, T)(T input) {
	auto chans = input.front;
	input.popFront();
	auto msg = input.front;
	auto output = LUserChannels(chans, msg);
	return output;
}
///
@safe pure /+nothrow @nogc+/ unittest { //Numeric.RPL_LUSERCHANNELS
	import std.range : only;
	{
		immutable luser = parseNumeric!(Numeric.RPL_LUSERCHANNELS)(only("46", "channels formed"));
		assert(luser.numChans == 46);
		assert(luser.message == "channels formed");
	}
}
/++
+
+/
//255 :I have <clients> clients and <servers> servers
//TODO: Find out if this is safe to parse
auto parseNumeric(Numeric numeric : Numeric.RPL_LUSERME, T)(T input) {
	return LUserMe(input.front);
}
///
@safe pure /+nothrow @nogc+/ unittest { //Numeric.RPL_LUSERME
	import std.range : only;
	{
		immutable luser = parseNumeric!(Numeric.RPL_LUSERME)(only("I have 47 clients and 48 servers"));
		assert(luser.message == "I have 47 clients and 48 servers");
	}
}

/++
+
+/
//322 <username> <channel> <count> :[\[<modes\] ]<topic>
auto parseNumeric(Numeric numeric : Numeric.RPL_LIST, T)(T input, ModeType[char] channelModeTypes) {
	import std.algorithm.iteration : filter, map;
	import std.algorithm.searching : findSplitAfter, startsWith;
	import std.array : array;
	import std.conv : parse;
	import virc.common : Change, Channel, parseModeString, Topic;
	//Note: RFC2812 makes no mention of the modes being included.
	//Seems to be a de-facto standard, supported by several softwares.
	Channel channel;
	//username doesn't really help us here. skip it
	input.popFront();
	channel.name = input.front;
	input.popFront();
	auto str = input.front;
	channel.userCount = parse!uint(str);
	input.popFront();
	if (input.front.startsWith("[+")) {
		auto splitTopicStr = input.front.findSplitAfter("] ");
		channel.topic = Topic(splitTopicStr[1]);
		channel.modes = parseModeString(splitTopicStr[0][1..$], channelModeTypes).filter!(x => x.change == Change.set).map!(x => x.mode).array;
	} else {
		channel.topic = Topic(input.front);
	}
	return channel;
}
///
@safe pure /+nothrow @nogc+/ unittest { //Numeric.RPL_LIST
	import std.algorithm.searching : canFind;
	import std.range : only;
	import std.typecons : Nullable;
	import virc.common : Topic;
	import virc.modes : Mode;
	{
		immutable listEntry = parseNumeric!(Numeric.RPL_LIST)(only("someone", "#test", "4", "[+fnt 200:2] some words"), ['n': ModeType.d, 't': ModeType.d, 'f': ModeType.c]);
		assert(listEntry.name == "#test");
		assert(listEntry.userCount == 4);
		assert(listEntry.topic == Topic("some words"));
		assert(listEntry.modes.canFind(Mode(ModeType.d, 'n')));
		assert(listEntry.modes.canFind(Mode(ModeType.d, 't')));
		assert(listEntry.modes.canFind(Mode(ModeType.c, 'f', Nullable!string("100:2"))));
	}
	{
		immutable listEntry = parseNumeric!(Numeric.RPL_LIST)(only("someone", "#test2", "6", "[+fnst 100:2] some more words"), ['n': ModeType.d, 't': ModeType.d, 'f': ModeType.c]);
		assert(listEntry.name == "#test2");
		assert(listEntry.userCount == 6);
		assert(listEntry.topic == Topic("some more words"));
		assert(listEntry.modes.canFind(Mode(ModeType.d, 'n')));
		assert(listEntry.modes.canFind(Mode(ModeType.d, 't')));
		assert(listEntry.modes.canFind(Mode(ModeType.d, 's')));
		assert(listEntry.modes.canFind(Mode(ModeType.c, 'f', Nullable!string("100:2"))));
	}
	{
		immutable listEntry = parseNumeric!(Numeric.RPL_LIST)(only("someone", "#test3", "1", "no modes?"), ['n': ModeType.d, 't': ModeType.d, 'f': ModeType.c]);
		assert(listEntry.name == "#test3");
		assert(listEntry.userCount == 1);
		assert(listEntry.topic == Topic("no modes?"));
		assert(listEntry.modes.length == 0);
	}
}
/++
+ Parser for RPL_TOPIC.
+
+ Format is `332 <client><channel> :<topic>`
+/
auto parseNumeric(Numeric numeric : Numeric.RPL_TOPIC, T)(T input) {
	import std.typecons : Nullable, Tuple;
	Nullable!(Tuple!(string, "channel", string, "topic")) output = Tuple!(string, "channel", string, "topic")();
	if (input.empty) {
		output.nullify;
		return output;
	}
	input.popFront();
	if (input.empty) {
		output.nullify;
		return output;
	}
	output.channel = input.front;
	input.popFront();
	if (input.empty) {
		output.nullify;
		return output;
	}
	output.topic = input.front;
	return output;
}
///
@safe pure nothrow @nogc unittest {
	import std.range : only, takeNone;
	{
		immutable topic = parseNumeric!(Numeric.RPL_TOPIC)(only("someone", "#channel", "This is the topic!"));
		assert(topic.channel == "#channel");
		assert(topic.topic == "This is the topic!");
	}
	{
		immutable topic = parseNumeric!(Numeric.RPL_TOPIC)(takeNone(only("")));
		assert(topic.isNull);
	}
	{
		immutable topic = parseNumeric!(Numeric.RPL_TOPIC)(only("someone"));
		assert(topic.isNull);
	}
	{
		immutable topic = parseNumeric!(Numeric.RPL_TOPIC)(only("someone", "#channel"));
		assert(topic.isNull);
	}
}

/++
+
+/
//353 =/*/@ <channel> :<prefix[es]><usermask>[ <prefix[es]><usermask>...]
auto parseNumeric(Numeric numeric : Numeric.RPL_NAMREPLY, T)(T input) {
	auto chanFlag = input.front;
	input.popFront();
	auto channel = input.front;
	return "";
}
///
unittest {

}