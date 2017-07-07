/++
+ Module containing IRC client guts. Parses and dispatches to appropriate
+ handlers/
+/
module virc.client;
import std.algorithm.comparison : among;
import std.algorithm.iteration : chunkBy, cumulativeFold, filter, map, splitter;
import std.algorithm.searching : canFind, endsWith, find, findSplit, findSplitAfter, findSplitBefore, skipOver, startsWith;
import std.array : array;
import std.ascii : isDigit;
import std.conv : parse, text;
import std.datetime;
import std.exception : enforce;
import std.format : format, formattedWrite;
import std.meta : AliasSeq;
import std.range.primitives : ElementType, isInputRange, isOutputRange;
import std.range : chain, empty, front, put, walkLength;
import std.traits : Parameters, Unqual;
import std.typecons : Nullable;
import std.utf : byCodeUnit;

import virc.common;
import virc.encoding;
import virc.internaladdresslist;
import virc.ircsplitter;
import virc.modes;
import virc.numerics;
import virc.tags;
import virc.usermask;

/++
+
+/
struct NickInfo {
	///
	string nickname;
	///
	string username;
	///
	string realname;
}

/++
+
+/
immutable char[char] defaultPrefixes;
static this() {
	defaultPrefixes = ['o': '@', 'v': '+'];
}
/++
+
+/
enum supportedCaps = AliasSeq!(
	"account-notify", // http://ircv3.net/specs/extensions/account-notify-3.1.html
	"account-tag", // http://ircv3.net/specs/extensions/account-tag-3.2.html
	"away-notify", // http://ircv3.net/specs/extensions/away-notify-3.1.html
	"cap-notify", // http://ircv3.net/specs/extensions/cap-notify-3.2.html
	"chghost", // http://ircv3.net/specs/extensions/chghost-3.2.html
	"echo-message", // http://ircv3.net/specs/extensions/echo-message-3.2.html
	"extended-join", // http://ircv3.net/specs/extensions/extended-join-3.1.html
	"invite-notify", // http://ircv3.net/specs/extensions/invite-notify-3.2.html
	"metadata", // http://ircv3.net/specs/core/metadata-3.2.html
	"monitor", // http://ircv3.net/specs/core/monitor-3.2.html
	"multi-prefix", // http://ircv3.net/specs/extensions/multi-prefix-3.1.html
	"server-time", // http://ircv3.net/specs/extensions/server-time-3.2.html
	"userhost-in-names", // http://ircv3.net/specs/extensions/userhost-in-names-3.2.html
);

/++
+
+/
auto ircClient(alias mix, T)(ref T output, NickInfo info, string password = string.init) {
	auto client = IRCClient!(mix, T)(output);
	client.username = info.username;
	client.realname = info.realname;
	client.nickname = info.nickname;
	if (password != string.init) {
		client.password = password;
	}
	client.initialize();
	return client;
}
auto ircClient(T)(ref T output, NickInfo info, string password = string.init) {
	return ircClient!null(output, info, password);
}
/++
+
+/
struct MessageMetadata {
	///
	SysTime time;
	///
	string[string] tags;
	///
	Nullable!Numeric messageNumeric;
	///
	string original;
}
/++
+
+/
enum MessageType {
	notice,
	privmsg
}
/++
+ An IRC message, passed between clients.
+/
struct Message {
	///This message's payload. Will include \x01 characters if the message is CTCP.
	string msg;

	/++
	+ Type of message.
	+
	+ NOTICE and PRIVMSG are identical, but replying to a NOTICE
	+ is discouraged.
	+/
	MessageType type;

	///Whether or not the message was the result of the server echoing back our messages.
	bool isEcho;

	/++
	+ Whether or not the message was a CTCP message.
	+
	+ Note that some clients may mangle long CTCP messages by truncation. Those
	+ messages will not be detected as CTCP messages.
	+/
	auto isCTCP() const {
		return (msg.startsWith("\x01")) && (msg.endsWith("\x01"));
	}
	///Whether or not the message is safe to reply to.
	auto isReplyable() const {
		return type != MessageType.notice;
	}
	///The CTCP command, if this is a CTCP message.
	auto ctcpCommand() const in {
		assert(isCTCP, "This is not a CTCP message!");
	} body {
		auto split = msg[1..$-1].splitter(" ");
		return split.front;
	}
	///The arguments after the CTCP command, if this is a CTCP message.
	auto ctcpArgs() const in {
		assert(isCTCP, "This is not a CTCP message!");
	} body {
		return msg.find(" ")[1..$-1];
	}
	bool opEquals(string str) @safe pure nothrow @nogc const {
		return str == msg;
	}
	string toString() @safe pure nothrow @nogc const {
		return msg;
	}
}
///
@safe pure nothrow @nogc unittest {
	{
		auto msg = Message("Hello!", MessageType.notice);
		assert(!msg.isCTCP);
		assert(!msg.isReplyable);
	}
	{
		auto msg = Message("Hello!", MessageType.privmsg);
		assert(msg.isReplyable);
	}
	{
		auto msg = Message("\x01ACTION does a thing\x01", MessageType.privmsg);
		assert(msg.isCTCP);
		assert(msg.ctcpCommand == "ACTION");
		assert(msg.ctcpArgs == "does a thing");
	}
}
/++
+
+/
struct Server {
	///
	MyInfo myInfo;
	///
	ISupport iSupport;
}
/++
+
+/
struct Target {
	///
	Nullable!Channel channel;
	///
	Nullable!User user;
	///
	bool isChannel() @safe pure nothrow @nogc const {
		return !channel.isNull;
	}
	///
	bool isNickname() @safe pure nothrow @nogc const {
		return !user.isNull;
	}
	bool opEquals(string target) @safe pure nothrow @nogc const {
		if (!channel.isNull) {
			return channel.get == Channel(target);
		} else if (!user.isNull) {
			return user.get == User(target);
		}
		return false;
	}
	bool opEquals(const User target) @safe pure nothrow @nogc const {
		if (!user.isNull) {
			return user.get == target;
		}
		return false;
	}
	bool opEquals(const Channel target) @safe pure nothrow @nogc const {
		if (!channel.isNull) {
			return channel.get == target;
		}
		return false;
	}
	void toString(T)(T sink) const if (isOutputRange!(T, const(char))) {
		if (!channel.isNull) {
			channel.get.toString(sink);
		} else if (!user.isNull) {
			user.get.toString(sink);
		}
	}
}
unittest {
	{
		Target target;
		target.channel = Channel("#hello");
		assert(target == Channel("#hello"));
		assert(target != User("test"));
		assert(target == "#hello");
	}
	{
		Target target;
		target.user = User("test");
		assert(target != Channel("#hello"));
		assert(target == User("test"));
		assert(target == "test");
	}
	{
		Target target;
		assert(target != Channel("#hello"));
		assert(target != User("test"));
		assert(target != "test");
		assert(target != "#hello");
	}
}
/++
+
+/
enum RFC1459Commands {
	privmsg = "PRIVMSG",
	notice = "NOTICE",
	info = "INFO",
	admin = "ADMIN",
	trace = "TRACE",
	connect = "CONNECT",
	time = "TIME",
	links = "LINKS",
	stats = "STATS",
	version_ = "VERSION",
	kick = "KICK",
	invite = "INVITE",
	list = "LIST",
	names = "NAMES",
	topic = "TOPIC",
	mode = "MODE",
	part = "PART",
	join = "JOIN",
	squit = "SQUIT",
	quit = "QUIT",
	oper = "OPER",
	server = "SERVER",
	user = "USER",
	nick = "NICK",
	pass = "PASS",
	who = "WHO",
	whois = "WHOIS",
	whowas = "WHOWAS",
	kill = "KILL",
	ping = "PING",
	pong = "PONG",
	error = "ERROR",
	away = "AWAY",
	rehash = "REHASH",
	restart = "RESTART",
	summon = "SUMMON",
	users = "USERS",
	wallops = "WALLOPS",
	userhost = "USERHOST",
	ison = "ISON",
}
/++
+
+/
enum RFC2812Commands {
	service = "SERVICE"
}
private struct IRCClient(alias mix, T) if (isOutputRange!(T, char)) {
	import virc.ircv3 : Capability, CapabilityServerSubcommands, IRCV3Commands;
	T output;
	Server server;
	Capability[] capsEnabled;
	string username;
	string nickname;
	string realname;
	Nullable!string password;

	InternalAddressList internalAddressList;

	static if (!__traits(isTemplate, mix)) {
		void delegate(const Capability, const MessageMetadata) @safe onReceiveCapList;
		void delegate(const Capability, const MessageMetadata) @safe onReceiveCapLS;
		void delegate(const Capability, const MessageMetadata) @safe onReceiveCapAck;
		void delegate(const Capability, const MessageMetadata) @safe onReceiveCapNak;
		void delegate(const Capability, const MessageMetadata) @safe onReceiveCapDel;
		void delegate(const Capability, const MessageMetadata) @safe onReceiveCapNew;
		void delegate(const User, const SysTime, const MessageMetadata) @safe onUserOnline;
		void delegate(const User, const MessageMetadata) @safe onUserOffline;
		void delegate(const User, const MessageMetadata) @safe onLogin;
		void delegate(const User, const MessageMetadata) @safe onLogout;
		void delegate(const User, const string, const MessageMetadata) @safe onAway;
		void delegate(const User, const MessageMetadata) @safe onBack;
		void delegate(const User, const MessageMetadata) @safe onMonitorList;
		void delegate(const User, const string, const MessageMetadata) @safe onNick;
		void delegate(const User, const Channel, const MessageMetadata) @safe onJoin;
		void delegate(const User, const Channel, const string msg, const MessageMetadata) @safe onPart;
		void delegate(const User, const Channel, const User, const string msg, const MessageMetadata) @safe onKick;
		void delegate(const User, const string msg, const MessageMetadata) @safe onQuit;
		void delegate(const User, const Channel, const MessageMetadata) @safe onTopic;
		void delegate(const User, const Target, const ModeChange mode, const MessageMetadata) @safe onMode;
		void delegate(const User, const Target, const Message, const MessageMetadata) @safe onMessage;
		void delegate(const Channel, const MessageMetadata) @safe onList;
		void delegate(const User, const User, const MessageMetadata) @safe onChgHost;
		void delegate(const LUserClient, const MessageMetadata) @safe onLUserClient;
		void delegate(const LUserOp, const MessageMetadata) @safe onLUserOp;
		void delegate(const LUserChannels, const MessageMetadata) @safe onLUserChannels;
		void delegate(const LUserMe, const MessageMetadata) @safe onLUserMe;
		void delegate(const NamesReply, const MessageMetadata) @safe onNamesReply;
		void delegate(const TopicReply, const MessageMetadata) @safe onTopicReply;
		void delegate(const TopicWhoTime, const MessageMetadata) @safe onTopicWhoTimeReply;
		void delegate(const MessageMetadata) @safe onError;
		void delegate(const MessageMetadata) @safe onRaw;
		void delegate() @safe onConnect;
		debug void delegate(const string) @safe onSend;
	} else {
		mixin mix;
	}


	private bool invalid = true;
	private bool isRegistered;
	private ulong capReqCount = 0;

	void initialize() {
		invalid = false;
		write("CAP LS 302");
		register();
	}
	public void ping() {

	}
	public void names() {
		write("NAMES");
	}
	public void ping(string nonce) {
		write!"PING :%s"(nonce);
	}
	public void lUsers() {
		write!"LUSERS";
	}
	private void pong(string nonce) {
		write!"PONG :%s"(nonce);
	}
	public void put(string line) {
		//Chops off terminating \r\n. Everything after is ignored, according to spec.
		line = findSplitBefore(line, "\r\n")[0];
		debug(verboseirc) import std.stdio : writeln;
		debug(verboseirc) writeln("I: ", line);
		assert(!invalid);
		if (line.empty) {
			return;
		}
		auto tagSplit = line.splitTag;
		line = tagSplit.msg;
		Nullable!User source;
		if (line.front == ':') {
			auto found = line.findSplit(" ");
			source = User();
			source.mask = UserMask(found[0][1..$]);
			line = found[2];
		}
		auto split = IRCSplitter(line);
		auto metadata = MessageMetadata();
		metadata.tags = tagSplit.tags;
		if("time" in tagSplit.tags) {
			metadata.time = parseTime(tagSplit.tags);
		} else {
			metadata.time = Clock.currTime(UTC());
		}
		if ("account" in tagSplit.tags) {
			if (!source.isNull) {
				source.account = tagSplit.tags["account"];
			}
		}
		if (!source.isNull) {
			internalAddressList.update(source);
			if (source.nickname in internalAddressList) {
				source = internalAddressList[source.nickname];
			}
		}

		if (split.front.filter!(x => !isDigit(x)).empty) {
			metadata.messageNumeric = cast(Numeric)split.front;
		}
		metadata.original = line;
		tryCall!"onRaw"(metadata);

		auto firstToken = split.front;
		split.popFront();
		switch (firstToken) {
			case IRCV3Commands.cap:
				recCap(split, metadata);
				break;
			case RFC1459Commands.join:
				Channel channel;
				channel.name = split.front;
				split.popFront();
				if (isEnabled(Capability("extended-join"))) {
					if (split.front != "*") {
						source.account = split.front;
					}
					split.popFront();
					source.realName = split.front;
					split.popFront();
				}
				recJoin(source, channel, metadata);
				break;
			case RFC1459Commands.part:
				Channel channel;
				channel.name = split.front;
				split.popFront();
				auto msg = split.front;
				recPart(source, channel, msg, metadata);
				break;
			case RFC1459Commands.ping:
				recPing(split.front, metadata);
				break;
			case RFC1459Commands.notice:
				Target target = parseTarget(split.front);
				split.popFront();
				auto message = Message(split.front, MessageType.notice);
				recNotice(source, target, message, metadata);
				break;
			case RFC1459Commands.privmsg:
				Target target = parseTarget(split.front);
				split.popFront();
				auto message = Message(split.front, MessageType.privmsg);
				recPrivmsg(source, target, message, metadata);
				break;
			case RFC1459Commands.mode:
				Target target = parseTarget(split.front);
				split.popFront();
				auto modes = parseModeString(split, server.iSupport.channelModeTypes);
				recMode(source, target, modes, metadata);
				break;
			case IRCV3Commands.chghost:
				User target;
				target.mask.nickname = source.nickname;
				target.mask.ident = split.front;
				split.popFront();
				target.mask.host = split.front;
				recChgHost(source, target, metadata);
				break;
			case Numeric.RPL_WELCOME:
				isRegistered = true;
				tryCall!"onConnect"();
				break;
			case Numeric.RPL_ISUPPORT:
				switch (split.save().canFind("UHNAMES", "NAMESX")) {
					case 1:
						if (!isEnabled(Capability("userhost-in-names"))) {
							write("PROTOCTL UHNAMES");
						}
						break;
					case 2:
						if (!isEnabled(Capability("multi-prefix"))) {
							write("PROTOCTL NAMESX");
						}
						break;
					default: break;
				}
				parseNumeric!(Numeric.RPL_ISUPPORT)(split, server.iSupport);
				break;
			case Numeric.RPL_LIST:
				auto channel = parseNumeric!(Numeric.RPL_LIST)(split, server.iSupport.channelModeTypes);
				recList(channel, metadata);
				break;
			case Numeric.RPL_YOURHOST, Numeric.RPL_CREATED, Numeric.RPL_LISTSTART, Numeric.RPL_LISTEND, Numeric.RPL_ENDOFMONLIST, Numeric.RPL_ENDOFNAMES, Numeric.RPL_YOURID, Numeric.RPL_LOCALUSERS, Numeric.RPL_GLOBALUSERS, Numeric.RPL_HOSTHIDDEN, Numeric.RPL_TEXT:
				break;
			case Numeric.RPL_MYINFO:
				server.myInfo = parseNumeric!(Numeric.RPL_MYINFO)(split);
				break;
			case Numeric.RPL_LOGON:
				auto reply = parseNumeric!(Numeric.RPL_LOGON)(split);
				recLogon(reply.user, reply.timeOccurred, metadata);
				break;
			case Numeric.RPL_MONONLINE:
				auto user = parseNumeric!(Numeric.RPL_MONONLINE)(split);
				recMonitorOnline(user, metadata);
				break;
			case Numeric.RPL_MONOFFLINE:
				auto user = parseNumeric!(Numeric.RPL_MONOFFLINE)(split);
				recMonitorOffline(user, metadata);
				break;
			case Numeric.RPL_MONLIST:
				auto user = parseNumeric!(Numeric.RPL_MONLIST)(split);
				recMonitorList(user, metadata);
				break;
			case Numeric.ERR_MONLISTFULL:
				recMonListFull(parseNumeric!(Numeric.ERR_MONLISTFULL)(split), metadata);
				break;
			case Numeric.ERR_NOMOTD:
				tryCall!"onError"(metadata);
				break;
			case Numeric.RPL_LUSERCLIENT:
				tryCall!"onLUserClient"(parseNumeric!(Numeric.RPL_LUSERCLIENT)(split), metadata);
				break;
			case Numeric.RPL_LUSEROP:
				tryCall!"onLUserOp"(parseNumeric!(Numeric.RPL_LUSEROP)(split), metadata);
				break;
			case Numeric.RPL_LUSERCHANNELS:
				tryCall!"onLUserChannels"(parseNumeric!(Numeric.RPL_LUSERCHANNELS)(split), metadata);
				break;
			case Numeric.RPL_LUSERME:
				tryCall!"onLUserMe"(parseNumeric!(Numeric.RPL_LUSERME)(split), metadata);
				break;
			case Numeric.RPL_TOPIC:
				auto reply = parseNumeric!(Numeric.RPL_TOPIC)(split);
				if (!reply.isNull) {
					recTopic(reply.get, metadata);
				}
				break;
			case Numeric.RPL_NAMREPLY:
				auto reply = parseNumeric!(Numeric.RPL_NAMREPLY)(split);
				if (!reply.isNull) {
					recRPLNamReply(reply.get, metadata);
				}
				break;
			case Numeric.RPL_TOPICWHOTIME:
				auto reply = parseNumeric!(Numeric.RPL_TOPICWHOTIME)(split);
				if (!reply.isNull) {
					recRPLTopicWhoTime(reply.get, metadata);
				}
				break;
			default: recUnknownCommand(firstToken, metadata); break;
		}
	}
	void put(immutable(ubyte)[] rawString) {
		put(rawString.toUTF8String);
	}
	private void recCap(T)(T tokens, MessageMetadata metadata) if (isInputRange!T && is(ElementType!T == string)) {
		immutable username = tokens.front; //Unused?
		tokens.popFront();
		immutable subCommand = tokens.front;
		tokens.popFront();
		immutable terminator = !tokens.skipOver("*");
		auto args = tokens
			.front
			.splitter(" ")
			.map!(x => Capability(x));
		final switch (cast(CapabilityServerSubcommands) subCommand) {
			case CapabilityServerSubcommands.ls:
				recCapLS(args, metadata);
				break;
			case CapabilityServerSubcommands.list:
				recCapList(args, metadata);
				break;
			case CapabilityServerSubcommands.acknowledge:
				recCapAck(args, metadata);
				break;
			case CapabilityServerSubcommands.notAcknowledge:
				recCapNak(args, metadata);
				break;
			case CapabilityServerSubcommands.new_:
				recCapNew(args, metadata);
				break;
			case CapabilityServerSubcommands.delete_:
				recCapDel(args, metadata);
				break;
		}
	}
	private void recCapLS(T)(T caps, const MessageMetadata metadata) if (is(ElementType!T == Capability)) {
		auto requestCaps = caps.filter!(among!supportedCaps);
		capReqCount += requestCaps.save().walkLength;
		if (!requestCaps.empty) {
			write!"CAP REQ :%-(%s %)"(requestCaps);
		}
		foreach (ref cap; caps) {
			tryCall!"onReceiveCapLS"(cap, metadata);
		}
	}
	private void recCapList(T)(T caps, const MessageMetadata metadata) if (is(ElementType!T == Capability)) {
		foreach (ref cap; caps) {
			tryCall!"onReceiveCapList"(cap, metadata);
		}
	}
	private void recCapAck(T)(T caps, const MessageMetadata metadata) if (is(ElementType!T == Capability)) {
		import std.range : hasLength;
		capsEnabled ~= caps.save().array;
		foreach (ref cap; caps) {
			tryCall!"onReceiveCapAck"(cap, metadata);
			static if (!hasLength!T) {
				capAcknowledgementCommon(1);
			}
		}
		static if (hasLength!T) {
			capAcknowledgementCommon(caps.length);
		}
	}
	private void recCapNak(T)(T caps, const MessageMetadata metadata) if (is(ElementType!T == Capability)) {
		import std.range : hasLength;
		foreach (ref cap; caps) {
			tryCall!"onReceiveCapNak"(cap, metadata);
			static if (!hasLength!T) {
				capAcknowledgementCommon(1);
			}
		}
		static if (hasLength!T) {
			capAcknowledgementCommon(caps.length);
		}
	}
	private void capAcknowledgementCommon(size_t count) {
		capReqCount -= count;
		if (capReqCount == 0) {
			endRegistration();
		}
	}
	private void recCapNew(T)(T caps, const MessageMetadata metadata) if (is(ElementType!T == Capability)) {
		auto requestCaps = caps.filter!(among!supportedCaps);
		capReqCount += requestCaps.save().walkLength;
		if (!requestCaps.empty) {
			write!"CAP REQ :%-(%s %)"(requestCaps);
		}
		foreach (ref cap; caps) {
			tryCall!"onReceiveCapNew"(cap, metadata);
		}
	}
	private void recCapDel(T)(T caps, const MessageMetadata metadata) if (is(ElementType!T == Capability)) {
		import std.algorithm.mutation : remove;
		import std.algorithm.searching : countUntil;
		foreach (ref cap; caps) {
			auto findCap = countUntil(capsEnabled, cap);
			if (findCap > -1) {
				capsEnabled = capsEnabled.remove(findCap);
			}
			tryCall!"onReceiveCapDel"(cap, metadata);
		}
	}
	private void recMode(const User user, const Target channel, const typeof(parseModeString("",null)) modes, const MessageMetadata metadata) {
		foreach (mode; modes) {
			tryCall!"onMode"(user, channel, mode, metadata);
		}
	}
	private void recJoin(const User user, const Channel channel, const MessageMetadata metadata) {
		tryCall!"onJoin"(user, channel, metadata);
	}
	private void recPart(const User user, const Channel channel, const string msg, const MessageMetadata metadata) {
		tryCall!"onPart"(user, channel, msg, metadata);
	}
	private void recNotice(const User user, const Target target, const Message msg, const MessageMetadata metadata) {
		tryCall!"onMessage"(user, target, msg, metadata);
	}
	private void recPrivmsg(const User user, const Target target, const Message msg, const MessageMetadata metadata) {
		tryCall!"onMessage"(user, target, msg, metadata);
	}
	private void recList(const Channel channel, const MessageMetadata metadata) {
		tryCall!"onList"(channel, metadata);
	}
	private void recPing(const string pingStr, const MessageMetadata) {
		pong(pingStr);
	}
	private void recMonitorOnline(T)(T users, const MessageMetadata metadata) if (isInputRange!T && is(ElementType!T == User)) {
		foreach (user; users) {
			tryCall!"onUserOnline"(user, SysTime.init, metadata);
		}
	}
	private void recMonitorOffline(T)(T users, const MessageMetadata metadata) if (isInputRange!T && is(ElementType!T == User)) {
		foreach (user; users) {
			tryCall!"onUserOffline"(user, metadata);
		}
	}
	private void recMonitorList(T)(T users, const MessageMetadata metadata) if (isInputRange!T && is(ElementType!T == User)) {
		foreach (user; users) {
			tryCall!"onMonitorList"(user, metadata);
		}
	}
	private void recMonListFull(const typeof(parseNumeric!(Numeric.ERR_MONLISTFULL)([""])), const MessageMetadata metadata) {
		tryCall!"onError"(metadata);
	}
	private void recLogon(const User user, const SysTime timeOccurred, const MessageMetadata metadata) {
		tryCall!"onUserOnline"(user, timeOccurred, metadata);
	}
	private void recChgHost(const User user, const User target, const MessageMetadata metadata) {
		internalAddressList.update(target);
		tryCall!"onChgHost"(user, target, metadata);
	}
	private void recRPLTopicWhoTime(const TopicWhoTime twt, const MessageMetadata metadata) {
		tryCall!"onTopicWhoTimeReply"(twt, metadata);
	}
	private void recTopic(const TopicReply tr, const MessageMetadata metadata) {
		tryCall!"onTopicReply"(tr, metadata);
	}
	private void endRegistration() {
		write("CAP END");
	}
	public void capList() {
		write("CAP LIST");
	}
	public void list() {
		write("LIST");
	}
	public void monitorClear() {
		assert(monitorIsEnabled);
		write("MONITOR C");
	}
	public void monitorList() {
		assert(monitorIsEnabled);
		write("MONITOR L");
	}
	public void monitorStatus() {
		assert(monitorIsEnabled);
		write("MONITOR S");
	}
	public void monitorAdd(T)(T users) if (isInputRange!T && is(ElementType!T == User)) {
		assert(monitorIsEnabled);
		writeList!("MONITOR + ", ",")(users.map!(x => x.nickname));
	}
	public void monitorRemove(T)(T users) if (isInputRange!T && is(ElementType!T == User)) {
		assert(monitorIsEnabled);
		writeList!("MONITOR - ", ",")(users.map!(x => x.nickname));
	}
	public bool monitorIsEnabled() {
		return capsEnabled.canFind("MONITOR");
	}
	public void quit(const string msg) {
		write!"QUIT :%s"(msg);
		invalid = true;
	}
	public void changeNickname(const string nick) {
		write!"NICK %s"(nick);
	}
	public void join(T,U = void[])(T channel, U keys = U.init) if (isInputRange!T && isInputRange!U) in {
		assert(channels.filter!(x => server.iSupport.canFind(x.front)).empty, channel.front~": Not a channel type");
		assert(!channels.empty, "No channels specified");
	} body {
		if (!keys.empty) {
			write!"JOIN %-(%s,%) %-(%s,%)"(channels, keys);
		} else {
			write!"JOIN %-(%s,%)"(channels);
		}
	}
	public void join(string chan) {
		write!"JOIN %s"(chan);
	}
	public void msg(string target, string message) {
		write!"PRIVMSG %s :%s"(target, message);
	}
	public void msg(Target target, Message message) {
		msg(target.text, message.text);
	}
	public void notice(string target, string message) {
		write!"NOTICE %s :%s"(target, message);
	}
	public void notice(Target target, Message message) {
		notice(target.text, message.text);
	}
	private void recUnknownCommand(const string cmd, const MessageMetadata metadata) {
		debug(verboseirc) import std.stdio : writeln;
		if (cmd.filter!(x => !x.isDigit).empty) {
			recUnknownNumeric(cmd, metadata);
		} else {
			debug(verboseirc) writeln(metadata.time, " Unknown command - ", metadata.original);
		}
	}
	private void recRPLNamReply(const NamesReply x, const MessageMetadata metadata) {
		tryCall!"onNamesReply"(x, metadata);
	}
	private void recUnknownNumeric(const string cmd, const MessageMetadata metadata) {
		debug(verboseirc) import std.stdio : writeln;
		debug(verboseirc) writeln(metadata.time, " Unhandled numeric: ", cast(Numeric)cmd, " ", metadata.original);
	}
	private void register() {
		assert(!isRegistered);
		if (!password.isNull) {
			write!"PASS :%s"(password);
		}
		changeNickname(nickname);
		write!"USER %s 0 * :%s"(username, realname);
	}
	private void write(string fmt, T...)(T args) {
		import std.range : put;
		debug(verboseirc) import std.stdio : writefln;
		debug(verboseirc) writefln!("O: "~fmt)(args);
		formattedWrite!fmt(output, args);
		put(output, "\r\n");
		debug {
			tryCall!"onSend"(format!fmt(args));
		}
		static if (is(typeof(output.flush()))) {
			output.flush();
		}
	}
	private void write(T...)(const string fmt, T args) {
		debug(verboseirc) writefln("O: "~fmt, args);
		formattedWrite(output, fmt, args);
		std.range.put(output, "\r\n");
		debug {
			tryCall!"onSend"(format(fmt, args));
		}
		static if (is(typeof(output.flush()))) {
			output.flush();
		}
	}
	private void write(const string text) {
		write!"%s"(text);
	}
	private void writeList(string prefix, string separator, T)(T range) if (isInputRange!T && is(Unqual!(ElementType!T) == string)) {
		write!(prefix~"%-(%s"~separator~"%)")(range);
	}
	private bool isEnabled(const Capability cap) {
		return capsEnabled.canFind(cap);
	}
	void tryCall(string func, T...)(T params) {
		import std.traits : hasMember;
		static if (!__traits(isTemplate, mix)) {
			if (__traits(getMember, this, func) !is null) {
				__traits(getMember, this, func)(params);
			}
		} else static if(hasMember!(typeof(this), func)) {
			__traits(getMember, this, func)(params);
		}
	}
	private Target parseTarget(string str) {
		Target output;
		if (server.iSupport.channelTypes.canFind(str.front)) {
			output.channel = Channel(str);
		} else {
			output.user = User(str);
		}
		return output;
	}
}
version(unittest) {
	import std.algorithm : equal, sort, until;
	import std.array : appender, array;
	import std.range: drop, empty, tail;
	import std.stdio : writeln;
	import std.string : lineSplitter, representation;
	import std.typecons : Tuple, tuple;
	import virc.ircv3 : Capability;
	static immutable testUser = NickInfo("nick", "ident", "real name!");
	mixin template Test() {
		bool lineReceived;
		void onRaw(const MessageMetadata) @safe pure {
			lineReceived = true;
		}
	}
	void initialize(T)(ref T client) {
		client.put(":localhost 001 someone :Welcome to the TestNet IRC Network someone!test@::1");
		client.put(":localhost 002 someone :Your host is localhost, running version IRCd-2.0");
		client.put(":localhost 003 someone :This server was created 20:21:33 Oct  21 2016");
		client.put(":localhost 004 someone localhost IRCd-2.0 BGHIRSWcdgikorswx ABCDFGIJKLMNOPQRSTYabcefghijklmnopqrstuvz FIJLYabefghjkloqv");
		client.put(":localhost 005 someone AWAYLEN=200 CALLERID=g CASEMAPPING=rfc1459 CHANMODES=IYbeg,k,FJLfjl,ABCDGKMNOPQRSTcimnprstuz CHANNELLEN=31 CHANTYPES=# CHARSET=ascii ELIST=MU ESILENCE EXCEPTS=e EXTBAN=,ABCNOQRSTUcjmprsz FNC INVEX=I :are supported by this server");
		client.put(":localhost 005 someone KICKLEN=255 MAP MAXBANS=60 MAXCHANNELS=25 MAXPARA=32 MAXTARGETS=20 MODES=10 NAMESX NETWORK=TestNet NICKLEN=31 OPERLOG OVERRIDE PREFIX=(qaohv)~&@%+ :are supported by this server");
		client.put(":localhost 005 someone REMOVE SECURELIST SILENCE=32 SSL=[::]:6697 STARTTLS STATUSMSG=~&@%+ TOPICLEN=307 UHNAMES USERIP VBANLIST WALLCHOPS WALLVOICES WATCH=1000 :are supported by this server");
		assert(client.isRegistered);
		assert(client.server.iSupport.userhostsInNames == true);
	}
	void initializeCaps(T)(ref T client) {
		initializeWithCaps(client, [Capability("multi-prefix"), Capability("server-time"), Capability("sasl", false, false, false, "EXTERNAL")]);
	}
	void initializeWithCaps(T)(ref T client, Capability[] caps) {
		foreach (i, cap; caps) {
			client.put(":localhost CAP * LS " ~ ((i+1 == caps.length) ? "" : "* ")~ ":" ~ cap.toString);
			client.put(":localhost CAP * ACK :" ~ cap.name);
		}
		initialize(client);
	}
}
///Test the basics
@safe unittest {
	auto buffer = appender!string;
	auto client = ircClient!Test(buffer, testUser);
	client.put("");
	assert(client.lineReceived == false);
	client.put("\r\n");
	assert(client.lineReceived == false);
	client.put("hello");
	assert(client.lineReceived == true);
	assert(!client.isRegistered);
	client.put(":localhost 001 someone :words");
	assert(client.isRegistered);
	client.put(":localhost 001 someone :words");
	assert(client.isRegistered);
}
///Auto-decoding test
@system unittest {
	auto buffer = appender!string;
	auto client = ircClient!Test(buffer, testUser);
	client.put("\r\n".representation);
	assert(client.lineReceived == false);
}
///
@safe unittest {
	import virc.ircv3 : Capability;
	{ //password test
		auto buffer = appender!string;
		auto client = ircClient(buffer, testUser, "Example");

		assert(buffer.data.lineSplitter.until!(x => x.startsWith("USER")).canFind("PASS :Example"));
	}
	//Request capabilities (IRC v3.2)
	{
		auto buffer = appender!(string);
		auto client = ircClient(buffer, testUser);
		client.put(":localhost CAP * LS :multi-prefix sasl=EXTERNAL");
		client.put(":localhost CAP * ACK :multi-prefix");

		auto lineByLine = buffer.data.lineSplitter;

		assert(lineByLine.front == "CAP LS 302");
		lineByLine.popFront();
		lineByLine.popFront();
		lineByLine.popFront();
		//sasl not yet supported
		assert(lineByLine.front == "CAP REQ :multi-prefix");
		lineByLine.popFront();
		assert(!lineByLine.empty);
		assert(lineByLine.front == "CAP END");
	}
	//Request capabilities NAK (IRC v3.2)
	{
		auto buffer = appender!(string);
		auto client = ircClient(buffer, testUser);
		Capability[] capabilities;
		client.onReceiveCapNak = (const Capability cap, const MessageMetadata) {
			capabilities ~= cap;
		};
		client.put(":localhost CAP * LS :multi-prefix sasl=EXTERNAL");
		client.put(":localhost CAP * NAK :multi-prefix");


		auto lineByLine = buffer.data.lineSplitter;

		assert(lineByLine.front == "CAP LS 302");
		lineByLine.popFront();
		lineByLine.popFront();
		lineByLine.popFront();
		//sasl not yet supported
		assert(lineByLine.front == "CAP REQ :multi-prefix");
		lineByLine.popFront();
		assert(!lineByLine.empty);
		assert(lineByLine.front == "CAP END");

		assert(!client.capsEnabled.canFind("multi-prefix"));
		assert(capabilities.length == 1);
		assert(capabilities[0] == Capability("multi-prefix"));
	}
	//Request capabilities, multiline (IRC v3.2)
	{
		auto buffer = appender!(string);
		auto client = ircClient(buffer, testUser);
		auto lineByLine = buffer.data.lineSplitter();

		Capability[] capabilities;
		client.onReceiveCapLS = (const Capability cap, const MessageMetadata) {
			capabilities ~= cap;
		};

		assert(lineByLine.front == "CAP LS 302");

		put(client, ":localhost CAP * LS * :multi-prefix extended-join account-notify batch invite-notify tls");
		put(client, ":localhost CAP * LS * :cap-notify server-time example.org/dummy-cap=dummyvalue example.org/second-dummy-cap");
		put(client, ":localhost CAP * LS :userhost-in-names sasl=EXTERNAL,DH-AES,DH-BLOWFISH,ECDSA-NIST256P-CHALLENGE,PLAIN");
		assert(capabilities.length == 12);
		initialize(client);
	}
	//CAP LIST multiline (IRC v3.2)
	{
		auto buffer = appender!(string);
		auto client = ircClient(buffer, testUser);
		Capability[] capabilities;
		client.onReceiveCapList = (const Capability cap, const MessageMetadata) {
			capabilities ~= cap;
		};
		initialize(client);
		client.capList();
		client.put(":localhost CAP modernclient LIST * :example.org/example-cap example.org/second-example-cap account-notify");
		client.put(":localhost CAP modernclient LIST :invite-notify batch example.org/third-example-cap");
		assert(
			capabilities.array.sort().equal(
				[
					Capability("account-notify"),
					Capability("batch"),
					Capability("example.org/example-cap"),
					Capability("example.org/second-example-cap"),
					Capability("example.org/third-example-cap"),
					Capability("invite-notify")
				]
		));
	}
	//CAP NEW, DEL (IRCv3.2 - cap-notify)
	{
		auto buffer = appender!(string);
		auto client = ircClient(buffer, testUser);
		Capability[] capabilitiesNew;
		Capability[] capabilitiesDeleted;
		client.onReceiveCapNew = (const Capability cap, const MessageMetadata) {
			capabilitiesNew ~= cap;
		};
		client.onReceiveCapDel = (const Capability cap, const MessageMetadata) {
			capabilitiesDeleted ~= cap;
		};
		initializeWithCaps(client, [Capability("cap-notify"), Capability("userhost-in-names"), Capability("multi-prefix"), Capability("away-notify")]);

		assert(client.capsEnabled.length == 4);

		client.put(":irc.example.com CAP modernclient NEW :batch");
		assert(capabilitiesNew == [Capability("batch")]);
		client.put(":irc.example.com CAP modernclient ACK :batch");
		assert(
			client.capsEnabled.sort().equal(
				[
					Capability("away-notify"),
					Capability("batch"),
					Capability("cap-notify"),
					Capability("multi-prefix"),
					Capability("userhost-in-names")
				]
		));

		client.put(":irc.example.com CAP modernclient DEL :userhost-in-names multi-prefix away-notify");
		assert(
			capabilitiesDeleted.array.sort().equal(
				[
					Capability("away-notify"),
					Capability("multi-prefix"),
					Capability("userhost-in-names")
				]
		));
		assert(
			client.capsEnabled.sort().equal(
				[
					Capability("batch"),
					Capability("cap-notify")
				]
		));
		client.put(":irc.example.com CAP modernclient NEW :account-notify");
		auto lineByLine = buffer.data.lineSplitter();
		assert(lineByLine.array[$-1] == "CAP REQ :account-notify");
	}
	{ //JOIN
		auto buffer = appender!(string);
		auto client = ircClient(buffer, testUser);
		User[] users;
		const(Channel)[] channels;
		client.onJoin = (const User user, const Channel chan, const MessageMetadata) {
			users ~= user;
			channels ~= chan;
		};
		TopicWhoTime topicWhoTime;
		bool topicWhoTimeReceived;
		client.onTopicWhoTimeReply = (const TopicWhoTime twt, const MessageMetadata) {
			assert(!topicWhoTimeReceived);
			topicWhoTimeReceived = true;
			topicWhoTime = twt;
		};
		TopicReply topicReply;
		bool topicReplyReceived;
		client.onTopicReply = (const TopicReply tr, const MessageMetadata) {
			assert(!topicReplyReceived);
			topicReplyReceived = true;
			topicReply = tr;
		};
		initialize(client);
		client.join("#test");
		client.put(":someone!ident@hostmask JOIN :#test");
		client.put(":localhost 332 someone #test :a topic");
		client.put(":localhost 333 someone #test someoneElse :1496821983");
		client.put(":localhost 353 someone = #test :someone!ident@hostmask another!user@somewhere");
		client.put(":localhost 366 someone #test :End of /NAMES list.");
		client.put(":localhost 324 someone #test :+nt");
		client.put(":localhost 329 someone #test :1496821983");
		assert(users.length == 1);
		assert(users[0].nickname == "someone");
		assert(channels.length == 1);
		assert(channels[0].name == "#test");
		assert(topicWhoTimeReceived);
		assert(topicReplyReceived);

		with(topicReply) {
			assert(channel == "#test");
			assert(topic == "a topic");
		}

		with (topicWhoTime) {
			assert(channel == "#test");
			assert(setter == User("someoneElse"));
			assert(timestamp == SysTime(DateTime(2017, 06, 07, 07, 53, 03), UTC()));
		}
		//Add 366, 324, 329 tests
		auto lineByLine = buffer.data.lineSplitter();
		assert(lineByLine.array[$-1] == "JOIN #test");
	}
	{
		auto buffer = appender!(string);
		auto client = ircClient(buffer, testUser);
		const(Channel)[] channels;
		client.onList = (const Channel chan, const MessageMetadata) {
			channels ~= chan;
		};
		initialize(client);
		client.list();
		client.put("321 someone Channel :Users Name");
		client.put("322 someone #test 4 :[+fnt 200:2] some words");
		client.put("322 someone #test2 6 :[+fnst 100:2] some more words");
		client.put("322 someone #test3 1 :no modes?");
		client.put("323 someone :End of channel list.");
		assert(channels.length == 3);
		with(channels[0]) {
			assert(name == "#test");
			assert(userCount == 4);
			assert(topic == Topic("some words"));
		}
		with(channels[1]) {
			assert(name == "#test2");
			assert(userCount == 6);
			assert(topic == Topic("some more words"));
		}
		with(channels[2]) {
			assert(name == "#test3");
			assert(userCount == 1);
			assert(topic == Topic("no modes?"));
		}
	}
	{
		auto buffer = appender!(string);
		auto client = ircClient(buffer, testUser);
		User[] users;
		const(Channel)[] channels;
		client.onJoin = (const User user, const Channel chan, const MessageMetadata metadata) {
			users ~= user;
			channels ~= chan;
			assert(metadata.time == SysTime(DateTime(2012,06,30,23,59,59), 419.msecs, UTC()));
		};
		initialize(client);
		client.put("@time=2012-06-30T23:59:59.419Z :John!~john@1.2.3.4 JOIN #chan");
		assert(users.length == 1);
		assert(users[0].nickname == "John");
		assert(channels.length == 1);
		assert(channels[0].name == "#chan");
	}
	{
		auto buffer = appender!(string);
		auto client = ircClient(buffer, testUser);
		User[] users;
		const(MessageMetadata)[] metadata;
		client.onUserOnline = (const User user, const SysTime, const MessageMetadata) {
			users ~= user;
		};
		client.onUserOffline = (const User user, const MessageMetadata) {
			users ~= user;
		};
		client.onMonitorList = (const User user, const MessageMetadata) {
			users ~= user;
		};
		client.onError = (const MessageMetadata received) {
			metadata ~= received;
		};
		initialize(client);
		client.put(":localhost 730 someone :John!test@example.net,Bob!test2@example.com");
		assert(users.length == 2);
		with (users[0]) {
			assert(nickname == "John");
			assert(ident == "test");
			assert(host == "example.net");
		}
		with (users[1]) {
			assert(nickname == "Bob");
			assert(ident == "test2");
			assert(host == "example.com");
		}

		users.length = 0;

		client.put(":localhost 731 someone :John");
		assert(users.length == 1);
		assert(users[0].nickname == "John");

		users.length = 0;

		client.put(":localhost 732 someone :John,Bob");
		client.put(":localhost 733 someone :End of MONITOR list");
		assert(users.length == 2);
		assert(users[0].nickname == "John");
		assert(users[1].nickname == "Bob");

		client.put(":localhost 734 someone 5 Earl :Monitor list is full.");
		assert(metadata.length == 1);
		assert(metadata[0].messageNumeric == Numeric.ERR_MONLISTFULL);
	}
	{ //extended-join http://ircv3.net/specs/extensions/extended-join-3.1.html
		auto buffer = appender!(string);
		auto client = ircClient(buffer, testUser);


		User[] users;
		client.onJoin = (const User user, const Channel, const MessageMetadata) {
			users ~= user;
		};

		initializeWithCaps(client, [Capability("extended-join")]);

		client.put(":nick!user@host JOIN #channelname accountname :Real Name");
		auto user = User("nick!user@host");
		user.account = "accountname";
		user.realName = "Real Name";
		assert(users.front == user);

		user.account.nullify();
		users = [];
		client.put(":nick!user@host JOIN #channelname * :Real Name");
		assert(users.front == user);
	}
	{ //example taken from RFC2812, section 3.2.2
		auto buffer = appender!(string);
		auto client = ircClient(buffer, testUser);


		User[] users;
		const(Channel)[] channels;
		string lastMsg;
		client.onPart = (const User user, const Channel chan, const string msg, const MessageMetadata) {
			users ~= user;
			channels ~= chan;
			lastMsg = msg;
		};

		initialize(client);

		client.put(":WiZ!jto@tolsun.oulu.fi PART #playzone :I lost");
		immutable user = User("WiZ!jto@tolsun.oulu.fi");
		assert(users.front == user);
		assert(channels.front == Channel("#playzone"));
		assert(lastMsg == "I lost");
	}
	{ //http://ircv3.net/specs/extensions/chghost-3.2.html
		auto buffer = appender!(string);
		auto client = ircClient(buffer, testUser);


		User[] users;
		client.onChgHost = (const User user, const User newUser, const MessageMetadata) {
			users ~= user;
			users ~= newUser;
		};

		initialize(client);
		client.put(":nick!user@host JOIN #test");
		assert("nick" in client.internalAddressList);
		assert(client.internalAddressList["nick"] == User("nick!user@host"));
		client.put(":nick!user@host CHGHOST user new.host.goes.here");
		assert(users[0] == User("nick!user@host"));
		assert(users[1] == User("nick!user@new.host.goes.here"));
		assert(client.internalAddressList["nick"] == User("nick!user@new.host.goes.here"));
		client.put(":nick!user@host CHGHOST newuser host");
		assert(users[2] == User("nick!user@host"));
		assert(users[3] == User("nick!newuser@host"));
		assert(client.internalAddressList["nick"] == User("nick!newuser@host"));
		client.put(":nick!user@host CHGHOST newuser new.host.goes.here");
		assert(users[4] == User("nick!user@host"));
		assert(users[5] == User("nick!newuser@new.host.goes.here"));
		assert(client.internalAddressList["nick"] == User("nick!newuser@new.host.goes.here"));
		client.put(":tim!~toolshed@backyard CHGHOST b ckyard");
		assert(users[6] == User("tim!~toolshed@backyard"));
		assert(users[7] == User("tim!b@ckyard"));
		assert(client.internalAddressList["tim"] == User("tim!b@ckyard"));
		client.put(":tim!b@ckyard CHGHOST ~toolshed backyard");
		assert(users[8] == User("tim!b@ckyard"));
		assert(users[9] == User("tim!~toolshed@backyard"));
		assert(client.internalAddressList["tim"] == User("tim!~toolshed@backyard"));
	}
	{ //PING? PONG!
		auto buffer = appender!(string);
		auto client = ircClient(buffer, testUser);

		initialize(client);
		client.put("PING :words");
		auto lineByLine = buffer.data.lineSplitter();
		assert(lineByLine.array[$-1] == "PONG :words");
	}
}
@system unittest {
	{ //QUIT and invalidation check
		import core.exception : AssertError;
		import std.exception : assertThrown;
		auto buffer = appender!(string);
		auto client = ircClient(buffer, testUser);

		initialize(client);
		client.quit("I'm out");
		auto lineByLine = buffer.data.lineSplitter();
		assert(lineByLine.array[$-1] == "QUIT :I'm out");
		assert(client.invalid);
		assertThrown!AssertError(client.put("PING :hahahaha"));
	}
}
@safe unittest {
	{ //NAMES
		auto buffer = appender!(string);
		auto client = ircClient(buffer, testUser);
		NamesReply[] replies;
		client.onNamesReply = (const NamesReply reply, const MessageMetadata) {
			replies ~= reply;
		};

		initialize(client);

		client.names();
		client.put(":localhost 353 someone = #channel :User1 User2 @User3 +User4");
		client.put(":localhost 353 someone @ #channel2 :User5 User2 @User6 +User7");
		client.put(":localhost 353 someone * #channel3 :User1 User2 @User3 +User4");
		client.put(":localhost 366 someone :End of NAMES list");
		assert(replies.length == 3);
		assert(replies[0].chanFlag == NamReplyFlag.public_);
		assert(replies[1].chanFlag == NamReplyFlag.secret);
		assert(replies[2].chanFlag == NamReplyFlag.private_);
	}
	{ //WATCH stuff
		auto buffer = appender!string;
		auto client = ircClient(buffer, testUser);
		User[] users;
		SysTime[] times;
		client.onUserOnline = (const User user, const SysTime time, const MessageMetadata) {
			users ~= user;
			times ~= time;
		};
		initialize(client);
		client.put(":localhost 600 someone someoneElse someIdent example.net 911248013 :logged on");

		assert(users.length == 1);
		assert(users[0] == User("someoneElse!someIdent@example.net"));
		assert(times.length == 1);
		assert(times[0] == SysTime(DateTime(1998, 11, 16, 20, 26, 53), UTC()));
	}
	{ //LUSER stuff
		auto buffer = appender!string;
		auto client = ircClient(buffer, testUser);
		bool lUserMeReceived;
		bool lUserChannelsReceived;
		bool lUserOpReceived;
		bool lUserClientReceived;
		LUserMe lUserMe;
		LUserClient lUserClient;
		LUserOp lUserOp;
		LUserChannels lUserChannels;
		client.onLUserMe = (const LUserMe param, const MessageMetadata) {
			assert(!lUserMeReceived);
			lUserMeReceived = true;
			lUserMe = param;
		};
		client.onLUserChannels = (const LUserChannels param, const MessageMetadata) {
			assert(!lUserChannelsReceived);
			lUserChannelsReceived = true;
			lUserChannels = param;
		};
		client.onLUserOp = (const LUserOp param, const MessageMetadata) {
			assert(!lUserOpReceived);
			lUserOpReceived = true;
			lUserOp = param;
		};
		client.onLUserClient = (const LUserClient param, const MessageMetadata) {
			assert(!lUserClientReceived);
			lUserClientReceived = true;
			lUserClient = param;
		};
		initialize(client);
		client.lUsers();
		client.put(":localhost 251 someone :There are 8 users and 0 invisible on 2 servers");
		client.put(":localhost 252 someone 1 :operator(s) online");
		client.put(":localhost 254 someone 1 :channels formed");
		client.put(":localhost 255 someone :I have 1 clients and 1 servers");

		assert(lUserMeReceived);
		assert(lUserChannelsReceived);
		assert(lUserOpReceived);
		assert(lUserClientReceived);

		assert(lUserMe.message == "I have 1 clients and 1 servers");
		assert(lUserClient.message == "There are 8 users and 0 invisible on 2 servers");
		assert(lUserOp.numOperators == 1);
		assert(lUserOp.message == "operator(s) online");
		assert(lUserChannels.numChannels == 1);
		assert(lUserChannels.message == "channels formed");
	}
	{ //PRIVMSG and NOTICE stuff
		auto buffer = appender!string;
		auto client = ircClient(buffer, testUser);
		Tuple!(const User, "user", const Target, "target", const Message, "message")[] messages;
		client.onMessage = (const User user, const Target target, const Message msg, const MessageMetadata) {
			messages ~= tuple!("user", "target", "message")(user, target, msg);
		};

		initialize(client);

		client.put(":someoneElse!somebody@somewhere PRIVMSG someone :words go here");
		assert(messages.length == 1);
		with (messages[0]) {
			assert(user == User("someoneElse!somebody@somewhere"));
			assert(!target.isChannel);
			assert(target.isNickname);
			assert(target == User("someone"));
			assert(message == "words go here");
			assert(message.isReplyable);
		}
		client.put(":ohno!it's@me PRIVMSG #someplace :more words go here");
		assert(messages.length == 2);
		with (messages[1]) {
			assert(user == User("ohno!it's@me"));
			assert(target.isChannel);
			assert(!target.isNickname);
			assert(target == Channel("#someplace"));
			assert(message == "more words go here");
			assert(message.isReplyable);
		}

		client.put(":someoneElse2!somebody2@somewhere2 NOTICE someone :words don't go here");
		assert(messages.length == 3);
		with(messages[2]) {
			assert(user == User("someoneElse2!somebody2@somewhere2"));
			assert(!target.isChannel);
			assert(target.isNickname);
			assert(target == User("someone"));
			assert(message == "words don't go here");
			assert(!message.isReplyable);
		}

		client.put(":ohno2!it's2@me4 NOTICE #someplaceelse :more words might go here");
		assert(messages.length == 4);
		with(messages[3]) {
			assert(user == User("ohno2!it's2@me4"));
			assert(target.isChannel);
			assert(!target.isNickname);
			assert(target == Channel("#someplaceelse"));
			assert(message == "more words might go here");
			assert(!message.isReplyable);
		}

		client.put(":someoneElse2!somebody2@somewhere2 NOTICE someone :\x01ACTION did the thing\x01");
		assert(messages.length == 5);
		with(messages[4]) {
			assert(user == User("someoneElse2!somebody2@somewhere2"));
			assert(!target.isChannel);
			assert(target.isNickname);
			assert(target == User("someone"));
			assert(message.isCTCP);
			assert(message.ctcpArgs == "did the thing");
			assert(message.ctcpCommand == "ACTION");
			assert(!message.isReplyable);
		}

		client.put(":ohno2!it's2@me4 NOTICE #someplaceelse :\x01ACTION did not do the thing\x01");
		assert(messages.length == 6);
		with(messages[5]) {
			assert(user == User("ohno2!it's2@me4"));
			assert(target.isChannel);
			assert(!target.isNickname);
			assert(target == Channel("#someplaceelse"));
			assert(message.isCTCP);
			assert(message.ctcpArgs == "did not do the thing");
			assert(message.ctcpCommand == "ACTION");
			assert(!message.isReplyable);
		}

		client.msg("#channel", "ohai");
		client.notice("#channel", "ohi");
		client.msg("someoneElse", "ohay");
		client.notice("someoneElse", "ohello");
		Target channelTarget;
		channelTarget.channel = Channel("#channel");
		Target userTarget;
		userTarget.user = User("someoneElse");
		client.msg(channelTarget, Message("ohai"));
		client.notice(channelTarget, Message("ohi"));
		client.msg(userTarget, Message("ohay"));
		client.notice(userTarget, Message("ohello"));
		auto lineByLine = buffer.data.lineSplitter();
		foreach (i; 0..5) //skip the initial handshake
			lineByLine.popFront();
		assert(lineByLine.array == ["PRIVMSG #channel :ohai", "NOTICE #channel :ohi", "PRIVMSG someoneElse :ohay", "NOTICE someoneElse :ohello", "PRIVMSG #channel :ohai", "NOTICE #channel :ohi", "PRIVMSG someoneElse :ohay", "NOTICE someoneElse :ohello"]);
	}
	{ //PING? PONG!
		auto buffer = appender!(string);
		auto client = ircClient(buffer, testUser);

		initialize(client);
		client.ping("hooray");
		client.put(":localhost PONG localhost :hooray");
		auto lineByLine = buffer.data.lineSplitter();
		assert(lineByLine.array[$-1] == "PING :hooray");
	}
	{
		auto buffer = appender!(string);
		auto client = ircClient(buffer, testUser);
		Tuple!(const User, "user", const Target, "target", const ModeChange, "change")[] changes;

		client.onMode = (const User user, const Target target, const ModeChange mode, const MessageMetadata) {
			changes ~= tuple!("user", "target", "change")(user, target, mode);
		};

		initialize(client);
		client.put(":someone!ident@host JOIN #test");
		client.put(":someoneElse!user@host2 MODE #test +s");
		client.put(":someoneElse!user@host2 MODE #test -s");
		client.put(":someoneElse!user@host2 MODE #test +kp 2");
		client.put(":someoneElse!user@host2 MODE someone +r");

		assert(changes.length == 5);
		with (changes[0]) {
			assert(target == Channel("#test"));
			assert(user == User("someoneElse!user@host2"));
		}
		with (changes[1]) {
			assert(target == Channel("#test"));
			assert(user == User("someoneElse!user@host2"));
		}
		with (changes[2]) {
			assert(target == Channel("#test"));
			assert(user == User("someoneElse!user@host2"));

		}
		with (changes[3]) {
			assert(target == Channel("#test"));
			assert(user == User("someoneElse!user@host2"));

		}
		with (changes[4]) {
			assert(target == User("someone"));
			assert(user == User("someoneElse!user@host2"));

		}
	}
	{ //account-tag examples from http://ircv3.net/specs/extensions/account-tag-3.2.html
		auto buffer = appender!(string);
		auto client = ircClient(buffer, testUser);
		User[] privmsgUsers;
		client.onMessage = (const User user, const Target target, const Message msg, const MessageMetadata) {
			privmsgUsers ~= user;
		};
		initialize(client);

		client.put(":user PRIVMSG #atheme :Hello everyone.");
		client.put(":user ACCOUNT hax0r");
		client.put("@account=hax0r :user PRIVMSG #atheme :Now I'm logged in.");
		client.put("@account=hax0r :user ACCOUNT bob");
		client.put("@account=bob :user PRIVMSG #atheme :I switched accounts.");
		with(privmsgUsers[0]) {
			assert(account.isNull);
		}
		with(privmsgUsers[1]) {
			assert(account == "hax0r");
		}
		with(privmsgUsers[2]) {
			assert(account == "bob");
		}
	}
	{ //monitor - http://ircv3.net/specs/core/monitor-3.2.html
		auto buffer = appender!(string);
		auto client = ircClient(buffer, testUser);
		initializeWithCaps(client, [Capability("MONITOR")]);

		assert(client.monitorIsEnabled);

		client.monitorAdd([User("Someone")]);
		client.monitorRemove([User("Someone")]);
		client.monitorClear();
		client.monitorList();
		client.monitorStatus();

		auto lineByLine = buffer.data.lineSplitter().drop(5);
		assert(lineByLine.array == ["MONITOR + Someone", "MONITOR - Someone", "MONITOR C", "MONITOR L", "MONITOR S"]);
	}
	{
		auto buffer = appender!(string);
		auto client = ircClient(buffer, testUser);
		bool errorReceived;
		client.onError = (const MessageMetadata) {
			assert(!errorReceived);
			errorReceived = true;
		};
		initialize(client);
		client.put("422 someone :MOTD File is missing");
		assert(errorReceived);
	}
}