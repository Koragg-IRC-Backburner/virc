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
		const isEnabled = !val.isNull;
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
	private void insertToken(TokenPair pair) pure @safe {
		insertToken(pair.key, pair.value);
	}
}
///
@safe pure unittest {
	import virc.casemapping : CaseMapping;
	import virc.modes : ModeType;
	auto isupport = ISupport();
	{
		assert(isupport.awayLength == ulong.max);
		isupport.insertToken(keyValuePair("AWAYLEN=8"));
		assert(isupport.awayLength == 8);
		isupport.insertToken(keyValuePair("AWAYLEN="));
		assert(isupport.awayLength == ulong.max);
		isupport.insertToken(keyValuePair("AWAYLEN=8"));
		assert(isupport.awayLength == 8);
		isupport.insertToken(keyValuePair("-AWAYLEN"));
		assert(isupport.awayLength == ulong.max);
	}
	{
		assert(isupport.callerID.isNull);
		isupport.insertToken(keyValuePair("CALLERID=h"));
		assert(isupport.callerID == 'h');
		isupport.insertToken(keyValuePair("CALLERID"));
		assert(isupport.callerID == 'g');
		//isupport.insertToken(keyValuePair("CALLERID"));
		//assert(isupport.callerID.isNull);
	}
	{
		assert(isupport.caseMapping == CaseMapping.unknown);
		isupport.insertToken(keyValuePair("CASEMAPPING=rfc1459"));
		assert(isupport.caseMapping == CaseMapping.rfc1459);
		isupport.insertToken(keyValuePair("CASEMAPPING=ascii"));
		assert(isupport.caseMapping == CaseMapping.ascii);
		isupport.insertToken(keyValuePair("CASEMAPPING=rfc3454"));
		assert(isupport.caseMapping == CaseMapping.rfc3454);
		isupport.insertToken(keyValuePair("CASEMAPPING=strict-rfc1459"));
		assert(isupport.caseMapping == CaseMapping.strictRFC1459);
		isupport.insertToken(keyValuePair("-CASEMAPPING"));
		assert(isupport.caseMapping == CaseMapping.unknown);
		isupport.insertToken(keyValuePair("CASEMAPPING=something"));
		assert(isupport.caseMapping == CaseMapping.unknown);
	}
	{
		assert(isupport.chanLimits.length == 0);
		isupport.insertToken(keyValuePair("CHANLIMIT=#+:25,&:"));
		assert(isupport.chanLimits['#'] == 25);
		assert(isupport.chanLimits['+'] == 25);
		assert(isupport.chanLimits['&'] == ulong.max);
		isupport.insertToken(keyValuePair("-CHANLIMIT"));
		assert(isupport.chanLimits.length == 0);
		isupport.insertToken(keyValuePair("CHANLIMIT=q"));
		assert(isupport.chanLimits.length == 0);
		isupport.insertToken(keyValuePair("CHANLIMIT=!:f"));
		assert(isupport.chanLimits.length == 0);
	}
	{
		assert(isupport.channelModeTypes.length == 0);
		isupport.insertToken(keyValuePair("CHANMODES=b,k,l,imnpst"));
		assert(isupport.channelModeTypes['b'] == ModeType.a);
		assert(isupport.channelModeTypes['k'] == ModeType.b);
		assert(isupport.channelModeTypes['l'] == ModeType.c);
		assert(isupport.channelModeTypes['i'] == ModeType.d);
		assert(isupport.channelModeTypes['t'] == ModeType.d);
		isupport.insertToken(keyValuePair("CHANMODES=beI,k,l,BCMNORScimnpstz"));
		assert(isupport.channelModeTypes['e'] == ModeType.a);
		isupport.insertToken(keyValuePair("CHANMODES"));
		assert(isupport.channelModeTypes.length == 0);
		isupport.insertToken(keyValuePair("CHANMODES=w,,,"));
		assert(isupport.channelModeTypes['w'] == ModeType.a);
		assert('b' !in isupport.channelModeTypes);
		isupport.insertToken(keyValuePair("-CHANMODES"));
		assert(isupport.channelModeTypes.length == 0);
	}
	{
		assert(isupport.channelLength == 200);
		isupport.insertToken(keyValuePair("CHANNELLEN=50"));
		assert(isupport.channelLength == 50);
		isupport.insertToken(keyValuePair("CHANNELLEN="));
		assert(isupport.channelLength == ulong.max);
		isupport.insertToken(keyValuePair("-CHANNELLEN"));
		assert(isupport.channelLength == 200);
	}
	{
		assert(isupport.channelTypes == "#&!+");
		isupport.insertToken(keyValuePair("CHANTYPES=&#"));
		assert(isupport.channelTypes == "&#");
		isupport.insertToken(keyValuePair("CHANTYPES"));
		assert(isupport.channelTypes == "");
		isupport.insertToken(keyValuePair("-CHANTYPES"));
		assert(isupport.channelTypes == "#&!+");
	}
	{
		assert(isupport.charSet == "");
		isupport.insertToken(keyValuePair("CHARSET=ascii"));
		assert(isupport.charSet == "ascii");
		isupport.insertToken(keyValuePair("CHARSET"));
		assert(isupport.charSet == "");
		isupport.insertToken(keyValuePair("-CHARSET"));
		assert(isupport.charSet == "");
	}
	{
		assert(!isupport.cNotice);
		isupport.insertToken(keyValuePair("CNOTICE"));
		assert(isupport.cNotice);
		isupport.insertToken(keyValuePair("-CNOTICE"));
		assert(!isupport.cNotice);
	}
	{
		assert(!isupport.cPrivmsg);
		isupport.insertToken(keyValuePair("CPRIVMSG"));
		assert(isupport.cPrivmsg);
		isupport.insertToken(keyValuePair("-CPRIVMSG"));
		assert(!isupport.cPrivmsg);
	}
	{
		assert(isupport.deaf.isNull);
		isupport.insertToken(keyValuePair("DEAF=D"));
		assert(isupport.deaf == 'D');
		isupport.insertToken(keyValuePair("DEAF"));
		assert(isupport.deaf == 'd');
		isupport.insertToken(keyValuePair("-DEAF"));
		assert(isupport.deaf.isNull);
	}
	{
		assert(isupport.extendedList == "");
		isupport.insertToken(keyValuePair("ELIST=CMNTU"));
		assert(isupport.extendedList == "CMNTU");
		isupport.insertToken(keyValuePair("-ELIST"));
		assert(isupport.extendedList == "");
	}
	{
		assert(isupport.banExceptions.isNull);
		isupport.insertToken(keyValuePair("EXCEPTS"));
		assert(isupport.banExceptions == 'e');
		isupport.insertToken(keyValuePair("EXCEPTS=f"));
		assert(isupport.banExceptions == 'f');
		isupport.insertToken(keyValuePair("EXCEPTS=e"));
		assert(isupport.banExceptions == 'e');
		isupport.insertToken(keyValuePair("-EXCEPTS"));
		assert(isupport.banExceptions.isNull);
	}
	{
		assert(isupport.banExtensions.isNull);
		isupport.insertToken(keyValuePair("EXTBAN=~,cqnr"));
		assert(isupport.banExtensions.prefix == '~');
		assert(isupport.banExtensions.banTypes == "cqnr");
		isupport.insertToken(keyValuePair("EXTBAN=,ABCNOQRSTUcjmprsz"));
		assert(isupport.banExtensions.prefix.isNull);
		assert(isupport.banExtensions.banTypes == "ABCNOQRSTUcjmprsz");
		isupport.insertToken(keyValuePair("EXTBAN=~,qjncrRa"));
		assert(isupport.banExtensions.prefix == '~');
		assert(isupport.banExtensions.banTypes == "qjncrRa");
		isupport.insertToken(keyValuePair("-EXTBAN"));
		assert(isupport.banExtensions.isNull);
	}
	{
		assert(isupport.forcedNickChanges == false);
		isupport.insertToken(keyValuePair("FNC"));
		assert(isupport.forcedNickChanges == true);
		isupport.insertToken(keyValuePair("-FNC"));
		assert(isupport.forcedNickChanges == false);
	}
}
/++
+ Parses an ISUPPORT token.
+/
private auto keyValuePair(string token) pure @safe {
	import std.algorithm : findSplit, skipOver;
	immutable isDisabled = token.skipOver('-');
	auto splitParams = token.findSplit("=");
	Nullable!string param;
	if (!isDisabled) {
		param = splitParams[2];
	}
	return TokenPair(splitParams[0], param);
}
/++
+
+/
void parseNumeric(Numeric numeric: Numeric.RPL_ISUPPORT, T)(T input, ref ISupport iSupport) {
	import std.typecons : Nullable;
	immutable username = input.front;
	input.popFront();
	while (!input.empty && !input.isColonParameter) {
		iSupport.insertToken(keyValuePair(input.front));
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
		assert(support.channelTypes == "#&!+");
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