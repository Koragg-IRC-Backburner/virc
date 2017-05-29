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
template parseNumeric(Numeric numeric) {
	static if (numeric.among(noInformationNumerics)) {
		static assert(0, "Cannot parse "~numeric~": No information to parse.");
	}
	//004 <username> <server_name> <version> <user_modes> <chan_modes> [<channel_modes_with_params> <user_modes_with_params> <server_modes> <server_modes_with_params>]
	static if (numeric == Numeric.RPL_MYINFO) {
		auto parseNumeric(T)(T input) {
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
	}
	static if (numeric == Numeric.RPL_ISUPPORT) {
		void parseNumeric(T)(T input, ref ISupport iSupport) {
			immutable username = input.front;
			input.popFront();
			while (!input.empty && !input.isColonParameter) {
				auto token = input.front;
				immutable isDisabled = token.skipOver('-');
				auto splitParams = token.findSplit("=");
				Nullable!string param;
				if (!isDisabled) {
					param = splitParams[2];
				}
				iSupport.insertToken(splitParams[0], param);
				input.popFront();
			}
		}
		auto parseNumeric(T)(T input) {
			ISupport tmp;
			parseNumeric(input, tmp);
			return tmp;
		}
	}
	//251 :There are <users> users and <services> services on <servers> servers
	//TODO: Find out if this is safe to parse
	static if (numeric == Numeric.RPL_LUSERCLIENT) {
		auto parseNumeric(T)(T input) {
			return LUserClient(input.front);
		}
	}
	//252 <opers> :operator(s) online
	static if (numeric == Numeric.RPL_LUSEROP) {
		auto parseNumeric(T)(T input) {
			auto ops = input.front;
			input.popFront();
			auto msg = input.front;
			auto output = LUserOp(ops, msg);
			return output;
		}
	}
	//254 <channels> :channels formed
	static if (numeric == Numeric.RPL_LUSERCHANNELS) {
		auto parseNumeric(T)(T input) {
			auto chans = input.front;
			input.popFront();
			auto msg = input.front;
			auto output = LUserChannels(chans, msg);
			return output;
		}
	}
	//255 :I have <clients> clients and <servers> servers
	//TODO: Find out if this is safe to parse
	static if (numeric == Numeric.RPL_LUSERME) {
		auto parseNumeric(T)(T input) {
			return LUserMe(input.front);
		}
	}
	//322 <username> <channel> <count> :[\[<modes\] ]<topic>
	static if (numeric == Numeric.RPL_LIST) {
		auto parseNumeric(T)(T input, ModeType[char] channelModeTypes) {
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
	}
	//600 <nickname> <username> <hostname> <signontime> :logged on
	//601 <nickname> <username> <hostname> <lastnickchange> :logged off
	//602 <nickname> <username> <hostname> <lastnickchange> :stopped watching
	//604 <nickname> <username> <hostname> <lastnickchange> :is online
	//605 <nickname> <username> <hostname> <lastnickchange> :is offline
	//609 <nickname> <username> <hostname> <awaysince> :is away
	static if (numeric.among(Numeric.RPL_LOGON, Numeric.RPL_LOGOFF, Numeric.RPL_WATCHOFF, Numeric.RPL_NOWOFF, Numeric.RPL_NOWON, Numeric.RPL_NOWISAWAY)) {
		auto parseNumeric(T)(T input) {
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
	}
	//730 <nick> :target[!user@host][,target[!user@host]]*
	static if (numeric == Numeric.RPL_MONONLINE) {
		auto parseNumeric(T)(T input) {
			input.popFront();
			auto split = input.front.splitter(",");
			return split.map!(x => { User user; user.mask = UserMask(x); return user; }());
		}
	}
	//731 <nick> :target[,target2]*
	//732 <nick> :target[,target2]*
	static if (numeric.among(Numeric.RPL_MONOFFLINE,Numeric.RPL_MONLIST)) {
		auto parseNumeric(T)(T input) {
			input.popFront();
			auto split = input.front.splitter(",");
			return split.map!(x => { User user; user.mask.nickname = x; return user; }());
		}
	}
	//734 <nick> <limit> <targets> :Monitor list is full.
	static if (numeric == Numeric.ERR_MONLISTFULL) {
		auto parseNumeric(T)(T input) {
			input.popFront();
			auto limit = input.front.to!ulong;
			input.popFront();
			User user;
			user.mask.nickname = input.front;
			return Tuple!(ulong, "limit", User, "userAdded")(limit, user);
		}
	}
	//353 =/*/@ <channel> :<prefix[es]><usermask>[ <prefix[es]><usermask>...]
	static if (numeric == Numeric.RPL_NAMREPLY) {
		auto parseNumeric(T)(T input) {
			auto chanFlag = input.front;
			input.popFront();
			auto channel = input.front;
			return "";
		}
	}
	//332 <channel> :<topic>
	static if (numeric == Numeric.RPL_TOPIC) {
		auto parseNumeric(T)(T input) {
			return "";
		}
	}
	//333 <channel> <setter> <timestamp>
	static if (numeric == Numeric.RPL_TOPICWHOTIME) {
		auto parseNumeric(T)(T input) {
			return "";
		}
	}
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
///
@safe pure /+nothrow @nogc+/ unittest { //Numeric.RPL_ISUPPORT
	import std.exception : assertNotThrown, assertThrown;
	import virc.ircsplitter : IRCSplitter;
	{
		auto support = parseNumeric!(Numeric.RPL_ISUPPORT)(IRCSplitter("someone STATUSMSG=~&@%+ CHANLIMIT=#:2 CHANMODES=a,b,c,d CHANTYPES=# :are supported by this server"));
		assert(support.statusMessage == "~&@%+");
		assert(support.chanLimits == ['#': 2UL]);
		assert(support.channelTypes == "#");
		assert(support.channelModeTypes == ['a':ModeType.a, 'b':ModeType.b, 'c':ModeType.c, 'd':ModeType.d]);
		parseNumeric!(Numeric.RPL_ISUPPORT)(IRCSplitter("someone -STATUSMSG -CHANLIMIT -CHANMODES -CHANTYPES :are supported by this server"), support);
		assert(support.statusMessage == support.statusMessage.init);
		assert(support.chanLimits == support.chanLimits.init);
		assert(support.channelTypes == support.channelTypes.init);
		assert(support.channelModeTypes == support.channelModeTypes.init);
	}
	{
		auto support = parseNumeric!(Numeric.RPL_ISUPPORT)(IRCSplitter("someone SILENCE=4 :are supported by this server"));
		assert(support.silence == 4);
		parseNumeric!(Numeric.RPL_ISUPPORT)(IRCSplitter("someone SILENCE :are supported by this server"), support);
		assert(support.silence.isNull);
		parseNumeric!(Numeric.RPL_ISUPPORT)(IRCSplitter("someone SILENCE=6 :are supported by this server"), support);
		parseNumeric!(Numeric.RPL_ISUPPORT)(IRCSplitter("someone -SILENCE :are supported by this server"), support);
		assert(support.silence.isNull);
	}
	{
		assertNotThrown(parseNumeric!(Numeric.RPL_ISUPPORT)(IRCSplitter("someone :are supported by this server")));
	}
	{
		assertThrown(parseNumeric!(Numeric.RPL_ISUPPORT)(IRCSplitter("someone WHATISTHIS :are supported by this server")));
	}
}
///
@safe pure /+nothrow @nogc+/ unittest { //Numeric.RPL_LUSERCLIENT
	import std.range : only;
	{
		immutable luser = parseNumeric!(Numeric.RPL_LUSERCLIENT)(only("There are 42 users and 43 services on 44 servers"));
		assert(luser.message == "There are 42 users and 43 services on 44 servers");
	}
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
///
@safe pure /+nothrow @nogc+/ unittest { //Numeric.RPL_LUSERCHANNELS
	import std.range : only;
	{
		immutable luser = parseNumeric!(Numeric.RPL_LUSERCHANNELS)(only("46", "channels formed"));
		assert(luser.numChans == 46);
		assert(luser.message == "channels formed");
	}
}
///
@safe pure /+nothrow @nogc+/ unittest { //Numeric.RPL_LUSERME
	import std.range : only;
	{
		immutable luser = parseNumeric!(Numeric.RPL_LUSERME)(only("I have 47 clients and 48 servers"));
		assert(luser.message == "I have 47 clients and 48 servers");
	}
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
///
@safe pure /+nothrow @nogc+/ unittest { //Numeric.ERR_MONLISTFULL
	import std.range : only;
	auto test = parseNumeric!(Numeric.ERR_MONLISTFULL)(only("someone", "5", "someone2", "Monitor list is full."));
	assert(test.limit == 5);
	assert(test.userAdded.nickname == "someone2");
}