/++
+ Module for parsing ISUPPORT replies.
+/
module virc.numerics.isupport;

import virc.numerics.definitions;

/++
+
+/
enum ISupportToken {
	///
	accept = "ACCEPT",
	///
	awayLen = "AWAYLEN",
	///
	callerID = "CALLERID",
	///
	caseMapping = "CASEMAPPING",
	///
	chanLimit = "CHANLIMIT",
	///
	chanModes = "CHANMODES",
	///
	channelLen = "CHANNELLEN",
	///
	chanTypes = "CHANTYPES",
	///
	charSet = "CHARSET",
	///
	chIdLen = "CHIDLEN",
	///
	cNotice = "CNOTICE",
	///
	cPrivmsg = "CPRIVMSG",
	///
	deaf = "DEAF",
	///
	eList = "ELIST",
	///
	eSilence = "ESILENCE",
	///
	excepts = "EXCEPTS",
	///
	extBan = "EXTBAN",
	///
	fnc = "FNC",
	///
	idChan = "IDCHAN",
	///
	invEx = "INVEX",
	///
	kickLen = "KICKLEN",
	///
	knock = "KNOCK",
	///
	language = "LANGUAGE",
	///
	lineLen = "LINELEN",
	///
	map = "MAP",
	///
	maxBans = "MAXBANS",
	///
	maxChannels = "MAXCHANNELS",
	///
	maxList = "MAXLIST",
	///
	maxPara = "MAXPARA",
	///
	maxTargets = "MAXTARGETS",
	///
	metadata = "METADATA",
	///
	modes = "MODES",
	///
	monitor = "MONITOR",
	///
	namesX = "NAMESX",
	///
	network = "NETWORK",
	///
	nickLen = "NICKLEN",
	///
	noQuit = "NOQUIT",
	///
	operLog = "OPERLOG",
	///
	override_ = "OVERRIDE",
	///
	penalty = "PENALTY",
	///
	prefix = "PREFIX",
	///
	remove = "REMOVE",
	///
	rfc2812 = "RFC2812",
	///
	safeList = "SAFELIST",
	///
	secureList = "SECURELIST",
	///
	silence = "SILENCE",
	///
	ssl = "SSL",
	///
	startTLS = "STARTTLS",
	///
	statusMsg = "STATUSMSG",
	///
	std = "STD",
	///
	targMax = "TARGMAX",
	///
	topicLen = "TOPICLEN",
	///
	uhNames = "UHNAMES",
	///
	userIP = "USERIP",
	///
	userLen = "USERLEN",
	///
	vBanList = "VBANLIST",
	///
	vChans = "VCHANS",
	///
	wallChOps = "WALLCHOPS",
	///
	wallVoices = "WALLVOICES",
	///
	watch = "WATCH",
	///
	whoX = "WHOX"
}
/++
+
+/
class UnknownISupportTokenException : Exception {
	package this(string token, string file = __FILE__, size_t line = __LINE__) @safe pure {
		super("Unknown Token: "~ token, file, line);
	}
}
/++
+
+/
struct ISupport {
	import std.typecons : Nullable;
	import virc.casemapping : CaseMapping;
	import virc.modes : ModeType;
	///
	char[char] prefixes;
	///
	string channelTypes = "#&!+"; //RFC2811 specifies four channel types.
	///
	ModeType[char] channelModeTypes;
	///
	ulong maxModesPerCommand;
	///
	ulong[char] chanLimits;
	///
	ulong nickLength = 9;
	///
	ulong[char] maxList;
	///
	string network;
	///
	Nullable!char banExceptions;
	///
	Nullable!char inviteExceptions;
	///
	bool wAllChannelOps;
	///
	bool wAllChannelVoices;
	///
	string statusMessage;
	///
	CaseMapping caseMapping;
	///
	string extendedList;
	///
	ulong topicLength = 390;
	///
	ulong kickLength;
	///
	ulong userLength;
	///
	ulong channelLength = 200;
	///
	ulong[char] channelIDLengths;
	///
	Nullable!string standard;
	///
	Nullable!ulong silence;
	///
	bool extendedSilence;
	///
	bool rfc2812;
	///
	bool penalty;
	///
	bool forcedNickChanges;
	///
	bool safeList;
	///
	ulong awayLength = ulong.max;
	///
	bool noQuit;
	///
	bool userIP;
	///
	bool cPrivmsg;
	///
	bool cNotice;
	///
	ulong maxTargets;
	///
	bool knock;
	///
	bool virtualChannels;
	///
	ulong maximumWatches;
	///
	bool whoX;
	///
	Nullable!char callerID;
	///
	string[] languages;
	///
	ulong maxLanguages;
	///
	bool startTLS; //DANGEROUS!
	///
	string banExtensions;
	///
	bool logsOperCommands;
	///
	string sslServer;
	///
	bool userhostsInNames;
	///
	bool namesExtended;
	///
	bool secureList;
	///
	bool supportsRemove;
	///
	bool allowsOperOverride;
	///
	bool variableBanList;
	///
	bool supportsMap;
	///
	ulong maximumParameters = 12;
	///
	ulong lineLength = 512;
	///
	Nullable!char deaf;
	///
	ulong metadata = 0;
	///
	ulong monitorTargetLimit = 0;
	///
	ulong[string] targetMaxByCommand;
	///
	string charSet;
	///
	void insertToken(string token, Nullable!string val) @safe pure {
		import std.algorithm.iteration : splitter;
		import std.algorithm.searching : findSplit;
		import std.conv : parse, to;
		import std.meta : AliasSeq;
		import std.range : empty, popFront, zip;
		import std.string : toLower;
		import std.utf : byCodeUnit;
		string value;
		if (!val.isNull) {
			value = val.get;
		}
		bool isEnabled = !val.isNull;
		switch (cast(ISupportToken)token) {
			case ISupportToken.chanModes:
				if (isEnabled) {
					auto splitModes = value.splitter(",");
					foreach (modeType; AliasSeq!(ModeType.a, ModeType.b, ModeType.c, ModeType.d)) {
						foreach (modeChar; splitModes.front) {
							channelModeTypes[modeChar] = modeType;
						}
						splitModes.popFront();
					}
				} else {
					channelModeTypes = channelModeTypes.init;
				}
				break;
			case ISupportToken.prefix:
				auto split = value.findSplit(")");
				split[0].popFront();
				foreach (modeChar, prefix; zip(split[0].byCodeUnit, split[2].byCodeUnit)) {
					prefixes[modeChar] = prefix;
					if (modeChar !in channelModeTypes) {
						channelModeTypes[modeChar] = ModeType.d;
					}
				}
				break;
			case ISupportToken.chanTypes:
				channelTypes = value;
				break;
			case ISupportToken.wallChOps:
				wAllChannelOps = isEnabled;
				break;
			case ISupportToken.wallVoices:
				wAllChannelVoices = isEnabled;
				break;
			case ISupportToken.statusMsg:
				statusMessage = value;
				break;
			case ISupportToken.extBan:
				banExtensions = value;
				break;
			case ISupportToken.fnc:
				forcedNickChanges = isEnabled;
				break;
			case ISupportToken.userIP:
				userIP = isEnabled;
				break;
			case ISupportToken.cPrivmsg:
				cPrivmsg = isEnabled;
				break;
			case ISupportToken.cNotice:
				cNotice = isEnabled;
				break;
			case ISupportToken.knock:
				knock = isEnabled;
				break;
			case ISupportToken.vChans:
				virtualChannels = isEnabled;
				break;
			case ISupportToken.whoX:
				whoX = isEnabled;
				break;
			case ISupportToken.awayLen:
				try {
					awayLength = parse!ulong(value);
				} catch (Exception) {
					awayLength = ulong.max;
				}
				break;
			case ISupportToken.nickLen:
				nickLength = parse!ulong(value);
				break;
			case ISupportToken.lineLen:
				lineLength = parse!ulong(value);
				break;
			case ISupportToken.channelLen:
				channelLength = parse!ulong(value);
				break;
			case ISupportToken.kickLen:
				kickLength = parse!ulong(value);
				break;
			case ISupportToken.userLen:
				if (value == value.init) {
					userLength = ulong.max;
				} else {
					userLength = parse!ulong(value);
				}
				break;
			case ISupportToken.topicLen:
				if (value == "") {
					topicLength = ulong.max;
				} else {
					topicLength = parse!ulong(value);
				}
				break;
			case ISupportToken.maxBans:
				maxList['b'] = parse!ulong(value);
				break;
			case ISupportToken.modes:
				maxModesPerCommand = parse!ulong(value);
				break;
			case ISupportToken.watch:
				maximumWatches = parse!ulong(value);
				break;
			case ISupportToken.metadata:
				if (value == value.init) {
					metadata = ulong.max;
				} else {
					metadata = parse!ulong(value);
				}
				break;
			case ISupportToken.monitor:
				if (value == value.init) {
					monitorTargetLimit = ulong.max;
				} else {
					monitorTargetLimit = parse!ulong(value);
				}
				break;
			case ISupportToken.maxList:
				auto splitModes = value.splitter(",");
				foreach (listEntry; splitModes) {
					auto splitArgs = listEntry.findSplit(":");
					immutable limit = parse!ulong(splitArgs[2]);
					foreach (modeChar; splitArgs[0]) {
						maxList[modeChar] = limit;
					}
				}
				break;
			case ISupportToken.targMax:
				auto splitCmd = value.splitter(",");
				foreach (listEntry; splitCmd) {
					auto splitArgs = listEntry.findSplit(":");
					if (splitArgs[2].empty) {
						targetMaxByCommand[splitArgs[0]] = ulong.max;
					} else {
						immutable limit = parse!ulong(splitArgs[2]);
						targetMaxByCommand[splitArgs[0]] = limit;
					}
				}
				break;
			case ISupportToken.chanLimit:
				if (isEnabled) {
					auto splitPrefix = value.splitter(",");
					foreach (listEntry; splitPrefix) {
						auto splitArgs = listEntry.findSplit(":");
						if (splitArgs[1] != ":") {
							chanLimits = chanLimits.init;
							break;
						}
						try {
							immutable limit = parse!ulong(splitArgs[2]);
							foreach (prefix; splitArgs[0]) {
								chanLimits[prefix] = limit;
							}
						} catch (Exception) {
							if (splitArgs[2] == "") {
								foreach (prefix; splitArgs[0]) {
									chanLimits[prefix] = ulong.max;
								}
							} else {
								chanLimits = chanLimits.init;
								break;
							}
						}
					}
				} else {
					chanLimits = chanLimits.init;
				}
				break;
			case ISupportToken.maxTargets:
				maxTargets = parse!ulong(value);
				break;
			case ISupportToken.maxChannels:
				chanLimits['#'] = parse!ulong(value);
				break;
			case ISupportToken.maxPara:
				maximumParameters = parse!ulong(value);
				break;
			case ISupportToken.startTLS:
				startTLS = isEnabled;
				break;
			case ISupportToken.ssl:
				sslServer = value;
				break;
			case ISupportToken.operLog:
				logsOperCommands = isEnabled;
				break;
			case ISupportToken.silence:
				if (value.empty || !isEnabled) {
					silence.nullify();
				} else {
					silence = value.parse!ulong;
				}
				break;
			case ISupportToken.network:
				network = value;
				break;
			case ISupportToken.caseMapping:
				switch (value.toLower()) {
					case CaseMapping.rfc1459:
						caseMapping = CaseMapping.rfc1459;
						break;
					case CaseMapping.rfc3454:
						caseMapping = CaseMapping.rfc3454;
						break;
					case CaseMapping.strictRFC1459:
						caseMapping = CaseMapping.strictRFC1459;
						break;
					case CaseMapping.ascii:
						caseMapping = CaseMapping.ascii;
						break;
					default:
						caseMapping = CaseMapping.unknown;
						break;
				}
				break;
			case ISupportToken.charSet:
				//Has serious issues and has been removed from drafts
				//So we leave this one unparsed
				charSet = value;
				break;
			case ISupportToken.uhNames:
				userhostsInNames = isEnabled;
				break;
			case ISupportToken.namesX:
				userhostsInNames = isEnabled;
				break;
			case ISupportToken.invEx:
				inviteExceptions = value.byCodeUnit.front;
				break;
			case ISupportToken.excepts:
				banExceptions = value.byCodeUnit.front;
				break;
			case ISupportToken.callerID, ISupportToken.accept:
				//value is required, but not all implementations support it
				if (value == value.init) {
					callerID = 'g';
				} else {
					callerID = value.byCodeUnit.front;
				}
				break;
			case ISupportToken.deaf:
				if (value == value.init) {
					deaf = 'd';
				} else {
					deaf = value.byCodeUnit.front;
				}
				break;
			case ISupportToken.eList:
				extendedList = value;
				break;
			case ISupportToken.secureList:
				secureList = isEnabled;
				break;
			case ISupportToken.noQuit:
				noQuit = isEnabled;
				break;
			case ISupportToken.remove:
				supportsRemove = isEnabled;
				break;
			case ISupportToken.eSilence:
				extendedSilence = isEnabled;
				break;
			case ISupportToken.override_:
				allowsOperOverride = isEnabled;
				break;
			case ISupportToken.vBanList:
				variableBanList = isEnabled;
				break;
			case ISupportToken.map:
				supportsMap = isEnabled;
				break;
			case ISupportToken.safeList:
				safeList = isEnabled;
				break;
			case ISupportToken.chIdLen:
				channelIDLengths['!'] = parse!ulong(value);
				break;
			case ISupportToken.idChan:
				auto splitPrefix = value.splitter(",");
				foreach (listEntry; splitPrefix) {
					auto splitArgs = listEntry.findSplit(":");
					immutable limit = parse!ulong(splitArgs[2]);
					foreach (prefix; splitArgs[0]) {
						channelIDLengths[prefix] = limit;
					}
				}
				break;
			case ISupportToken.std:
				standard = value;
				break;
			case ISupportToken.rfc2812:
				rfc2812 = isEnabled;
				break;
			case ISupportToken.penalty:
				penalty = isEnabled;
				break;
			case ISupportToken.language:
				auto splitLangs = value.splitter(",");
				maxLanguages = to!ulong(splitLangs.front);
				splitLangs.popFront();
				foreach (lang; splitLangs)
					languages ~= lang;
				break;
			default: throw new UnknownISupportTokenException(token);
		}
	}
}
///
@safe pure unittest {
	import std.typecons : Nullable;
	import virc.casemapping : CaseMapping;
	auto isupport = ISupport();
	{
		assert(isupport.awayLength == ulong.max);
		isupport.insertToken("AWAYLEN", Nullable!string("8"));
		assert(isupport.awayLength == 8);
		isupport.insertToken("AWAYLEN", Nullable!string.init);
		assert(isupport.awayLength == ulong.max);
	}
	{
		assert(isupport.callerID.isNull);
		isupport.insertToken("CALLERID", Nullable!string("h"));
		assert(isupport.callerID == 'h');
		isupport.insertToken("CALLERID", Nullable!string.init);
		assert(isupport.callerID == 'g');
	}
	{
		assert(isupport.caseMapping == CaseMapping.unknown);
		isupport.insertToken("CASEMAPPING", Nullable!string("rfc1459"));
		assert(isupport.caseMapping == CaseMapping.rfc1459);
		isupport.insertToken("CASEMAPPING", Nullable!string("ascii"));
		assert(isupport.caseMapping == CaseMapping.ascii);
		isupport.insertToken("CASEMAPPING", Nullable!string("rfc3454"));
		assert(isupport.caseMapping == CaseMapping.rfc3454);
		isupport.insertToken("CASEMAPPING", Nullable!string("strict-rfc1459"));
		assert(isupport.caseMapping == CaseMapping.strictRFC1459);
		isupport.insertToken("CASEMAPPING", Nullable!string.init);
		assert(isupport.caseMapping == CaseMapping.unknown);
	}
	{
		assert(isupport.chanLimits.length == 0);
		isupport.insertToken("CHANLIMIT", Nullable!string("#+:25,&:"));
		assert(isupport.chanLimits['#'] == 25);
		assert(isupport.chanLimits['+'] == 25);
		assert(isupport.chanLimits['&'] == ulong.max);
		isupport.insertToken("CHANLIMIT", Nullable!string.init);
		assert(isupport.chanLimits.length == 0);
		isupport.insertToken("CHANLIMIT", Nullable!string("q"));
		assert(isupport.chanLimits.length == 0);
		isupport.insertToken("CHANLIMIT", Nullable!string("!:f"));
		assert(isupport.chanLimits.length == 0);
	}
}

/++
+
+/
void parseNumeric(Numeric numeric: Numeric.RPL_ISUPPORT, T)(T input, ref ISupport iSupport) {
	import std.algorithm : findSplit, skipOver;
	import std.typecons : Nullable;
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
/++
+
+/
auto parseNumeric(Numeric numeric: Numeric.RPL_ISUPPORT, T)(T input) {
	ISupport tmp;
	parseNumeric!numeric(input, tmp);
	return tmp;
}
///
@safe pure /+nothrow @nogc+/ unittest { //Numeric.RPL_ISUPPORT
	import std.exception : assertNotThrown, assertThrown;
	import virc.ircsplitter : IRCSplitter;
	import virc.modes : ModeType;
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