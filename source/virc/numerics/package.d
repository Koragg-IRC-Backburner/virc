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
public import virc.numerics.isupport;
import virc.usermask;

///
enum Numeric {
	//RFC1459 Command responses: https://tools.ietf.org/html/rfc1459#section-6.2
	///
	RPL_TRACELINK = "200",
	///
	RPL_TRACECONNECTING = "201",
	///
	RPL_TRACEHANDSHAKE = "202",
	///
	RPL_TRACEUNKNOWN = "203",
	///
	RPL_TRACEOPERATOR = "204",
	///
	RPL_TRACEUSER = "205",
	///
	RPL_TRACESERVER = "206",
	///
	RPL_TRACENEWTYPE = "208",
	///
	RPL_STATSLINKINFO = "211",
	///
	RPL_STATSCOMMANDS = "212",
	///
	RPL_STATSCLINE = "213",
	///
	RPL_STATSNLINE = "214",
	///
	RPL_STATSILINE = "215",
	///
	RPL_STATSKLINE = "216",
	///
	RPL_STATSYLINE = "218",
	///
	RPL_ENDOFSTATS = "219",
	///
	RPL_STATSLLINE = "241",
	///
	RPL_STATSUPTIME = "242",
	///
	RPL_STATSOLINE = "243",
	///
	RPL_STATSHLINE = "244",
	///
	RPL_UMODEIS = "221",
	///
	RPL_LUSERCLIENT = "251",
	///
	RPL_LUSEROP = "252",
	///
	RPL_LUSERUNKNOWN = "253",
	///
	RPL_LUSERCHANNELS = "254",
	///
	RPL_LUSERME = "255",
	///
	RPL_ADMINME = "256",
	///
	RPL_ADMINLOC1 = "257",
	///
	RPL_ADMINLOC2 = "258",
	///
	RPL_ADMINEMAIL = "259",
	///
	RPL_TRACELOG = "261",
	///
	RPL_NONE = "300",
	///
	RPL_AWAY = "301",
	///
	RPL_USERHOST = "302",
	///
	RPL_ISON = "303",
	///
	RPL_UNAWAY = "305",
	///
	RPL_NOWAWAY = "306",
	///
	RPL_WHOISUSER = "311",
	///
	RPL_WHOISSERVER = "312",
	///
	RPL_WHOISOPERATOR = "313",
	///
	RPL_WHOWASUSER = "314",
	///
	RPL_ENDOFWHO = "315",
	///
	RPL_WHOISIDLE = "317",
	///
	RPL_ENDOFWHOIS = "318",
	///
	RPL_WHOISCHANNELS = "319",
	///
	RPL_LISTSTART = "321",
	///
	RPL_LIST = "322",
	///
	RPL_LISTEND = "323",
	///
	RPL_CHANNELMODEIS = "324",
	///
	RPL_NOTOPIC = "331",
	///
	RPL_TOPIC = "332",
	///
	RPL_INVITING = "341",
	///
	RPL_SUMMONING = "342",
	///
	RPL_VERSION = "351",
	///
	RPL_WHOREPLY = "352",
	///
	RPL_NAMREPLY = "353",
	///
	RPL_LINKS = "364",
	///
	RPL_ENDOFLINKS = "365",
	///
	RPL_ENDOFNAMES = "366",
	///
	RPL_BANLIST = "367",
	///
	RPL_ENDOFBANLIST = "368",
	///
	RPL_ENDOFWHOWAS = "369",
	///
	RPL_INFO = "371",
	///
	RPL_MOTD = "372",
	///
	RPL_ENDOFINFO = "374",
	///
	RPL_MOTDSTART = "375",
	///
	RPL_ENDOFMOTD = "376",
	///
	RPL_YOUREOPER = "381",
	///
	RPL_REHASHING = "382",
	///
	RPL_TIME = "391",
	///
	RPL_USERSSTART = "392",
	///
	RPL_USERS = "393",
	///
	RPL_ENDOFUSERS = "394",
	///
	RPL_NOUSERS = "395",
	//RFC1459 Errors: https://tools.ietf.org/html/rfc1459#section-6.1
	///
	ERR_NOSUCHNICK = "401",
	///
	ERR_NOSUCHSERVER = "402",
	///
	ERR_NOSUCHCHANNEL = "403",
	///
	ERR_CANNOTSENDTOCHAN = "404",
	///
	ERR_TOOMANYCHANNELS = "405",
	///
	ERR_WASNOSUCHNICK = "406",
	///
	ERR_TOOMANYTARGETS = "407",
	///
	ERR_NOORIGIN = "409",
	///
	ERR_NORECIPIENT = "411",
	///
	ERR_NOTEXTTOSEND = "412",
	///
	ERR_NOTOPLEVEL = "413",
	///
	ERR_WILDTOPLEVEL = "414",
	///
	ERR_UNKNOWNCOMMAND = "421",
	///
	ERR_NOMOTD = "422",
	///
	ERR_NOADMININFO = "423",
	///
	ERR_FILEERROR = "424",
	///
	ERR_NONICKNAMEGIVEN = "431",
	///
	ERR_ERRONEUSNICKNAME = "432",
	///
	ERR_NICKNAMEINUSE = "433",
	///
	ERR_NICKCOLLISION = "436",
	///
	ERR_USERNOTINCHANNEL = "441",
	///
	ERR_NOTONCHANNEL = "442",
	///
	ERR_USERONCHANNEL = "443",
	///
	ERR_NOLOGIN = "444",
	///
	ERR_SUMMONDISABLED = "445",
	///
	ERR_USERSDISABLED = "446",
	///
	ERR_NOTREGISTERED = "451",
	///
	ERR_NEEDMOREPARAMS = "461",
	///
	ERR_ALREADYREGISTRED = "462",
	///
	ERR_NOPERMFORHOST = "463",
	///
	ERR_PASSWDMISMATCH = "464",
	///
	ERR_YOUREBANNEDCREEP = "465",
	///
	ERR_KEYSET = "467",
	///
	ERR_CHANNELISFULL = "471",
	///
	ERR_UNKNOWNMODE = "472",
	///
	ERR_INVITEONLYCHAN = "473",
	///
	ERR_BANNEDFROMCHAN = "474",
	///
	ERR_BADCHANNELKEY = "475",
	///
	ERR_NOPRIVILEGES = "481",
	///
	ERR_CHANOPRIVSNEEDED = "482",
	///
	ERR_CANTKILLSERVER = "483",
	///
	ERR_NOOPERHOST = "491",
	///
	ERR_UMODEUNKNOWNFLAG = "501",
	///
	ERR_USERSDONTMATCH = "502",
	//RFC1459 Reserved: https://tools.ietf.org/html/rfc1459#section-6.3
	//Obsolete or reserved for "future use"
	///
	RPL_STATSQLINE = "217",
	///
	RPL_SERVICEINFO = "231",
	///
	RPL_ENDOFSERVICES = "232",
	///
	RPL_SERVICE = "233",
	///
	RPL_WHOISCHANOP = "316",
	///
	RPL_KILLDONE = "361",
	///
	RPL_CLOSING = "362",
	///
	RPL_CLOSEEND = "363",
	///
	RPL_INFOSTART = "373",
	///
	RPL_MYPORTIS = "384",
	///
	ERR_NOSERVICEHOST = "492",
	//RFC2812 Command responses: https://tools.ietf.org/html/rfc2812#section-5.1
	///
	RPL_WELCOME = "001",
	///
	RPL_YOURHOST = "002",
	///
	RPL_CREATED = "003",
	///
	RPL_MYINFO = "004",
	///
	RPL_BOUNCE = "005",
	///
	RPL_TRACESERVICE = "207",
	///
	RPL_TRACECLASS = "209",
	///
	RPL_SERVLIST = "234",
	///
	RPL_SERVLISTEND = "235",
	///
	RPL_TRACEEND = "262",
	///
	RPL_TRYAGAIN = "263",
	///
	RPL_UNIQOPIS = "325",
	///
	RPL_INVITELIST = "346",
	///
	RPL_ENDOFINVITELIST = "347",
	///
	RPL_EXCEPTLIST = "348",
	///
	RPL_ENDOFEXCEPTLIST = "349",
	//RFC2812 Errors: https://tools.ietf.org/html/rfc2812#section-5.2
	///
	ERR_NOSUCHSERVICE = "408",
	///
	ERR_BADMASK = "415",
	///
	ERR_TOOMANYMATCHES = "416", //Errata
	///
	ERR_UNAVAILRESOURCE = "437",
	///
	ERR_YOUWILLBEBANNED = "466",
	///
	ERR_BADCHANMASK = "476",
	///
	ERR_NOCHANMODES = "477",
	///
	ERR_BANLISTFULL = "478",
	///
	ERR_RESTRICTED = "484",
	///
	ERR_UNIQOPPRIVSNEEDED = "485",
	//RFC2812 Reserved: https://tools.ietf.org/html/rfc2812#section-5.3
	///
	RPL_STATSVLINE = "240",
	///
	RPL_STATSSLINE = "245", //244 in original doc, 245 in errata
	///
	RPL_STATSPING = "246",
	///
	RPL_STATSBLINE = "247",
	///
	RPL_STATSDLINE = "250",
	//Monitor: http://ircv3.net/specs/core/monitor-3.2.html
	///
	RPL_MONONLINE = "730",
	///
	RPL_MONOFFLINE = "731",
	///
	RPL_MONLIST = "732",
	///
	RPL_ENDOFMONLIST = "733",
	///
	ERR_MONLISTFULL = "734",
	//Metadata: http://ircv3.net/specs/core/metadata-3.2.html
	///
	RPL_WHOISKEYVALUE = "760",
	///
	RPL_KEYVALUE = "761",
	///
	RPL_METADATAEND = "762",
	///
	ERR_METADATALIMIT = "764",
	///
	ERR_TARGETINVALID = "765",
	///
	ERR_NOMATCHINGKEY = "766",
	///
	ERR_KEYINVALID = "767",
	///
	ERR_KEYNOTSET = "768",
	///
	ERR_KEYNOPERMISSION = "769",
	//SASL: http://ircv3.net/specs/extensions/sasl-3.1.html
	///
	RPL_LOGGEDIN = "900",
	///
	RPL_LOGGEDOUT = "901",
	///
	ERR_NICKLOCKED = "902",
	///
	RPL_SASLSUCCESS = "903",
	///
	ERR_SASLFAIL = "904",
	///
	ERR_SASLTOOLONG = "905",
	///
	ERR_SASLABORTED = "906",
	///
	ERR_SASLALREADY = "907",
	///
	RPL_SASLMECHS = "908",
	//STARTTLS: http://ircv3.net/specs/extensions/tls-3.1.html
	///
	RPL_STARTTLS = "670",
	///
	ERR_STARTTLS = "691",
	//IRCX: http://tools.ietf.org/id/draft-pfenning-irc-extensions-04.txt
	//Pretty uncommon, but included for completeness
	///
	IRCRPL_IRCX = "800",
	///
	IRCRPL_ACCESSADD = "801",
	///
	IRCRPL_ACCESSDELETE = "802",
	///
	IRCRPL_ACCESSSTART = "803",
	///
	IRCRPL_ACCESSLIST = "804",
	///
	IRCRPL_ACCESSEND = "805",
	///
	IRCRPL_EVENTADD = "806",
	///
	IRCRPL_EVENTDEL = "807",
	///
	IRCRPL_EVENTSTART = "808",
	///
	IRCRPL_EVENTLIST = "809",
	///
	IRCRPL_EVENTEND = "810",
	///
	IRCRPL_LISTXSTART = "811",
	///
	IRCRPL_LISTXLIST = "812",
	///
	IRCRPL_LISTXPICS = "813",
	///
	IRCRPL_LISTXTRUNC = "816",
	///
	IRCRPL_LISTXEND = "817",
	///
	IRCRPL_PROPLIST = "818",
	///
	IRCRPL_PROPEND = "819",
	///
	IRCERR_BADCOMMAND = "900",
	///
	IRCERR_TOOMANYARGUMENTS = "901",
	///
	IRCERR_BADFUNCTION = "902",
	///
	IRCERR_BADLEVEL = "903",
	///
	IRCERR_BADTAG = "904",
	///
	IRCERR_BADPROPERTY = "905",
	///
	IRCERR_BADVALUE = "906",
	///
	IRCERR_RESOURCE = "907",
	///
	IRCERR_SECURITY = "908",
	///
	IRCERR_ALREADYAUTHENTICATED = "909",
	///
	IRCERR_AUTHENTICATIONFAILED = "910",
	///
	IRCERR_AUTHENTICATIONSUSPENDED = "911",
	///
	IRCERR_UNKNOWNPACKAGE = "912",
	///
	IRCERR_NOACCESS = "913",
	///
	IRCERR_DUPACCESS = "914",
	///
	IRCERR_MISACCESS = "915",
	///
	IRCERR_TOOMANYACCESSES = "916",
	///
	IRCERR_EVENTDUP = "918",
	///
	IRCERR_EVENTMIS = "919",
	///
	IRCERR_NOSUCHEVENT = "920",
	///
	IRCERR_TOOMANYEVENTS = "921",
	///
	IRCERR_NOWHISPER = "923",
	///
	IRCERR_NOSUCHOBJECT = "924",
	///
	IRCERR_NOTSUPPORTED = "925",
	///
	IRCERR_CHANNELEXIST = "926",
	///
	IRCERR_ALREADYONCHANNEL = "927",
	///
	IRCERR_UNKNOWNERROR = "999",
	//WATCH: https://github.com/grawity/irc-docs/blob/master/client/draft-meglio-irc-watch-00.txt
	///
	RPL_GONEAWAY = "598",
	///
	RPL_NOTAWAY = "599",
	///
	RPL_LOGON = "600",
	///
	RPL_LOGOFF = "601",
	///
	RPL_WATCHOFF = "602",
	///
	RPL_WATCHSTAT = "603",
	///
	RPL_NOWON = "604",
	///
	RPL_NOWOFF = "605",
	///
	RPL_WATCHLIST = "606",
	///
	RPL_ENDOFWATCHLIST = "607",
	///
	RPL_CLEARWATCH = "608",
	///
	RPL_NOWISAWAY = "609",
	//Misc
	///
	RPL_TEXT = "304",
	//Unknown origin, but in use
	///
	RPL_YOURID = "042",
	///
	RPL_LOCALUSERS = "265",
	///
	RPL_GLOBALUSERS = "266",
	///
	RPL_TOPICWHOTIME = "333",
	///
	RPL_HOSTHIDDEN = "396",
	//ISUPPORT: http://www.irc.org/tech_docs/draft-brocklesby-irc-isupport-03.txt
	///
	RPL_ISUPPORT = "005"
}
alias noInformationNumerics = AliasSeq!(
	Numeric.RPL_WELCOME,
	Numeric.RPL_YOURHOST,
	Numeric.RPL_CREATED,

	Numeric.RPL_YOURID,
	Numeric.RPL_LOCALUSERS,
	Numeric.RPL_GLOBALUSERS,
	Numeric.RPL_HOSTHIDDEN,

	listEndNumerics,
	listStartNumerics
);
alias listStartNumerics =AliasSeq!(
	Numeric.RPL_LISTSTART
);
alias listEndNumerics =AliasSeq!(
	Numeric.RPL_LISTEND,
	Numeric.RPL_ENDOFNAMES,
	Numeric.RPL_ENDOFMONLIST
);
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