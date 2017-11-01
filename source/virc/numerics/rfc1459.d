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
	ulong numChannels;
	///
	string message;
	///
	this(string chans, string msg) pure @safe {
		import std.conv : to;
		numChannels = chans.to!ulong;
		message = msg;
	}
}
/++
+
+/
struct LUserOp {
	///
	ulong numOperators;
	///
	string message;
	///
	this(string ops, string msg) pure @safe {
		import std.conv : to;
		numOperators = ops.to!ulong;
		message = msg;
	}
}
/++
+ RPL_VERSION reply contents.
+/
struct VersionReply {
	///The responding server's version string.
	string version_;
	///The server hostmask responding to the version query
	string server;
	///Contents depend on server, but are usually related to version
	string comments;
}

/++
+
+/
//251 :There are <users> users and <services> services on <servers> servers
//TODO: Find out if this is safe to parse
auto parseNumeric(Numeric numeric : Numeric.RPL_LUSERCLIENT, T)(T input) {
	input.popFront();
	return LUserClient(input.front);
}
///
@safe pure /+nothrow @nogc+/ unittest { //Numeric.RPL_LUSERCLIENT
	import std.range : only;
	{
		immutable luser = parseNumeric!(Numeric.RPL_LUSERCLIENT)(only("someone", "There are 42 users and 43 services on 44 servers"));
		assert(luser.message == "There are 42 users and 43 services on 44 servers");
	}
}
/++
+
+/
//252 <opers> :operator(s) online
auto parseNumeric(Numeric numeric : Numeric.RPL_LUSEROP, T)(T input) {
	input.popFront();
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
		immutable luser = parseNumeric!(Numeric.RPL_LUSEROP)(only("someone", "45", "operator(s) online"));
		assert(luser.numOperators == 45);
		assert(luser.message == "operator(s) online");
	}
}

/++
+
+/
//254 <channels> :channels formed
auto parseNumeric(Numeric numeric : Numeric.RPL_LUSERCHANNELS, T)(T input) {
	input.popFront();
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
		immutable luser = parseNumeric!(Numeric.RPL_LUSERCHANNELS)(only("someone", "46", "channels formed"));
		assert(luser.numChannels == 46);
		assert(luser.message == "channels formed");
	}
}
/++
+
+/
//255 :I have <clients> clients and <servers> servers
//TODO: Find out if this is safe to parse
auto parseNumeric(Numeric numeric : Numeric.RPL_LUSERME, T)(T input) {
	input.popFront();
	return LUserMe(input.front);
}
///
@safe pure /+nothrow @nogc+/ unittest { //Numeric.RPL_LUSERME
	import std.range : only;
	{
		immutable luser = parseNumeric!(Numeric.RPL_LUSERME)(only("someone", "I have 47 clients and 48 servers"));
		assert(luser.message == "I have 47 clients and 48 servers");
	}
}

struct ChannelListResult {
	import virc.common : Topic, Mode;
	string name;
	uint userCount;
	Topic topic;
	Mode[] modes;
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
	ChannelListResult channel;
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
struct TopicReply {
	string channel;
	string topic;
}
/++
+ Parser for RPL_TOPIC.
+
+ Format is `332 <client><channel> :<topic>`
+/
auto parseNumeric(Numeric numeric : Numeric.RPL_TOPIC, T)(T input) {
	import std.typecons : Nullable;
	Nullable!TopicReply output = TopicReply();
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
struct NamesReply {
	import std.algorithm : splitter;
	import std.traits : ReturnType;
	NamReplyFlag chanFlag;
	string channel;
	ReturnType!(splitter!("a == b", string, string)) users;
}
/++
+
+/
enum NamReplyFlag : string {
	///Channel will never be shown to users that aren't in it
	secret = "@",
	///Channel will have its name replaced for users that aren't in it
	private_ = "*",
	///Non-private and non-secret channel.
	public_ = "=",
	///ditto
	other = public_
}
/++
+ Parser for RPL_VERSION
+
+ Format is `351 <client> <version> <server> :<comments>`
+/
auto parseNumeric(Numeric numeric : Numeric.RPL_VERSION, T)(T input) {
	import std.typecons : Nullable, Tuple;
	import virc.common : toParsedTuple, User;

	Nullable!VersionReply output;
	const tuple = toParsedTuple!(Tuple!(User, "self", string, "version_", string, "server", string, "comments"))(input);
	if (tuple.isNull) {
		return output.init;
	} else {
		output = VersionReply();
		output.version_ = tuple.version_;
		output.server = tuple.server;
		output.comments = tuple.comments;
		return output;
	}
}
///
@safe pure nothrow @nogc unittest {
	import std.algorithm.searching : canFind;
	import std.array : array;
	import std.range : only, takeNone;
	import virc.ircsplitter : IRCSplitter;
	{
		auto versionReply = parseNumeric!(Numeric.RPL_VERSION)(only("Someone", "ircd-seven-1.1.4(20170104-717fbca8dbac,charybdis-3.4-dev)", "localhost", "eHIKMpSZ6 TS6ow 7IZ"));
		assert(versionReply.version_ == "ircd-seven-1.1.4(20170104-717fbca8dbac,charybdis-3.4-dev)");
		assert(versionReply.server == "localhost");
		assert(versionReply.comments == "eHIKMpSZ6 TS6ow 7IZ");
	}
	{
		immutable versionReply = parseNumeric!(Numeric.RPL_VERSION)(takeNone(only("")));
		assert(versionReply.isNull);
	}
	{
		immutable versionReply = parseNumeric!(Numeric.RPL_VERSION)(only("Someone"));
		assert(versionReply.isNull);
	}
	{
		immutable versionReply = parseNumeric!(Numeric.RPL_VERSION)(only("Someone", "ircd-seven-1.1.4(20170104-717fbca8dbac,charybdis-3.4-dev)"));
		assert(versionReply.isNull);
	}
	{
		immutable versionReply = parseNumeric!(Numeric.RPL_VERSION)(only("Someone", "", "localhost"));
		assert(versionReply.isNull);
	}
}

/++
+ Parser for RPL_NAMREPLY
+
+ Format is `353 <client> =/*/@ <channel> :<prefix[es]><usermask>[ <prefix[es]><usermask>...]`
+/
auto parseNumeric(Numeric numeric : Numeric.RPL_NAMREPLY, T)(T input) {
	import std.algorithm : splitter;
	import std.typecons : Nullable;
	Nullable!NamesReply output = NamesReply();
	if (input.empty) {
		output.nullify();
		return output;
	}
	input.popFront();
	if (input.empty) {
		output.nullify();
		return output;
	}
	output.chanFlag = cast(NamReplyFlag)input.front;
	input.popFront();
	if (input.empty) {
		output.nullify();
		return output;
	}
	output.channel = input.front;
	input.popFront();
	if (input.empty) {
		output.nullify();
		return output;
	}
	output.users = input.front.splitter(" ");
	return output;
}
///
@safe pure nothrow unittest {
	import std.algorithm.searching : canFind;
	import std.array : array;
	import std.range : only, takeNone;
	import virc.ircsplitter : IRCSplitter;
	{
		auto namReply = parseNumeric!(Numeric.RPL_NAMREPLY)(IRCSplitter("someone = #channel :User1 User2 @User3 +User4"));
		assert(namReply.chanFlag == NamReplyFlag.public_);
		assert(namReply.channel == "#channel");
		assert(namReply.users.array.canFind("User1"));
		assert(namReply.users.array.canFind("User2"));
		assert(namReply.users.array.canFind("@User3"));
		assert(namReply.users.array.canFind("+User4"));
	}
	{
		immutable namReply = parseNumeric!(Numeric.RPL_NAMREPLY)(IRCSplitter("someone = #channel"));
		assert(namReply.isNull);
	}
	{
		immutable namReply = parseNumeric!(Numeric.RPL_NAMREPLY)(IRCSplitter("someone ="));
		assert(namReply.isNull);
	}
	{
		immutable namReply = parseNumeric!(Numeric.RPL_NAMREPLY)(IRCSplitter("someone"));
		assert(namReply.isNull);
	}
	{
		immutable namReply = parseNumeric!(Numeric.RPL_NAMREPLY)(takeNone(only("")));
		assert(namReply.isNull);
	}
}