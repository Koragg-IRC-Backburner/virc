module virc.client;
import std.format : formattedWrite, format;
import std.range.primitives : isOutputRange, ElementType, isInputRange;
import std.range : put, empty, front, walkLength, chain;
import std.algorithm.iteration : splitter, filter, map, chunkBy, cumulativeFold;
import std.algorithm.searching : startsWith, canFind, skipOver, findSplit, findSplitAfter, endsWith, find, findSplitBefore;
import std.exception : enforce;
import std.algorithm.comparison : among;
import std.meta : AliasSeq;
import std.typecons : Nullable;
import std.array : array;
import std.conv : text, parse;
import std.datetime;
import std.traits : Parameters;
import std.ascii : isDigit;
import std.utf : byCodeUnit;
debug import std.stdio : writeln, writefln;

static import std.range;

import virc.common;
import virc.encoding;
import virc.internaladdresslist;
import virc.ircsplitter;
import virc.modes;
import virc.numerics;
import virc.tags;
import virc.usermask;

struct NickInfo {
	string nickname;
	string username;
	string realname;
}

enum defaultPrefixes = ['o': '@', 'v': '+'];

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

enum ISUPPORT {
	prefix,
	chantypes,
	chanmodes,
	modes,
	maxchannels,
	chanlimit,
	nicklen,
	maxbans,
	maxlist,
	network,
	excepts,
	invex,
	wallchops,
	wallvoices,
	statusmsg,
	casemapping,
	elist,
	topiclen,
	kicklen,
	channellen,
	chidlen,
	idchan,
	std,
	silence,
	rfc2812,
	penalty,
	fnc,
	safelist,
	awaylen,
	noquit,
	userip,
	cprivmsg,
	cnotice,
	maxnicklen,
	maxtargets,
	knock,
	vchans,
	watch,
	whox,
	callerid,
	accept,
	language
}

auto ircClient(T, alias mix = null)(ref T output, NickInfo info, Nullable!string password = Nullable!string.init) {
	auto client = IRCClient!(T, mix)(output);
	client.username = info.username;
	client.realname = info.realname;
	client.nickname = info.nickname;
	client.initialize();
	return client;
}

struct Capability {
	string name;
	bool isVendorSpecific;
	bool isSticky;
	bool isDisabled;
	bool isAcked;
	string value;

	alias name this;

	@disable this();

	this(string str) @safe pure @nogc {
		switch (str[0]) {
			case '~':
				isAcked = true;
				name = str[1..$];
				break;
			case '=':
				isSticky = true;
				name = str[1..$];
				break;
			case '-':
				isDisabled = true;
				name = str[1..$];
				break;
			default:
				name = str;
				break;
		}
		isVendorSpecific = name.byCodeUnit.canFind('/');
	}
	string toString() {
		return name~(value.empty ? "" : "=")~value;
	}
}
struct MessageMetadata {
	SysTime time;
	string[string] tags;
	Nullable!Numeric messageNumeric;
	string original;
	string toString() const @safe pure nothrow @nogc {
		return original;
	}
}
enum MessageType {
	notice,
	privmsg
}
struct Message {
	string msg;
	MessageType type;
	bool isCTCP() const pure @safe nothrow @nogc {
		return (msg.startsWith("\x01")) && (msg.endsWith("\x01"));
	}
	bool isNotice() const pure @safe nothrow @nogc {
		return type == MessageType.notice;
	}
	bool isPrivmsg() const pure @safe nothrow @nogc {
		return type == MessageType.privmsg;
	}
	string ctcpCommand() const pure @safe nothrow @nogc in {
		assert(isCTCP, "This is not a CTCP message!");
	} body {
		auto split = msg[1..$-1].splitter(" ");
		return split.front;
	}
	string ctcpArgs() const pure @safe nothrow @nogc in {
		assert(isCTCP, "This is not a CTCP message!");
	} body {
		return msg.find(" ")[1..$-1];
	}
}
struct Server {
	MyInfo myInfo;
	ISupport iSupport;
}
struct Target {
	Nullable!Channel channel;
	Nullable!User user;
	void toString(T)(T sink) const if (isOutputRange!(T, const(char))) {
		if (!channel.isNull) {
			channel.get.toString(sink);
		} else if (user.isNull) {
			user.get.toString(sink);
		}
	}
}
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
enum RFC2812Commands {
	service = "SERVICE"
}
enum IRCV3Commands {
	cap = "CAP",
	metadata = "METADATA",
	authenticate = "AUTHENTICATE",
	account = "ACCOUNT",
	starttls = "STARTTLS",
	monitor = "MONITOR",
	batch = "BATCH",
	chghost = "CHGHOST"
}
enum CapabilityServerSubcommands {
	ls = "LS",
	acknowledge = "ACK",
	notAcknowledge = "NAK",
	list = "LIST",
	new_ = "NEW",
	delete_ = "DEL"
}
enum CapabilityClientSubcommands {
	ls = "LS",
	list = "LIST",
	request = "REQ",
	end = "END"
}
private struct IRCClient(T, alias mix) if (isOutputRange!(T, char)) {
	T output;
	Server server;
	Capability[] capsEnabled;
	string username;
	string nickname;
	string realname;
	Nullable!string password;

	InternalAddressList internalAddressList;

	static if (!__traits(isTemplate, mix)) {
		void delegate(const Capability, const MessageMetadata) onReceiveCapList;
		void delegate(const Capability, const MessageMetadata) onReceiveCapLS;
		void delegate(const Capability, const MessageMetadata) onReceiveCapAck;
		void delegate(const Capability, const MessageMetadata) onReceiveCapNak;
		void delegate(const Capability, const MessageMetadata) onReceiveCapDel;
		void delegate(const Capability, const MessageMetadata) onReceiveCapNew;
		void delegate(const User, const MessageMetadata) onUserOnline;
		void delegate(const User, const MessageMetadata) onUserOffline;
		void delegate(const User, const MessageMetadata) onLogin;
		void delegate(const User, const MessageMetadata) onLogout;
		void delegate(const User, const string, const MessageMetadata) onAway;
		void delegate(const User, const MessageMetadata) onBack;
		void delegate(const User, const MessageMetadata) onMonitorList;
		void delegate(const User, const string, const MessageMetadata) onNick;
		void delegate(const User, const Channel, const MessageMetadata) onJoin;
		void delegate(const User, const Channel, const string msg, const MessageMetadata) onPart;
		void delegate(const User, const Channel, const User, const string msg, const MessageMetadata) onKick;
		void delegate(const User, const string msg, const MessageMetadata) onQuit;
		void delegate(const User, const Channel, const MessageMetadata) onTopic;
		void delegate(const User, const Target, const ModeChange mode, const MessageMetadata) onMode;
		void delegate(const User, const Target, const Message, const MessageMetadata) onMessage;
		void delegate(const Channel, const MessageMetadata) onList;
		void delegate(const User, const User, const MessageMetadata) onChgHost;
		void delegate(const LUserClient, const MessageMetadata) onLUserClient;
		void delegate(const LUserOp, const MessageMetadata) onLUserOp;
		void delegate(const LUserChannels, const MessageMetadata) onLUserChannels;
		void delegate(const LUserMe, const MessageMetadata) onLUserMe;
		void delegate(const MessageMetadata) onError;
		void delegate(const MessageMetadata) onRaw;
		void delegate() onConnect;
		debug void delegate(const string) onSend;
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
	public void ping(string nonce) {
		write!"PING :%s"(nonce);
	}
	private void pong(string nonce) {
		write!"PONG :%s"(nonce);
	}
	public void put(string line) {
		//Chops off terminating \r\n. Everything after is ignored, according to spec.
		line = findSplitBefore(line, "\r\n")[0];
		debug(verbose) writeln("I: ", line);
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
				User user = source;
				Channel channel;
				channel.name = split.front;
				split.popFront();
				if (isEnabled(Capability("extended-join"))) {
					if (split.front != "*") {
						user.account = split.front;
					}
					split.popFront();
					user.realName = split.front;
					split.popFront();
				}
				recJoin(user, channel, metadata);
				break;
			case RFC1459Commands.part:
				User user = source;
				Channel channel;
				channel.name = split.front;
				split.popFront();
				auto msg = split.front;
				recPart(user, channel, msg, metadata);
				break;
			case RFC1459Commands.ping:
				recPing(split.front, metadata);
				break;
			case RFC1459Commands.notice:
				User user = source;
				Target target;
				if (server.iSupport.channelTypes.canFind(split.front.front)) {
					target.channel = Channel(split.front);
				} else {
					target.user = User();
					target.user.mask = UserMask(split.front);
				}
				split.popFront();
				auto message = Message(split.front, MessageType.notice);
				recNotice(user, target, message, metadata);
				break;
			case RFC1459Commands.privmsg:
				User user = source;
				Target target;
				if (server.iSupport.channelTypes.canFind(split.front.front)) {
					target.channel = Channel(split.front);
				} else {
					target.user = User();
					target.user.mask = UserMask(split.front);
				}
				split.popFront();
				auto message = Message(split.front, MessageType.privmsg);
				recNotice(user, target, message, metadata);
				break;
			case RFC1459Commands.mode:
				Target target;
				if (server.iSupport.channelTypes.canFind(split.front.front)) {
					target.channel = Channel(split.front);
				} else {
					target.user = User();
					target.user.mask.nickname = split.front;
				}
				split.popFront();
				auto modes = parseModeString(split.front, server.iSupport.channelModeTypes);
				recMode(source, target, modes, metadata);
				break;
			case IRCV3Commands.chghost:
				User user = source;
				User target;
				target.mask.nickname = user.nickname;
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
				auto user = parseNumeric!(Numeric.RPL_LOGON)(split);
				recLogon(user, metadata);
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
				//auto channel = Channel(split.front);
				//split.popFront();
				//channel.topic = split.front;
				//recTopic(channel, metadata);
				break;
			case Numeric.RPL_NAMREPLY:
				auto reply = parseNumeric!(Numeric.RPL_NAMREPLY)(split);
				break;
			case Numeric.RPL_TOPICWHOTIME:
				auto reply = parseNumeric!(Numeric.RPL_TOPICWHOTIME)(split);
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
		capsEnabled ~= caps.save().array;
		foreach (ref cap; caps) {
			tryCall!"onReceiveCapAck"(cap, metadata);
			capReqCount--;
			if (capReqCount == 0) {
				endRegistration();
			}
		}
	}
	private void recCapNak(T)(T caps, const MessageMetadata metadata) if (is(ElementType!T == Capability)) {
		foreach (ref cap; caps) {
			tryCall!"onReceiveCapNak"(cap, metadata);
			capReqCount--;
			if (capReqCount == 0) {
				endRegistration();
			}
		}
	}
	private void recCapNew(T)(T caps, const MessageMetadata metadata) if (is(ElementType!T == Capability)) {
		foreach (ref cap; caps) {
			tryCall!"onReceiveCapNew"(cap, metadata);
		}
	}
	private void recCapDel(T)(T caps, const MessageMetadata metadata) if (is(ElementType!T == Capability)) {
		foreach (ref cap; caps) {
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
			tryCall!"onUserOnline"(user, metadata);
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
	private void recLogon(const User user, const MessageMetadata metadata) {
		tryCall!"onUserOnline"(user, metadata);
	}
	private void recChgHost(const User user, const User target, const MessageMetadata metadata) {
		tryCall!"onChgHost"(user, target, metadata);
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
		enforce(monitorIsEnabled);
		write("MONITOR C");
	}
	public void monitorList() {
		enforce(monitorIsEnabled);
		write("MONITOR L");
	}
	public void monitorStatus() {
		enforce(monitorIsEnabled);
		write("MONITOR S");
	}
	public void monitorAdd(T)(T users) if (isInputRange!T && is(ElementType!T == User)) {
		enforce(monitorIsEnabled);
		writeList("MONITOR +", ",", users.map!(x => x.nickname));
	}
	public void monitorRemove(T)(T users) if (isInputRange!T && is(ElementType!T == User)) {
		enforce(monitorIsEnabled);
		writeList("MONITOR -", ",", users.map!(x => x.nickname));
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
	public void msg(string target, string msg) {
		write!"PRIVMSG %s :%s"(target, msg);
	}
	private void recUnknownCommand(const string cmd, const MessageMetadata metadata) {
		if (cmd.filter!(x => !x.isDigit).empty) {
			recUnknownNumeric(cmd, metadata);
		} else {
			debug writeln(metadata.time, " Unknown command - ", metadata.original);
		}
	}
	private void recUnknownNumeric(const string cmd, const MessageMetadata metadata) {
		debug writeln(metadata.time, " Unhandled numeric: ", cast(Numeric)cmd, " ", metadata.original);
	}
	private void register() {
		if (isRegistered) {
			return;
		}
		if (!password.isNull) {
			write!"PASS :%s"(password);
		}
		changeNickname(nickname);
		write!"USER %s 0 * :%s"(username, realname);
	}
	private void write(string fmt, T...)(T args) {
		debug(verbose) writefln!("O: "~fmt)(args);
		formattedWrite!fmt(output, args);
		std.range.put(output, "\r\n");
		debug {
			tryCall!"onSend"(format!fmt(args));
		}
		static if (is(typeof(output.flush()))) {
			output.flush();
		}
	}
	private void write(T...)(const string fmt, T args) {
		debug(verbose) writefln("O: "~fmt, args);
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
	private void writeList(T)(const string begin, const string separator, T range) {
		foreach (chunk; ircChunks(begin, range, server.iSupport.lineLength, separator)) {
			write!"%s :%-(%s%s%)"(begin, chunk, separator);
		}
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
}


unittest {
	import std.algorithm : equal, sort;
	import std.array : appender, array;
	import std.range: empty, tail;
	import std.stdio : writeln;
	import std.string : lineSplitter;


	enum testUser = NickInfo("nick", "ident", "real name!");
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
	{
		auto buffer = appender!string;
		auto client = ircClient(buffer, testUser);
		bool lineReceived;
		client.onRaw = (const MessageMetadata) {
			lineReceived = true;
		};
		client.put("");
		assert(lineReceived == false);
		client.put("\r\n");
		assert(lineReceived == false);
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
	{
		auto buffer = appender!(string);
		auto client = ircClient(buffer, testUser);
		User[] users;
		const(Channel)[] channels;
		client.onJoin = (const User user, const Channel chan, const MessageMetadata) {
			users ~= user;
			channels ~= chan;
		};
		initialize(client);
		client.put (":someone!ident@hostmask JOIN :#test");
		assert(users.length == 1);
		assert(users[0].nickname == "someone");
		assert(channels.length == 1);
		assert(channels[0].name == "#test");
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
		const(Channel)[] channels;
		const(MessageMetadata)[] metadata;
		client.onUserOnline = (const User user, const MessageMetadata) {
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
		assert(users[0].nickname == "John");
		assert(users[0].ident == "test");
		assert(users[0].host == "example.net");
		assert(users[1].nickname == "Bob");
		assert(users[1].ident == "test2");
		assert(users[1].host == "example.com");

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
		client.onJoin = (const User user, const Channel chan, const MessageMetadata metadata) {
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
		auto user = User("WiZ!jto@tolsun.oulu.fi");
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
		client.put(":nick!user@host CHGHOST user new.host.goes.here");
		assert(users[0] == User("nick!user@host"));
		assert(users[1] == User("nick!user@new.host.goes.here"));
		client.put(":nick!user@host CHGHOST newuser host");
		assert(users[2] == User("nick!user@host"));
		assert(users[3] == User("nick!newuser@host"));
		client.put(":nick!user@host CHGHOST newuser new.host.goes.here");
		assert(users[4] == User("nick!user@host"));
		assert(users[5] == User("nick!newuser@new.host.goes.here"));
	}
	{ //PING? PONG!
		auto buffer = appender!(string);
		auto client = ircClient(buffer, testUser);

		initialize(client);
		client.put("PING :words");
		auto lineByLine = buffer.data.lineSplitter();
		assert(lineByLine.array[$-1] == "PONG :words");
	}
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
auto ircChunks(T)(const string begin, T range, const string inSeparator) {
	return cumulativeFold!((a, b) => a + b)(range.map!(a => a.length+inSeparator.length)).map!(x => x - inSeparator.length);
}
///
unittest {
	import std.algorithm : equal;
	assert(ircChunks("test", ["test2", "test3", "test4"], ",").equal([5, 11, 17]));
}