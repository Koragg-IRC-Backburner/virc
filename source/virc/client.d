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
import virc.ircv3.batch;
import virc.ircv3.sasl;
import virc.ircv3.tags;
import virc.modes;
import virc.numerics;
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
	"batch", // http://ircv3.net/specs/extensions/batch-3.2.html
	"cap-notify", // http://ircv3.net/specs/extensions/cap-notify-3.2.html
	"chghost", // http://ircv3.net/specs/extensions/chghost-3.2.html
	"echo-message", // http://ircv3.net/specs/extensions/echo-message-3.2.html
	"extended-join", // http://ircv3.net/specs/extensions/extended-join-3.1.html
	"invite-notify", // http://ircv3.net/specs/extensions/invite-notify-3.2.html
	//"metadata", // http://ircv3.net/specs/core/metadata-3.2.html
	//"monitor", // http://ircv3.net/specs/core/monitor-3.2.html
	"multi-prefix", // http://ircv3.net/specs/extensions/multi-prefix-3.1.html
	"sasl", // http://ircv3.net/specs/extensions/sasl-3.1.html and http://ircv3.net/specs/extensions/sasl-3.2.html
	"server-time", // http://ircv3.net/specs/extensions/server-time-3.2.html
	"userhost-in-names", // http://ircv3.net/specs/extensions/userhost-in-names-3.2.html
);

/++
+
+/
auto ircClient(alias mix, T)(ref T output, NickInfo info, SASLMechanism[] saslMechs = [], string password = string.init) {
	auto client = IRCClient!(mix, T)(output);
	client.username = info.username;
	client.realname = info.realname;
	client.nickname = info.nickname;
	if (password != string.init) {
		client.password = password;
	}
	client.saslMechs = saslMechs;
	client.initialize();
	return client;
}
///ditto
auto ircClient(T)(ref T output, NickInfo info, SASLMechanism[] saslMechs = [], string password = string.init) {
	return ircClient!null(output, info, saslMechs, password);
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
	///
	BatchInformation batch;
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
		auto split = msg[1..$-1].findSplit(" ");
		return split[2];
	}
	bool opEquals(string str) @safe pure nothrow @nogc const {
		return str == msg;
	}
	auto toHash() const {
		return hashOf(msg);
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
	{
		auto msg = Message("\x01VERSION\x01", MessageType.privmsg);
		assert(msg.isCTCP);
		assert(msg.ctcpCommand == "VERSION");
		assert(msg.ctcpArgs == "");
	}
}
@system pure nothrow @nogc unittest {
	assert(Message("Hello!", MessageType.notice).toHash == Message("Hello!", MessageType.privmsg).toHash);
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
	/++
	+ Mode prefixes present in target. May be present on both channels and users.
	+
	+ Channel mode prefixes are used when targetting a subset of users on that
	+ channel (all voiced users, for example), while user mode prefixes are found
	+ mainly in responses from the server.
	+/
	Nullable!string prefixes;
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
	/++
	+
	+/
	this(Channel chan) @safe pure nothrow @nogc {
		channel = chan;
	}
	/++
	+
	+/
	this(User user_) @safe pure nothrow @nogc {
		user = user_;
	}
	private this(string str, string modePrefixes, string channelPrefixes) @safe pure nothrow {
		import std.array : empty, front, popFront;
		import std.algorithm : canFind;
		import std.utf : byDchar;
		if (str.empty) {
			return;
		}
		auto tmpStr = str;
		while (modePrefixes.byDchar.canFind(tmpStr.byDchar.front)) {
			if (prefixes.isNull) {
				prefixes = "";
			}
			prefixes ~= tmpStr.byDchar.front;
			tmpStr.popFront();
		}
		if (!tmpStr.empty && channelPrefixes.byDchar.canFind(tmpStr.byDchar.front)) {
			channel = Channel(tmpStr);
		} else {
			user = User(tmpStr);
		}
	}
	/++
	+
	+/
	auto targetText() const {
		if (!channel.isNull) {
			return channel.name;
		} else if (!user.isNull) {
			return user.nickname;
		}
		assert(0, "No target specified");
	}
}
///
@safe pure nothrow unittest {
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
	assert(Target("Hello", "+@%", "#&")  == User("Hello"));
	assert(Target(Channel("#test")) == Channel("#test"));
	assert(Target(User("Test")) == User("Test"));
	{
		auto target = Target("+Hello", "+@%", "#&");
		assert(target == User("Hello"));
		assert(target.prefixes == "+");
	}
	assert(Target("#Hello", "+@%", "#&")  == Channel("#Hello"));
	{
		auto target = Target("+#Hello", "+@%", "#&");
		assert(target == Channel("#Hello"));
		assert(target.prefixes == "+");
	}
	{
		auto target = Target("+@#Hello", "+@%", "#&");
		assert(target == Channel("#Hello"));
		assert(target.prefixes == "+@");
	}
	{
		auto target = Target("", "", "");
		assert(target.channel.isNull);
		assert(target.user.isNull);
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

import virc.ircv3 : IRCV3Commands;
alias ClientNoOpCommands = AliasSeq!(
	RFC1459Commands.server,
	RFC1459Commands.user,
	RFC1459Commands.pass,
	RFC1459Commands.whois,
	RFC1459Commands.whowas,
	RFC1459Commands.kill,
	RFC1459Commands.who,
	RFC1459Commands.oper,
	RFC1459Commands.squit,
	RFC1459Commands.summon,
	RFC1459Commands.topic, //UNIMPLEMENTED
	RFC1459Commands.pong, //UNIMPLEMENTED
	RFC1459Commands.error, //UNIMPLEMENTED
	RFC1459Commands.userhost,
	RFC1459Commands.version_,
	RFC1459Commands.names,
	RFC1459Commands.away,
	RFC1459Commands.connect,
	RFC1459Commands.trace,
	RFC1459Commands.links,
	RFC1459Commands.stats,
	RFC1459Commands.ison,
	RFC1459Commands.restart,
	RFC1459Commands.users,
	RFC1459Commands.list,
	RFC1459Commands.admin,
	RFC1459Commands.rehash,
	RFC1459Commands.time,
	RFC1459Commands.info,
	RFC2812Commands.service,
	IRCV3Commands.starttls, //DO NOT IMPLEMENT
	IRCV3Commands.batch, //SPECIAL CASE
	IRCV3Commands.metadata, //UNIMPLEMENTED
	IRCV3Commands.monitor,
	Numeric.RPL_HOSTHIDDEN,
	Numeric.RPL_ENDOFNAMES,
	Numeric.RPL_ENDOFMONLIST,
	Numeric.RPL_LOCALUSERS,
	Numeric.RPL_GLOBALUSERS,
	Numeric.RPL_YOURHOST,
	Numeric.RPL_YOURID,
	Numeric.RPL_CREATED,
	Numeric.RPL_LISTSTART,
	Numeric.RPL_LISTEND,
	Numeric.RPL_TEXT,
);

/++
+
+/
struct ChannelState {
	Channel channel;
	string topic;
	User*[] users;
	void toString(T)(T sink) const if (isOutputRange!(T, const(char))) {
		formattedWrite!"Channel: %s\n"(sink, channel);
		formattedWrite!"\tTopic: %s\n"(sink, topic);
		formattedWrite!"\tUsers:\n"(sink);
		foreach (user; users) {
			formattedWrite!"\t\t%s\n"(sink, *user);
		}
	}
}
enum ErrorType {
	///Insufficient privileges for command.
	noPrivs,
	///Monitor list is full.
	monListFull,
	///Server has no MOTD.
	noMOTD,
	///Malformed message received from server.
	malformed
}
struct IRCError {
	ErrorType type;
	string message;
}
/++
+
+/
struct IRCClient(alias mix, T) if (isOutputRange!(T, char)) {
	import virc.ircv3 : Capability, CapabilityServerSubcommands, IRCV3Commands;
	T output;
	///
	Server server;
	///
	Capability[] capsEnabled;
	private string nickname;
	private string username;
	private string realname;
	private Nullable!string password;
	///
	ChannelState[string] channels;

	///SASL mechanisms available for usage
	SASLMechanism[] saslMechs;
	///
	InternalAddressList internalAddressList;

	static if (__traits(isTemplate, mix)) {
		mixin mix;
	} else {
		///
		void delegate(const Capability, const MessageMetadata) @safe onReceiveCapList;
		///
		void delegate(const Capability, const MessageMetadata) @safe onReceiveCapLS;
		///
		void delegate(const Capability, const MessageMetadata) @safe onReceiveCapAck;
		///
		void delegate(const Capability, const MessageMetadata) @safe onReceiveCapNak;
		///
		void delegate(const Capability, const MessageMetadata) @safe onReceiveCapDel;
		///
		void delegate(const Capability, const MessageMetadata) @safe onReceiveCapNew;
		///
		void delegate(const User, const SysTime, const MessageMetadata) @safe onUserOnline;
		///
		void delegate(const User, const MessageMetadata) @safe onUserOffline;
		///
		void delegate(const User, const MessageMetadata) @safe onLogin;
		///
		void delegate(const User, const MessageMetadata) @safe onLogout;
		///
		void delegate(const User, const string, const MessageMetadata) @safe onAway;
		///
		void delegate(const User, const MessageMetadata) @safe onBack;
		///
		void delegate(const User, const MessageMetadata) @safe onMonitorList;
		///
		void delegate(const User, const User, const MessageMetadata) @safe onNick;
		///
		void delegate(const User, const User, const Channel, const MessageMetadata) @safe onInvite;
		///
		void delegate(const User, const Channel, const MessageMetadata) @safe onJoin;
		///
		void delegate(const User, const Channel, const string, const MessageMetadata) @safe onPart;
		///
		void delegate(const User, const Channel, const User, const string, const MessageMetadata) @safe onKick;
		///
		void delegate(const User, const string, const MessageMetadata) @safe onQuit;
		///
		void delegate(const User, const Channel, const string, const MessageMetadata) @safe onTopic;
		///
		void delegate(const User, const Target, const ModeChange, const MessageMetadata) @safe onMode;
		///
		void delegate(const User, const Target, const Message, const MessageMetadata) @safe onMessage;
		///
		void delegate(const User, const string, const MessageMetadata) @safe onWallops;
		///
		void delegate(const ChannelListResult, const MessageMetadata) @safe onList;
		///
		void delegate(const User, const User, const MessageMetadata) @safe onChgHost;
		///
		void delegate(const LUserClient, const MessageMetadata) @safe onLUserClient;
		///
		void delegate(const LUserOp, const MessageMetadata) @safe onLUserOp;
		///
		void delegate(const LUserChannels, const MessageMetadata) @safe onLUserChannels;
		///
		void delegate(const LUserMe, const MessageMetadata) @safe onLUserMe;
		///
		void delegate(const NamesReply, const MessageMetadata) @safe onNamesReply;
		///
		void delegate(const TopicReply, const MessageMetadata) @safe onTopicReply;
		///
		void delegate(const TopicWhoTime, const MessageMetadata) @safe onTopicWhoTimeReply;
		///
		void delegate(const VersionReply, const MessageMetadata) @safe onVersionReply;
		///
		void delegate(const IRCError, const MessageMetadata) @safe onError;
		///
		void delegate(const MessageMetadata) @safe onRaw;
		///
		void delegate() @safe onConnect;
		///
		debug void delegate(const string) @safe onSend;
	}


	private bool invalid = true;
	private bool isRegistered;
	private ulong capReqCount = 0;
	private BatchProcessor batchProcessor;
	private bool isAuthenticating;
	private bool authenticationSucceeded;
	private string[] supportedSASLMechs;
	private SASLMechanism selectedSASLMech;
	private bool autoSelectSASLMech;
	private string receivedSASLAuthenticationText;

	bool isAuthenticated() {
		return authenticationSucceeded;
	}

	void initialize() {
		debug(verboseirc) {
			import std.experimental.logger : trace;
			trace("-------------------------");
		}
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
		import std.conv : asOriginalType;
		import std.meta : NoDuplicates;
		import std.string : representation;
		import std.traits : EnumMembers;
		debug(verboseirc) import std.experimental.logger : trace;
		//Chops off terminating \r\n. Everything after is ignored, according to spec.
		line = findSplitBefore(line, "\r\n")[0];
		debug(verboseirc) trace("←: ", line);
		assert(!invalid);
		if (line.empty) {
			return;
		}
		batchProcessor.put(line);
		foreach (batch; batchProcessor) {
			batchProcessor.popFront();
			foreach (tagSplit; batch.lines) {
				auto batchLine = tagSplit.msg;
				Nullable!User source;
				if (batchLine.front == ':') {
					auto found = batchLine.findSplit(" ");
					source = User();
					source.mask = UserMask(found[0][1..$]);
					batchLine = found[2];
				}
				auto split = IRCSplitter(batchLine);
				auto metadata = MessageMetadata();
				metadata.batch = tagSplit.batch;
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
				metadata.original = batchLine;
				tryCall!"onRaw"(metadata);

				auto firstToken = split.front;
				split.popFront();
				switchy: switch (firstToken) {
					//TOO MANY TEMPLATE INSTANTIATIONS! uncomment when compiler fixes this!
					//alias Numerics = NoDuplicates!(EnumMembers!Numeric);
					alias Numerics = AliasSeq!(Numeric.RPL_WELCOME, Numeric.RPL_ISUPPORT, Numeric.RPL_LIST, Numeric.RPL_YOURHOST, Numeric.RPL_CREATED, Numeric.RPL_LISTSTART, Numeric.RPL_LISTEND, Numeric.RPL_ENDOFMONLIST, Numeric.RPL_ENDOFNAMES, Numeric.RPL_YOURID, Numeric.RPL_LOCALUSERS, Numeric.RPL_GLOBALUSERS, Numeric.RPL_HOSTHIDDEN, Numeric.RPL_TEXT, Numeric.RPL_MYINFO, Numeric.RPL_LOGON, Numeric.RPL_MONONLINE, Numeric.RPL_MONOFFLINE, Numeric.RPL_MONLIST, Numeric.RPL_LUSERCLIENT, Numeric.RPL_LUSEROP, Numeric.RPL_LUSERCHANNELS, Numeric.RPL_LUSERME, Numeric.RPL_TOPIC, Numeric.RPL_NAMREPLY, Numeric.RPL_TOPICWHOTIME, Numeric.RPL_SASLSUCCESS, Numeric.RPL_LOGGEDIN, Numeric.RPL_VERSION, Numeric.ERR_MONLISTFULL, Numeric.ERR_NOMOTD, Numeric.ERR_NICKLOCKED, Numeric.ERR_SASLFAIL, Numeric.ERR_SASLTOOLONG, Numeric.ERR_SASLABORTED, Numeric.ERR_NOPRIVS);

					static foreach (cmd; AliasSeq!(NoDuplicates!(EnumMembers!IRCV3Commands), NoDuplicates!(EnumMembers!RFC1459Commands), NoDuplicates!(EnumMembers!RFC2812Commands), Numerics)) {
						case cmd:
							static if (!cmd.asOriginalType.among(ClientNoOpCommands)) {
								rec!cmd(source, split, metadata);
							}
							break switchy;
					}
					default: recUnknownCommand(firstToken, metadata); break;
				}
			}
		}
	}
	void put(immutable(ubyte)[] rawString) {
		put(rawString.toUTF8String);
	}
	private void tryEndRegistration() {
		if (capReqCount == 0 && !isAuthenticating && !isRegistered) {
			endRegistration();
		}
	}
	private void endAuthentication() {
		isAuthenticating = false;
		tryEndRegistration();
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
	public void join(T,U)(T chans, U keys) if (isInputRange!T && isInputRange!U) {
		auto filteredKeys = keys.filter!(x => !x.empty);
		if (!filteredKeys.empty) {
			write!"JOIN %-(%s,%) %-(%s,%)"(chans, filteredKeys);
		} else {
			write!"JOIN %-(%s,%)"(chans);
		}
	}
	public void join(const string chan, string key = "") {
		import std.range : only;
		join(only(chan), only(key));
	}
	public void join(const Channel chan, string key = "") {
		import std.range : only;
		join(only(chan.text), only(key));
	}
	public void msg(string target, string message) {
		write!"PRIVMSG %s :%s"(target, message);
	}
	public void wallops(const string message) {
		write!"WALLOPS :%s"(message);
	}
	public void msg(const Target target, const Message message) {
		msg(target.targetText, message.text);
	}
	public void ctcp(const Target target, const string command, const string args) {
		msg(target, Message("\x01"~command~" "~args~"\x01"));
	}
	public void ctcp(const Target target, const string command) {
		msg(target, Message("\x01"~command~"\x01"));
	}
	public void ctcpReply(const Target target, const string command, const string args) {
		notice(target, Message("\x01"~command~" "~args~"\x01"));
	}
	public void notice(const string target, const string message) {
		write!"NOTICE %s :%s"(target, message);
	}
	public void notice(const Target target, const Message message) {
		notice(target.targetText, message.text);
	}
	public void oper(string name, string pass) {
		assert(!name.canFind(" ") && !pass.canFind(" "));
		write!"OPER %s %s"(name, pass);
	}
	public void kick(Channel where, User who, string why) {
		write!"KICK %s %s :%s"(where.text, who.text, why);
	}
	public void version_() {
		write!"VERSION"();
	}
	public void version_(string serverMask) {
		write!"VERSION %s"(serverMask);
	}
	public void kick(const Channel chan, const User nick, const string message = "") {
		assert(message.length < server.iSupport.kickLength, "Kick message length exceeded");
		write!"KICK %s %s :%s"(chan, nick, message);
	}
	private void sendAuthenticatePayload(string payload) {
		import std.base64 : Base64;
		import std.range : chunks;
		import std.string : representation;
		if (payload == "") {
			write!"AUTHENTICATE +"();
		} else {
			auto str = Base64.encode(payload.representation);
			size_t lastChunkSize = 0;
			foreach (chunk; str.byCodeUnit.chunks(400)) {
				write!"AUTHENTICATE %s"(chunk);
				lastChunkSize = chunk.length;
			}
			if (lastChunkSize == 400) {
				write!"AUTHENTICATE +"();
			}
		}
	}
	private void user(string username_, string realname_) {
		write!"USER %s 0 * :%s"(username_, realname_);
	}
	private void pass(string pass) {
		write!"PASS :%s"(pass);
	}
	private void register() {
		assert(!isRegistered);
		if (!password.isNull) {
			pass(password);
		}
		changeNickname(nickname);
		user(username, realname);
	}
	private void write(string fmt, T...)(T args) {
		import std.range : put;
		debug(verboseirc) import std.experimental.logger : tracef;
		debug(verboseirc) tracef("→: "~fmt, args);
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
		debug(verboseirc) import std.experimental.logger : tracef;
		debug(verboseirc) tracef("→: "~fmt, args);
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
	private void tryCall(string func, T...)(T params) {
		import std.traits : hasMember;
		static if (!__traits(isTemplate, mix)) {
			if (__traits(getMember, this, func) !is null) {
				__traits(getMember, this, func)(params);
			}
		} else static if(hasMember!(typeof(this), func)) {
			__traits(getMember, this, func)(params);
		}
	}
	auto me() {
		assert(nickname in internalAddressList);
		return internalAddressList[nickname];
	}
	//Message parsing functions follow
	private void rec(string cmd : IRCV3Commands.cap, T)(User, T tokens, const MessageMetadata metadata) if (isInputRange!T && is(ElementType!T == string)) {
		immutable username = tokens.front; //Unused?
		tokens.popFront();
		immutable subCommand = tokens.front;
		tokens.popFront();
		immutable terminator = !tokens.skipOver("*");
		auto args = tokens
			.front
			.splitter(" ")
			.filter!(x => x != "")
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
			if (cap == "sasl") {
				supportedSASLMechs = cap.value.splitter(",").array;
			}
			tryCall!"onReceiveCapLS"(cap, metadata);
		}
	}
	private void recCapList(T)(T caps, const MessageMetadata metadata) if (is(ElementType!T == Capability)) {
		foreach (ref cap; caps) {
			if (cap == "sasl") {
				supportedSASLMechs = cap.value.splitter(",").array;
			}
			tryCall!"onReceiveCapList"(cap, metadata);
		}
	}
	private void recCapAck(T)(T caps, const MessageMetadata metadata) if (is(ElementType!T == Capability)) {
		import std.range : hasLength;
		capsEnabled ~= caps.save().array;
		foreach (ref cap; caps) {
			if (cap == "sasl") {
				startSASL();
			}
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
	private void capAcknowledgementCommon(const size_t count) {
		capReqCount -= count;
		tryEndRegistration();
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
	private void startSASL() {
		if (supportedSASLMechs.empty && !saslMechs.empty) {
			autoSelectSASLMech = true;
			saslAuth(saslMechs.front);
		} else if (!supportedSASLMechs.empty && !saslMechs.empty) {
			foreach (id, mech; saslMechs) {
				if (supportedSASLMechs.canFind(mech.name)) {
					saslAuth(mech);
				}
			}
		}
	}
	private void saslAuth(SASLMechanism mech) {
		selectedSASLMech = mech;
		write!"AUTHENTICATE %s"(mech.name);
		isAuthenticating = true;
	}
	private void rec(string cmd : RFC1459Commands.kick, T)(User source, T split, const MessageMetadata metadata) {
		if (split.empty) {
			return;
		}
		Channel channel = Channel(split.front);
		split.popFront();
		if (split.empty) {
			return;
		}
		User victim = User(split.front);
		split.popFront();
		string message;

		if (!split.empty) {
			message = split.front;
		}

		tryCall!"onKick"(source, channel, victim, message, metadata);
	}
	private void rec(string cmd : RFC1459Commands.wallops, T)(const User source, T tokens, const MessageMetadata metadata) if (isInputRange!T && is(ElementType!T == string)) {
		tryCall!"onWallops"(source, tokens.front, metadata);
	}
	private void rec(string cmd : RFC1459Commands.mode, T)(User source, T split, const MessageMetadata metadata) {
		auto target = Target(split.front, server.iSupport.statusMessage, server.iSupport.channelTypes);
		split.popFront();
		ModeType[char] modeTypes;
		if (target.isChannel) {
			modeTypes = server.iSupport.channelModeTypes;
		} else {
			//there are no user mode types.
		}
		auto modes = parseModeString(split, modeTypes);
		foreach (mode; modes) {
			tryCall!"onMode"(source, target, mode, metadata);
		}
	}
	private void rec(string cmd : RFC1459Commands.join, T)(User source, T split, const MessageMetadata metadata) if (isInputRange!T) {
		auto channel = Channel(split.front);
		split.popFront();
		if (isEnabled(Capability("extended-join"))) {
			if (split.front != "*") {
				source.account = split.front;
			}
			split.popFront();
			source.realName = split.front;
			split.popFront();
		}
		if (channel.name !in channels) {
			channels[channel.name] = ChannelState();
		}
		internalAddressList.update(source);
		channels[channel.name].users ~= source.nickname in internalAddressList;
		tryCall!"onJoin"(source, channel, metadata);
	}
	private void rec(string cmd : RFC1459Commands.part, T)(const User user, T split, const MessageMetadata metadata) {
		import std.algorithm.mutation : remove;
		import std.algorithm.searching : countUntil;
		auto channel = Channel(split.front);
		split.popFront();
		auto msg = split.front;
		if (channel.name in channels) {
			if (user.nickname in internalAddressList) {
				auto index = channels[channel.name].users.countUntil(user.nickname in internalAddressList);
				if (index > 0) {
					channels[channel.name].users.remove(index);
				}
			}
		}
		tryCall!"onPart"(user, channel, msg, metadata);
	}
	private void rec(string cmd : RFC1459Commands.notice, T)(const User user, T split, const MessageMetadata metadata) {
		auto target = Target(split.front, server.iSupport.statusMessage, server.iSupport.channelTypes);
		split.popFront();
		auto message = Message(split.front, MessageType.notice);
		recMessageCommon(user, target, message, metadata);
	}
	private void rec(string cmd : RFC1459Commands.privmsg, T)(const User user, T split, const MessageMetadata metadata) {
		auto target = Target(split.front, server.iSupport.statusMessage, server.iSupport.channelTypes);
		split.popFront();
		auto message = Message(split.front, MessageType.privmsg);
		recMessageCommon(user, target, message, metadata);
	}
	private void recMessageCommon(const User user, const Target target, Message msg, const MessageMetadata metadata) {
		if (user.nickname == nickname) {
			msg.isEcho = true;
		}
		tryCall!"onMessage"(user, target, msg, metadata);
	}
	private void rec(string cmd : Numeric.RPL_ISUPPORT, T)(const Nullable!User, T split, const MessageMetadata metadata) {
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
	}
	private void rec(string cmd : Numeric.RPL_WELCOME, T)(const Nullable!User, T split, const MessageMetadata metadata) {
		isRegistered = true;
		auto meUser = User();
		meUser.mask.nickname = nickname;
		meUser.mask.ident = username;
		internalAddressList.update(meUser);
		tryCall!"onConnect"();
	}
	private void rec(string cmd : Numeric.RPL_LOGGEDIN, T)(const Nullable!User, T split, const MessageMetadata metadata) {
		import virc.numerics.sasl : parseNumeric;
		if (isAuthenticating || isAuthenticated) {
			auto parsed = parseNumeric!(Numeric.RPL_LOGGEDIN)(split);
			auto user = User(parsed.mask);
			user.account = parsed.account;
			internalAddressList.update(user);
		}
	}
	private void rec(string cmd, T)(const Nullable!User, T split, const MessageMetadata metadata) if (cmd.among(Numeric.ERR_NICKLOCKED, Numeric.ERR_SASLFAIL, Numeric.ERR_SASLTOOLONG, Numeric.ERR_SASLABORTED)) {
		endAuthentication();
	}
	private void rec(string cmd : Numeric.RPL_MYINFO, T)(const Nullable!User, T split, const MessageMetadata metadata) {
		server.myInfo = parseNumeric!(Numeric.RPL_MYINFO)(split);
	}
	private void rec(string cmd : Numeric.RPL_LUSERCLIENT, T)(const Nullable!User, T split, const MessageMetadata metadata) {
		tryCall!"onLUserClient"(parseNumeric!(Numeric.RPL_LUSERCLIENT)(split), metadata);
	}
	private void rec(string cmd : Numeric.RPL_LUSEROP, T)(const Nullable!User, T split, const MessageMetadata metadata) {
		tryCall!"onLUserOp"(parseNumeric!(Numeric.RPL_LUSEROP)(split), metadata);
	}
	private void rec(string cmd : Numeric.RPL_LUSERCHANNELS, T)(const Nullable!User, T split, const MessageMetadata metadata) {
		tryCall!"onLUserChannels"(parseNumeric!(Numeric.RPL_LUSERCHANNELS)(split), metadata);
	}
	private void rec(string cmd : Numeric.RPL_LUSERME, T)(const Nullable!User, T split, const MessageMetadata metadata) {
		tryCall!"onLUserMe"(parseNumeric!(Numeric.RPL_LUSERME)(split), metadata);
	}
	private void rec(string cmd : Numeric.ERR_NOMOTD, T)(const Nullable!User, T split, const MessageMetadata metadata) {
		tryCall!"onError"(IRCError(ErrorType.noMOTD), metadata);
	}
	private void rec(string cmd : Numeric.RPL_SASLSUCCESS, T)(const Nullable!User, T split, const MessageMetadata metadata) {
		if (selectedSASLMech) {
			authenticationSucceeded = true;
		}
		endAuthentication();
	}
	private void rec(string cmd : Numeric.RPL_LIST, T)(const Nullable!User, T split, const MessageMetadata metadata) {
		auto channel = parseNumeric!(Numeric.RPL_LIST)(split, server.iSupport.channelModeTypes);
		tryCall!"onList"(channel, metadata);
	}
	private void rec(string cmd : RFC1459Commands.ping, T)(const Nullable!User, T split, const MessageMetadata) {
		pong(split.front);
	}
	private void rec(string cmd : Numeric.RPL_MONONLINE, T)(User , T split, const MessageMetadata metadata) if (isInputRange!T) {
		auto users = parseNumeric!(Numeric.RPL_MONONLINE)(split);
		foreach (user; users) {
			tryCall!"onUserOnline"(user, SysTime.init, metadata);
		}
	}
	private void rec(string cmd : Numeric.RPL_MONOFFLINE, T)(User, T split, const MessageMetadata metadata) if (isInputRange!T) {
		auto users = parseNumeric!(Numeric.RPL_MONOFFLINE)(split);
		foreach (user; users) {
			tryCall!"onUserOffline"(user, metadata);
		}
	}
	private void rec(string cmd : Numeric.RPL_MONLIST,  T)(User, T split, const MessageMetadata metadata) if (isInputRange!T) {
		auto users = parseNumeric!(Numeric.RPL_MONLIST)(split);
		foreach (user; users) {
			tryCall!"onMonitorList"(user, metadata);
		}
	}
	private void rec(string cmd : Numeric.ERR_MONLISTFULL, T)(const Nullable!User, T split, const MessageMetadata metadata) {
		auto err = parseNumeric!(Numeric.ERR_MONLISTFULL)(split);
		tryCall!"onError"(IRCError(ErrorType.monListFull), metadata);
	}
	private void rec(string cmd : Numeric.RPL_VERSION, T)(const Nullable!User, T split, const MessageMetadata metadata) {
		auto versionReply = parseNumeric!(Numeric.RPL_VERSION)(split);
		tryCall!"onVersionReply"(versionReply, metadata);
	}
	private void rec(string cmd : Numeric.RPL_LOGON, T)(const User user, T split, const MessageMetadata metadata) {
		auto reply = parseNumeric!(Numeric.RPL_LOGON)(split);
		tryCall!"onUserOnline"(reply.user, reply.timeOccurred, metadata);
	}
	private void rec(string cmd : IRCV3Commands.chghost, T)(const User user, T split, const MessageMetadata metadata) {
		User target;
		target.mask.nickname = user.nickname;
		target.mask.ident = split.front;
		split.popFront();
		target.mask.host = split.front;
		internalAddressList.update(target);
		tryCall!"onChgHost"(user, target, metadata);
	}
	private void rec(string cmd : Numeric.RPL_TOPICWHOTIME, T)(const User, T split, const MessageMetadata metadata) {
		auto reply = parseNumeric!(Numeric.RPL_TOPICWHOTIME)(split);
		if (!reply.isNull) {
			tryCall!"onTopicWhoTimeReply"(reply, metadata);
		}
	}
	private void rec(string cmd : Numeric.RPL_TOPIC, T)(const User, T split, const MessageMetadata metadata) {
		auto reply = parseNumeric!(Numeric.RPL_TOPIC)(split);
		if (!reply.isNull) {
			tryCall!"onTopicReply"(reply, metadata);
		}
	}
	private void rec(string cmd : RFC1459Commands.nick, T)(const User old, T split, const MessageMetadata metadata) {
		if (!split.empty) {
			internalAddressList.renameTo(old, split.front);
			auto new_ = internalAddressList[split.front];
			if (old.nickname == nickname) {
				nickname = new_.nickname;
			}
			tryCall!"onNick"(old, new_, metadata);
		}
	}
	private void rec(string cmd : RFC1459Commands.invite, T)(const User inviter, T split, const MessageMetadata metadata) {
		if (!split.empty) {
			User invited;
			if (split.front in internalAddressList) {
				invited = internalAddressList[split.front];
			} else {
				invited = User(split.front);
			}
			split.popFront();
			if (!split.empty) {
				auto channel = Channel(split.front);
				tryCall!"onInvite"(inviter, invited, channel, metadata);
			}
		}
	}
	private void rec(string cmd : RFC1459Commands.quit ,T)(const User user, T split, const MessageMetadata metadata) {
		string msg;
		if (!split.empty) {
			msg = split.front;
		}
		internalAddressList.invalidate(user.nickname);
		tryCall!"onQuit"(user, msg, metadata);
	}
	private void recUnknownCommand(const string cmd, const MessageMetadata metadata) {
		if (cmd.filter!(x => !x.isDigit).empty) {
			recUnknownNumeric(cmd, metadata);
		} else {
			debug(verboseirc) import std.experimental.logger : trace;
			debug(verboseirc) trace(" Unknown command: ", metadata.original);
		}
	}
	private void rec(string cmd : Numeric.RPL_NAMREPLY, T)(const User, T split, const MessageMetadata metadata) {
		auto reply = parseNumeric!(Numeric.RPL_NAMREPLY)(split);
		if (!reply.isNull) {
			tryCall!"onNamesReply"(reply, metadata);
		}
	}
	private void rec(string cmd : Numeric.ERR_NOPRIVS, T)(const User, T split, const MessageMetadata metadata) {
		auto reply = parseNumeric!(Numeric.ERR_NOPRIVS)(split);
		if (!reply.isNull) {
			tryCall!"onError"(IRCError(ErrorType.noPrivs, reply.priv), metadata);
		} else {
			tryCall!"onError"(IRCError(ErrorType.malformed), metadata);
		}
	}
	private void recUnknownNumeric(const string cmd, const MessageMetadata metadata) {
		debug(verboseirc) import std.experimental.logger : trace;
		debug(verboseirc) trace("Unhandled numeric: ", cast(Numeric)cmd, " ", metadata.original);
	}
	private void rec(string cmd : IRCV3Commands.account, T)(const User user, T split, const MessageMetadata metadata) {
		if (!split.empty) {
			auto newAccount = split.front;
			internalAddressList.update(user);
			auto newUser = internalAddressList[user.nickname];
			if (newAccount == "*") {
				newUser.account.nullify();
			} else {
				newUser.account = newAccount;
			}
			internalAddressList.updateExact(newUser);
		}
	}
	private void rec(string cmd : IRCV3Commands.authenticate, T)(const Nullable!User, T split, const MessageMetadata metadata) {
		import std.base64 : Base64;
		if (split.front != "+") {
			receivedSASLAuthenticationText ~= Base64.decode(split.front);
		}
		if ((selectedSASLMech) && (split.front == "+" || (split.front.length < 400))) {
			selectedSASLMech.put(receivedSASLAuthenticationText);
			if (selectedSASLMech.empty) {
				sendAuthenticatePayload("");
			} else {
				sendAuthenticatePayload(selectedSASLMech.front);
				selectedSASLMech.popFront();
			}
			receivedSASLAuthenticationText = [];
		}
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
	static immutable testClientInfo = NickInfo("nick", "ident", "real name!");
	static immutable testUser = User(testClientInfo.nickname, testClientInfo.username, "example.org");
	mixin template Test() {
		bool lineReceived;
		void onRaw(const MessageMetadata) @safe pure {
			lineReceived = true;
		}
	}
	void setupFakeConnection(T)(ref T client) {
		client.put(":localhost 001 someone :Welcome to the TestNet IRC Network "~testUser.text);
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
		initializeWithCaps(client, [Capability("multi-prefix"), Capability("server-time"), Capability("sasl", "EXTERNAL")]);
	}
	void initializeWithCaps(T)(ref T client, Capability[] caps) {
		foreach (i, cap; caps) {
			client.put(":localhost CAP * LS " ~ ((i+1 == caps.length) ? "" : "* ")~ ":" ~ cap.toString);
			client.put(":localhost CAP * ACK :" ~ cap.name);
		}
		setupFakeConnection(client);
	}
	auto spawnNoBufferClient(string password = string.init) {
		auto buffer = appender!(string);
		return ircClient(buffer, testClientInfo, [], password);
	}
	auto spawnNoBufferClient(alias mix)(string password = string.init) {
		auto buffer = appender!(string);
		return ircClient!mix(buffer, testClientInfo, [], password);
	}
}
///Test the basics
@safe unittest {
	auto client = spawnNoBufferClient!Test();
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
	auto client = spawnNoBufferClient!Test();
	client.put("\r\n".representation);
	assert(client.lineReceived == false);
}
///
@safe unittest {
	import virc.ircv3 : Capability;
	{ //password test
		auto client = spawnNoBufferClient("Example");

		assert(client.output.data.lineSplitter.until!(x => x.startsWith("USER")).canFind("PASS :Example"));
	}
	//Request capabilities (IRC v3.2)
	{
		auto client = spawnNoBufferClient();
		client.put(":localhost CAP * LS :multi-prefix sasl");
		client.put(":localhost CAP * ACK :multi-prefix sasl");

		auto lineByLine = client.output.data.lineSplitter;

		assert(lineByLine.front == "CAP LS 302");
		lineByLine.popFront();
		lineByLine.popFront();
		lineByLine.popFront();
		//sasl not yet supported
		assert(lineByLine.front == "CAP REQ :multi-prefix sasl");
		lineByLine.popFront();
		assert(!lineByLine.empty);
		assert(lineByLine.front == "CAP END");
	}
	//Request capabilities NAK (IRC v3.2)
	{
		auto client = spawnNoBufferClient();
		Capability[] capabilities;
		client.onReceiveCapNak = (const Capability cap, const MessageMetadata) {
			capabilities ~= cap;
		};
		client.put(":localhost CAP * LS :multi-prefix");
		client.put(":localhost CAP * NAK :multi-prefix");


		auto lineByLine = client.output.data.lineSplitter;

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
		auto client = spawnNoBufferClient();
		auto lineByLine = client.output.data.lineSplitter();

		Capability[] capabilities;
		client.onReceiveCapLS = (const Capability cap, const MessageMetadata) {
			capabilities ~= cap;
		};

		assert(lineByLine.front == "CAP LS 302");

		put(client, ":localhost CAP * LS * :multi-prefix extended-join account-notify batch invite-notify tls");
		put(client, ":localhost CAP * LS * :cap-notify server-time example.org/dummy-cap=dummyvalue example.org/second-dummy-cap");
		put(client, ":localhost CAP * LS :userhost-in-names sasl=EXTERNAL,DH-AES,DH-BLOWFISH,ECDSA-NIST256P-CHALLENGE,PLAIN");
		assert(capabilities.length == 12);
		setupFakeConnection(client);
	}
	//CAP LIST multiline (IRC v3.2)
	{
		auto client = spawnNoBufferClient();
		Capability[] capabilities;
		client.onReceiveCapList = (const Capability cap, const MessageMetadata) {
			capabilities ~= cap;
		};
		setupFakeConnection(client);
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
		auto client = spawnNoBufferClient();
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
		auto lineByLine = client.output.data.lineSplitter();
		assert(lineByLine.array[$-1] == "CAP REQ :account-notify");
	}
	{ //JOIN
		auto client = spawnNoBufferClient();
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
		setupFakeConnection(client);
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
			//TODO: remove when lack of these imports no longer produces warnings
			import std.datetime : SysTime;
			import virc.common : User;
			assert(channel == "#test");
			assert(setter == User("someoneElse"));
			assert(timestamp == SysTime(DateTime(2017, 06, 07, 07, 53, 03), UTC()));
		}
		//TODO: Add 366, 324, 329 tests
		auto lineByLine = client.output.data.lineSplitter();
		assert(lineByLine.array[$-1] == "JOIN #test");
	}
	{ //Channel list example
		auto client = spawnNoBufferClient();
		const(ChannelListResult)[] channels;
		client.onList = (const ChannelListResult chan, const MessageMetadata) {
			channels ~= chan;
		};
		setupFakeConnection(client);
		client.list();
		client.put("321 someone Channel :Users Name");
		client.put("322 someone #test 4 :[+fnt 200:2] some words");
		client.put("322 someone #test2 6 :[+fnst 100:2] some more words");
		client.put("322 someone #test3 1 :no modes?");
		client.put("323 someone :End of channel list.");
		assert(channels.length == 3);
		with(channels[0]) {
			//TODO: remove when lack of import no longer produces a warning
			import virc.common : Topic;
			assert(name == "#test");
			assert(userCount == 4);
			assert(topic == Topic("some words"));
		}
		with(channels[1]) {
			//TODO: remove when lack of import no longer produces a warning
			import virc.common : Topic;
			assert(name == "#test2");
			assert(userCount == 6);
			assert(topic == Topic("some more words"));
		}
		with(channels[2]) {
			//TODO: remove when lack of import no longer produces a warning
			import virc.common : Topic;
			assert(name == "#test3");
			assert(userCount == 1);
			assert(topic == Topic("no modes?"));
		}
	}
	{ //server-time http://ircv3.net/specs/extensions/server-time-3.2.html
		auto client = spawnNoBufferClient();
		User[] users;
		const(Channel)[] channels;
		client.onJoin = (const User user, const Channel chan, const MessageMetadata metadata) {
			users ~= user;
			channels ~= chan;
			assert(metadata.time == SysTime(DateTime(2012,06,30,23,59,59), 419.msecs, UTC()));
		};
		setupFakeConnection(client);
		client.put("@time=2012-06-30T23:59:59.419Z :John!~john@1.2.3.4 JOIN #chan");
		assert(users.length == 1);
		assert(users[0].nickname == "John");
		assert(channels.length == 1);
		assert(channels[0].name == "#chan");
	}
	{ //monitor
		auto client = spawnNoBufferClient();
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
		client.onError = (const IRCError error, const MessageMetadata received) {
			assert(error.type == ErrorType.monListFull);
			metadata ~= received;
		};
		setupFakeConnection(client);
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
		auto client = spawnNoBufferClient();

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
	{ //test for blank caps
		auto client = spawnNoBufferClient();
		put(client, ":localhost CAP * LS * : ");
		setupFakeConnection(client);
		assert(client.isRegistered);
	}
	{ //example taken from RFC2812, section 3.2.2
		auto client = spawnNoBufferClient();

		User[] users;
		const(Channel)[] channels;
		string lastMsg;
		client.onPart = (const User user, const Channel chan, const string msg, const MessageMetadata) {
			users ~= user;
			channels ~= chan;
			lastMsg = msg;
		};

		setupFakeConnection(client);

		client.put(":WiZ!jto@tolsun.oulu.fi PART #playzone :I lost");
		immutable user = User("WiZ!jto@tolsun.oulu.fi");
		assert(users.front == user);
		assert(channels.front == Channel("#playzone"));
		assert(lastMsg == "I lost");
	}
	{ //PART tests
		auto client = spawnNoBufferClient();

		Tuple!(const User, "user", const Channel, "channel", string, "message")[] parts;
		client.onPart = (const User user, const Channel chan, const string msg, const MessageMetadata) {
			parts ~= tuple!("user", "channel", "message")(user, chan, msg);
		};

		setupFakeConnection(client);

		assert("#example" !in client.channels);
		client.put(":"~testUser.text~" PART #example :see ya");
		assert("#example" !in client.channels);

		with (parts[0]) {
			assert(user == client.me);
			assert(channel == Channel("#example"));
			assert(message == "see ya");
		}
	}
	{ //http://ircv3.net/specs/extensions/chghost-3.2.html
		auto client = spawnNoBufferClient();

		User[] users;
		client.onChgHost = (const User user, const User newUser, const MessageMetadata) {
			users ~= user;
			users ~= newUser;
		};

		setupFakeConnection(client);
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
		auto client = spawnNoBufferClient();

		setupFakeConnection(client);
		client.put("PING :words");
		auto lineByLine = client.output.data.lineSplitter();
		assert(lineByLine.array[$-1] == "PONG :words");
	}
	{ //echo-message http://ircv3.net/specs/extensions/echo-message-3.2.html
		auto client = spawnNoBufferClient();
		Message[] messages;
		client.onMessage = (const User, const Target, const Message msg, const MessageMetadata) {
			messages ~= msg;
		};
		setupFakeConnection(client);
		client.msg("Attila", "hi");
		client.put(":"~testUser.text~" PRIVMSG Attila :hi");
		assert(messages.length > 0);
		assert(messages[0].isEcho);

		client.msg("#ircv3", "back from \x02lunch\x0F");
		client.put(":"~testUser.text~" PRIVMSG #ircv3 :back from lunch");
		assert(messages.length > 1);
		assert(messages[1].isEcho);
	}
	{ //Test self-tracking
		auto client = spawnNoBufferClient();
		setupFakeConnection(client);
		assert(client.me.nickname == testUser.nickname);
		client.changeNickname("Testface");
		client.put(":"~testUser.nickname~" NICK Testface");
		assert(client.me.nickname == "Testface");
	}
}
@system unittest {
	{ //QUIT and invalidation check
		import core.exception : AssertError;
		import std.exception : assertThrown;
		auto client = spawnNoBufferClient();

		setupFakeConnection(client);
		client.quit("I'm out");
		auto lineByLine = client.output.data.lineSplitter();
		assert(lineByLine.array[$-1] == "QUIT :I'm out");
		assert(client.invalid);
		assertThrown!AssertError(client.put("PING :hahahaha"));
	}
}
@safe unittest {
	{ //NAMES
		auto client = spawnNoBufferClient();
		NamesReply[] replies;
		client.onNamesReply = (const NamesReply reply, const MessageMetadata) {
			replies ~= reply;
		};

		setupFakeConnection(client);

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
		auto client = spawnNoBufferClient();
		User[] users;
		SysTime[] times;
		client.onUserOnline = (const User user, const SysTime time, const MessageMetadata) {
			users ~= user;
			times ~= time;
		};
		setupFakeConnection(client);
		client.put(":localhost 600 someone someoneElse someIdent example.net 911248013 :logged on");

		assert(users.length == 1);
		assert(users[0] == User("someoneElse!someIdent@example.net"));
		assert(times.length == 1);
		assert(times[0] == SysTime(DateTime(1998, 11, 16, 20, 26, 53), UTC()));
	}
	{ //LUSER stuff
		auto client = spawnNoBufferClient();
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
		setupFakeConnection(client);
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
		auto client = spawnNoBufferClient();
		Tuple!(const User, "user", const Target, "target", const Message, "message")[] messages;
		client.onMessage = (const User user, const Target target, const Message msg, const MessageMetadata) {
			messages ~= tuple!("user", "target", "message")(user, target, msg);
		};

		setupFakeConnection(client);

		client.put(":someoneElse!somebody@somewhere PRIVMSG someone :words go here");
		assert(messages.length == 1);
		with (messages[0]) {
			assert(user == User("someoneElse!somebody@somewhere"));
			assert(!target.isChannel);
			assert(target.isNickname);
			assert(target == User("someone"));
			assert(message == "words go here");
			assert(message.isReplyable);
			assert(!message.isEcho);
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
			assert(!message.isEcho);
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
			assert(!message.isEcho);
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
			assert(!message.isEcho);
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
			assert(!message.isEcho);
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
			assert(!message.isEcho);
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
		auto lineByLine = client.output.data.lineSplitter();
		foreach (i; 0..5) //skip the initial handshake
			lineByLine.popFront();
		assert(lineByLine.array == ["PRIVMSG #channel :ohai", "NOTICE #channel :ohi", "PRIVMSG someoneElse :ohay", "NOTICE someoneElse :ohello", "PRIVMSG #channel :ohai", "NOTICE #channel :ohi", "PRIVMSG someoneElse :ohay", "NOTICE someoneElse :ohello"]);
	}
	{ //PING? PONG!
		auto client = spawnNoBufferClient();

		setupFakeConnection(client);
		client.ping("hooray");
		client.put(":localhost PONG localhost :hooray");
		auto lineByLine = client.output.data.lineSplitter();
		assert(lineByLine.array[$-1] == "PING :hooray");
	}
	{ //Mode change test
		auto client = spawnNoBufferClient();
		Tuple!(const User, "user", const Target, "target", const ModeChange, "change")[] changes;

		client.onMode = (const User user, const Target target, const ModeChange mode, const MessageMetadata) {
			changes ~= tuple!("user", "target", "change")(user, target, mode);
		};

		setupFakeConnection(client);
		client.join("#test");
		client.put(":"~testUser.text~" JOIN #test "~testUser.nickname);
		client.put(":someone!ident@host JOIN #test");
		client.put(":someoneElse!user@host2 MODE #test +s");
		client.put(":someoneElse!user@host2 MODE #test -s");
		client.put(":someoneElse!user@host2 MODE #test +kp 2");
		client.put(":someoneElse!user@host2 MODE someone +r");
		client.put(":someoneElse!user@host2 MODE someone +k");

		assert(changes.length == 6);
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
		with (changes[5]) {
			assert(target == User("someone"));
			assert(user == User("someoneElse!user@host2"));
		}
	}
	{ //client join stuff
		auto client = spawnNoBufferClient();
		client.join("#test");
		assert(client.output.data.lineSplitter.array[$-1] == "JOIN #test");
		client.join(Channel("#test2"));
		assert(client.output.data.lineSplitter.array[$-1] == "JOIN #test2");
		client.join("#test3", "key");
		assert(client.output.data.lineSplitter.array[$-1] == "JOIN #test3 key");
		client.join("#test4", "key2");
		assert(client.output.data.lineSplitter.array[$-1] == "JOIN #test4 key2");
	}
	{ //account-tag examples from http://ircv3.net/specs/extensions/account-tag-3.2.html
		auto client = spawnNoBufferClient();
		User[] privmsgUsers;
		client.onMessage = (const User user, const Target, const Message, const MessageMetadata) {
			privmsgUsers ~= user;
		};
		setupFakeConnection(client);

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
		assert(client.internalAddressList["user"].account == "bob");
	}
	{ //account-notify - http://ircv3.net/specs/extensions/account-notify-3.1.html
		auto client = spawnNoBufferClient();
		//User[] privmsgUsers;
		//client.onMessage = (const User user, const Target, const Message, const MessageMetadata) {
		//	privmsgUsers ~= user;
		//};
		setupFakeConnection(client);
		client.put(":nick!user@host ACCOUNT accountname");
		assert(client.internalAddressList["nick"].account == "accountname");
		client.put(":nick!user@host ACCOUNT *");
		assert(client.internalAddressList["nick"].account.isNull);
	}
	{ //monitor - http://ircv3.net/specs/core/monitor-3.2.html
		auto client = spawnNoBufferClient();
		initializeWithCaps(client, [Capability("MONITOR")]);

		assert(client.monitorIsEnabled);

		client.monitorAdd([User("Someone")]);
		client.monitorRemove([User("Someone")]);
		client.monitorClear();
		client.monitorList();
		client.monitorStatus();

		const lineByLine = client.output.data.lineSplitter().drop(5).array;
		assert(lineByLine == ["MONITOR + Someone", "MONITOR - Someone", "MONITOR C", "MONITOR L", "MONITOR S"]);
	}
	{ //No MOTD test
		auto client = spawnNoBufferClient();
		bool errorReceived;
		client.onError = (const IRCError error, const MessageMetadata) {
			assert(!errorReceived);
			errorReceived = true;
			assert(error.type == ErrorType.noMOTD);
		};
		setupFakeConnection(client);
		client.put("422 someone :MOTD File is missing");
		assert(errorReceived);
	}
	{ //NICK tests
		auto client = spawnNoBufferClient();
		Tuple!(const User, "old", const User, "new_")[] nickChanges;
		client.onNick = (const User old, const User new_, const MessageMetadata) {
			nickChanges ~= tuple!("old", "new_")(old, new_);
		};

		setupFakeConnection(client);
		client.put(":WiZ NICK Kilroy");

		assert(nickChanges.length == 1);
		with(nickChanges[0]) {
			assert(old.nickname == "WiZ");
			assert(new_.nickname == "Kilroy");
		}

		client.put(":dan-!d@localhost NICK Mamoped");

		assert(nickChanges.length == 2);
		with(nickChanges[1]) {
			assert(old.nickname == "dan-");
			assert(new_.nickname == "Mamoped");
		}

		//invalid, so we shouldn't see anything
		client.put(":a NICK");
		assert(nickChanges.length == 2);
	}
	{ //QUIT tests
		auto client = spawnNoBufferClient();

		Tuple!(const User, "user", string, "message")[] quits;
		client.onQuit = (const User user, const string msg, const MessageMetadata) {
			quits ~= tuple!("user", "message")(user, msg);
		};

		setupFakeConnection(client);

		client.put(":dan-!d@localhost QUIT :Quit: Bye for now!");
		assert(quits.length == 1);
		with (quits[0]) {
			assert(user == User("dan-!d@localhost"));
			assert(message == "Quit: Bye for now!");
		}
		client.put(":nomessage QUIT");
		assert(quits.length == 2);
		with(quits[1]) {
			assert(user == User("nomessage"));
			assert(message == "");
		}
	}
	{ //Batch stuff
		auto client = spawnNoBufferClient();

		Tuple!(const User, "user", const MessageMetadata, "metadata")[] quits;
		client.onQuit = (const User user, const string, const MessageMetadata metadata) {
			quits ~= tuple!("user", "metadata")(user, metadata);
		};

		setupFakeConnection(client);

		client.put(`:irc.host BATCH +yXNAbvnRHTRBv netsplit irc.hub other.host`);
		client.put(`@batch=yXNAbvnRHTRBv :aji!a@a QUIT :irc.hub other.host`);
		client.put(`@batch=yXNAbvnRHTRBv :nenolod!a@a QUIT :irc.hub other.host`);
		client.put(`:nick!user@host PRIVMSG #channel :This is not in batch, so processed immediately`);
		client.put(`@batch=yXNAbvnRHTRBv :jilles!a@a QUIT :irc.hub other.host`);

		assert(quits.length == 0);

		client.put(`:irc.host BATCH -yXNAbvnRHTRBv`);

		assert(quits.length == 3);
		with(quits[0]) {
			assert(metadata.batch.type == "netsplit");
		}
	}
	{ //INVITE tests
		auto client = spawnNoBufferClient();

		Tuple!(const User, "inviter", const User, "invited",  const Channel, "channel")[] invites;
		client.onInvite = (const User inviter, const User invited, const Channel channel, const MessageMetadata) {
			invites ~= tuple!("inviter", "invited", "channel")(inviter, invited, channel);
		};

		setupFakeConnection(client);

		//Ensure the internal address list gets used for invited users as well
		client.internalAddressList.update(User("Wiz!ident@host"));

		client.put(":Angel INVITE Wiz #Dust");
		assert(invites.length == 1);
		with(invites[0]) {
			assert(inviter.nickname == "Angel");
			assert(invited.nickname == "Wiz");
			assert(invited.host == "host");
			assert(channel == Channel("#Dust"));
		}

		client.put(":ChanServ!ChanServ@example.com INVITE Attila #channel");
		assert(invites.length == 2);
		with(invites[1]) {
			assert(inviter.nickname == "ChanServ");
			assert(invited.nickname == "Attila");
			assert(channel == Channel("#channel"));
		}
	}
	{ //VERSION tests
		auto client = spawnNoBufferClient();

		VersionReply[] replies;
		client.onVersionReply = (const VersionReply reply, const MessageMetadata) {
			replies ~= reply;
		};

		setupFakeConnection(client);

		client.version_();
		client.put(format!":localhost 351 %s example-1.0 localhost :not a beta"(testUser.nickname));
		with (replies[0]) {
			assert(version_ == "example-1.0");
			assert(server == "localhost");
			assert(comments == "not a beta");
		}
		client.version_("*.example");
		client.put(format!":localhost 351 %s example-1.0 test.example :not a beta"(testUser.nickname));
		with (replies[1]) {
			assert(version_ == "example-1.0");
			assert(server == "test.example");
			assert(comments == "not a beta");
		}
	}
	{ //SASL test
		auto client = spawnNoBufferClient();
		client.saslMechs = [new SASLPlain("jilles", "jilles", "sesame")];
		client.put(":localhost CAP * LS :sasl");
		client.put(":localhost CAP whoever ACK :sasl");
		client.put("AUTHENTICATE +");
		client.put(":localhost 900 "~testUser.nickname~" "~testUser.text~" "~testUser.nickname~" :You are now logged in as "~testUser.nickname);
		client.put(":localhost 903 "~testUser.nickname~" :SASL authentication successful");

		assert(client.output.data.canFind("AUTHENTICATE amlsbGVzAGppbGxlcwBzZXNhbWU="));
		assert(client.isAuthenticated == true);
		assert(client.me.account == testUser.nickname);
	}
	{ //SASL 3.2 test
		auto client = spawnNoBufferClient();
		client.saslMechs = [new SASLPlain("jilles", "jilles", "sesame")];
		client.put(":localhost CAP * LS :sasl=UNKNOWN,PLAIN,EXTERNAL");
		client.put(":localhost CAP whoever ACK :sasl");
		client.put("AUTHENTICATE +");
		client.put(":localhost 900 "~testUser.nickname~" "~testUser.text~" "~testUser.nickname~" :You are now logged in as "~testUser.nickname);
		client.put(":localhost 903 "~testUser.nickname~" :SASL authentication successful");

		assert(client.output.data.canFind("AUTHENTICATE amlsbGVzAGppbGxlcwBzZXNhbWU="));
		assert(client.isAuthenticated == true);
		assert(client.me.account == testUser.nickname);
	}
	{ //SASL 3.2 test
		auto client = spawnNoBufferClient();
		client.saslMechs = [new SASLExternal];
		client.put(":localhost CAP * LS :sasl=UNKNOWN,EXTERNAL");
		client.put(":localhost CAP whoever ACK :sasl");
		client.put("AUTHENTICATE +");
		client.put(":localhost 900 "~testUser.nickname~" "~testUser.text~" "~testUser.nickname~" :You are now logged in as "~testUser.nickname);
		client.put(":localhost 903 "~testUser.nickname~" :SASL authentication successful");

		assert(client.output.data.canFind("AUTHENTICATE +"));
		assert(client.isAuthenticated == true);
		assert(client.me.account == testUser.nickname);
	}
	{ //SASL 3.2 test (bogus)
		auto client = spawnNoBufferClient();
		client.saslMechs = [new SASLPlain("jilles", "jilles", "sesame")];
		client.put(":localhost CAP * LS :sasl=UNKNOWN,EXTERNAL");
		client.put(":localhost CAP whoever ACK :sasl");
		client.put("AUTHENTICATE +");
		client.put(":localhost 900 "~testUser.nickname~" "~testUser.text~" "~testUser.nickname~" :You are now logged in as "~testUser.nickname);
		client.put(":localhost 903 "~testUser.nickname~" :SASL authentication successful");

		assert(!client.output.data.canFind("AUTHENTICATE amlsbGVzAGppbGxlcwBzZXNhbWU="));
		assert(client.isAuthenticated == false);
		//assert(client.me.account.isNull);
	}
	{ //SASL post-registration test
		auto client = spawnNoBufferClient();
		client.saslMechs = [new SASLExternal()];
		setupFakeConnection(client);
		client.capList();
		client.put(":localhost CAP * LIST :sasl=UNKNOWN,PLAIN,EXTERNAL");
	}
	{ //KICK tests
		auto client = spawnNoBufferClient();
		Tuple!(const User, "kickedBy", const User, "kicked",  const Channel, "channel", string, "message")[] kicks;
		client.onKick = (const User kickedBy, const Channel channel, const User kicked, const string message, const MessageMetadata) {
			kicks ~= tuple!("kickedBy", "kicked", "channel", "message")(kickedBy, kicked, channel, message);
		};
		setupFakeConnection(client);
		client.kick(Channel("#test"), User("Example"), "message");
		auto lineByLine = client.output.data.lineSplitter();
		assert(lineByLine.array[$-1] == "KICK #test Example :message");

		client.put(":WiZ KICK #Finnish John");

		assert(kicks.length == 1);
		with(kicks[0]) {
			assert(kickedBy == User("WiZ"));
			assert(channel == Channel("#Finnish"));
			assert(kicked == User("John"));
			assert(message == "");
		}

		client.put(":Testo KICK #example User :Now with kick message!");

		assert(kicks.length == 2);
		with(kicks[1]) {
			assert(kickedBy == User("Testo"));
			assert(channel == Channel("#example"));
			assert(kicked == User("User"));
			assert(message == "Now with kick message!");
		}

		client.put(":WiZ!jto@tolsun.oulu.fi KICK #Finnish John");

		assert(kicks.length == 3);
		with(kicks[2]) {
			assert(kickedBy == User("WiZ!jto@tolsun.oulu.fi"));
			assert(channel == Channel("#Finnish"));
			assert(kicked == User("John"));
			assert(message == "");
		}

		client.put(":User KICK");
		assert(kicks.length == 3);

		client.put(":User KICK #channel");
		assert(kicks.length == 3);
	}
	{ //WALLOPS tests
		auto client = spawnNoBufferClient();
		string[] messages;
		client.onWallops = (const User, const string msg, const MessageMetadata) {
			messages ~= msg;
		};
		setupFakeConnection(client);

		client.wallops("Test message!");
		auto lineByLine = client.output.data.lineSplitter();
		assert(lineByLine.array[$-1] == "WALLOPS :Test message!");

		client.put(":OtherUser!someone@somewhere WALLOPS :Test message reply!");
		assert(messages.length == 1);
		assert(messages[0] == "Test message reply!");

	}
	{ //CTCP tests
		auto client = spawnNoBufferClient();
		setupFakeConnection(client);
		client.ctcp(Target(User("test")), "ping");
		client.ctcp(Target(User("test")), "action", "does the thing.");
		client.ctcpReply(Target(User("test")), "ping", "1000000000");

		auto lineByLine = client.output.data.lineSplitter();
		assert(lineByLine.array[$-3] == "PRIVMSG test :\x01ping\x01");
		assert(lineByLine.array[$-2] == "PRIVMSG test :\x01action does the thing.\x01");
		assert(lineByLine.array[$-1] == "NOTICE test :\x01ping 1000000000\x01");
	}
}