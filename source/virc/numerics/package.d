/++
+ Module for defining, parsing and handling the large number of IRC numerics.
+/
module virc.numerics;
import std.algorithm : among, filter, findSplit, findSplitAfter, map, skipOver, splitter, startsWith;
import std.array : array;
import std.conv : parse, to;
import std.datetime : SysTime, UTC;
import std.meta : AliasSeq;
import std.range : empty, front, popFront, zip;
import std.string : toLower;
import std.typecons : Nullable, Tuple;
import std.utf : byCodeUnit;

import virc.casemapping;
import virc.common;
import virc.modes;
public import virc.numerics.definitions;
public import virc.numerics.isupport;
import virc.usermask;


/++
+ 004 RPL_MYINFO response.
+/
struct MyInfo {
	///
	string name;
	///
	string version_;
	///
	string userModes;
	///
	string userModesWithParams;
	///
	string channelModes;
	///
	string channelModesWithParams;
	///
	string serverModes;
	///
	string serverModesWithParams;
}
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
		numOpers = ops.to!ulong;
		message = msg;
	}
}
/++
+
+/
auto parseNumeric(Numeric numeric)() if (numeric.among(noInformationNumerics)) {
	static assert(0, "Cannot parse "~numeric~": No information to parse.");
}
//004 <username> <server_name> <version> <user_modes> <chan_modes> [<channel_modes_with_params> <user_modes_with_params> <server_modes> <server_modes_with_params>]
auto parseNumeric(Numeric numeric : Numeric.RPL_MYINFO, T)(T input) {
	MyInfo server;
	input.popFront();
	server.name = input.front;
	input.popFront();
	server.version_ = input.front;
	input.popFront();
	server.userModes = input.front;
	input.popFront();
	server.channelModes = input.front;
	input.popFront();
	if (!input.empty) {
		server.channelModesWithParams = input.front;
		input.popFront();
	}
	if (!input.empty) {
		server.userModesWithParams = input.front;
		input.popFront();
	}
	if (!input.empty) {
		server.serverModes = input.front;
		input.popFront();
	}
	if (!input.empty) {
		server.serverModesWithParams = input.front;
		input.popFront();
	}
	return server;
}
///
@safe pure nothrow @nogc unittest { //Numeric.RPL_MYINFO
	import std.range : only;
	{
		immutable info = parseNumeric!(Numeric.RPL_MYINFO)(only("someone", "localhost", "IRCd-2.0", "BGHIRSWcdgikorswx", "ABCDFGIJKLMNOPQRSTYabcefghijklmnopqrstuvz", "FIJLYabefghjkloqv"));
		assert(info.name == "localhost");
		assert(info.version_ == "IRCd-2.0");
		assert(info.userModes == "BGHIRSWcdgikorswx");
		assert(info.userModesWithParams == "");
		assert(info.channelModes == "ABCDFGIJKLMNOPQRSTYabcefghijklmnopqrstuvz");
		assert(info.channelModesWithParams == "FIJLYabefghjkloqv");
		assert(info.serverModes == "");
		assert(info.serverModesWithParams == "");
	}
}

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
//322 <username> <channel> <count> :[\[<modes\] ]<topic>
auto parseNumeric(Numeric numeric : Numeric.RPL_LIST, T)(T input, ModeType[char] channelModeTypes) {
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

//600 <nickname> <username> <hostname> <signontime> :logged on
//601 <nickname> <username> <hostname> <lastnickchange> :logged off
//602 <nickname> <username> <hostname> <lastnickchange> :stopped watching
//604 <nickname> <username> <hostname> <lastnickchange> :is online
//605 <nickname> <username> <hostname> <lastnickchange> :is offline
//609 <nickname> <username> <hostname> <awaysince> :is away
auto parseNumeric(Numeric numeric, T)(T input) if (numeric.among(Numeric.RPL_LOGON, Numeric.RPL_LOGOFF, Numeric.RPL_WATCHOFF, Numeric.RPL_NOWOFF, Numeric.RPL_NOWON, Numeric.RPL_NOWISAWAY)) {
	import std.typecons : tuple;
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

//730 <nick> :target[!user@host][,target[!user@host]]*
auto parseNumeric(Numeric numeric : Numeric.RPL_MONONLINE, T)(T input) {
	input.popFront();
	auto split = input.front.splitter(",");
	return split.map!(x => { User user; user.mask = UserMask(x); return user; }());
}
///
@safe pure nothrow @nogc unittest { //Numeric.RPL_MONONLINE
	import std.range : only;
	{
		auto logon = parseNumeric!(Numeric.RPL_MONONLINE)(only("test", "someone!someIdent@example.net"));
		assert(logon.front.mask.nickname == "someone");
		assert(logon.front.mask.ident == "someIdent");
		assert(logon.front.mask.host == "example.net");
	}
	{
		auto logon = parseNumeric!(Numeric.RPL_MONONLINE)(only("test", "someone!someIdent@example.net,someone2!someOther@example.com"));
		assert(logon.front.mask.nickname == "someone");
		assert(logon.front.mask.ident == "someIdent");
		assert(logon.front.mask.host == "example.net");
		logon.popFront();
		assert(logon.front.mask.nickname == "someone2");
		assert(logon.front.mask.ident == "someOther");
		assert(logon.front.mask.host == "example.com");
	}
}

//731 <nick> :target[,target2]*
//732 <nick> :target[,target2]*
auto parseNumeric(Numeric numeric, T)(T input) if (numeric.among(Numeric.RPL_MONOFFLINE,Numeric.RPL_MONLIST)) {
	input.popFront();
	auto split = input.front.splitter(",");
	return split.map!(x => { User user; user.mask.nickname = x; return user; }());
}
///
@safe pure nothrow @nogc unittest { //Numeric.RPL_MONOFFLINE
	import std.range : only;
	{
		auto logoff = parseNumeric!(Numeric.RPL_MONONLINE)(only("test", "someone"));
		assert(logoff.front.mask.nickname == "someone");
		assert(logoff.front.mask.ident.isNull);
		assert(logoff.front.mask.host.isNull);
	}
	{
		auto logoff = parseNumeric!(Numeric.RPL_MONONLINE)(only("test", "someone,someone2"));
		assert(logoff.front.mask.nickname == "someone");
		assert(logoff.front.mask.ident.isNull);
		assert(logoff.front.mask.host.isNull);
		logoff.popFront();
		assert(logoff.front.mask.nickname == "someone2");
		assert(logoff.front.mask.ident.isNull);
		assert(logoff.front.mask.host.isNull);
	}
}

//734 <nick> <limit> <targets> :Monitor list is full.
auto parseNumeric(Numeric numeric : Numeric.ERR_MONLISTFULL, T)(T input) {
	input.popFront();
	auto limit = input.front.to!ulong;
	input.popFront();
	User user;
	user.mask.nickname = input.front;
	return Tuple!(ulong, "limit", User, "userAdded")(limit, user);
}
///
@safe pure /+nothrow @nogc+/ unittest { //Numeric.ERR_MONLISTFULL
	import std.range : only;
	auto test = parseNumeric!(Numeric.ERR_MONLISTFULL)(only("someone", "5", "someone2", "Monitor list is full."));
	assert(test.limit == 5);
	assert(test.userAdded.nickname == "someone2");
}

//333 <channel> <setter> <timestamp>
auto parseNumeric(Numeric numeric : Numeric.RPL_TOPICWHOTIME, T)(T input) {
	return "";
}
///
unittest {

}
//332 <channel> :<topic>
auto parseNumeric(Numeric numeric : Numeric.RPL_TOPIC, T)(T input) {
	return "";
}
///
unittest {

}

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