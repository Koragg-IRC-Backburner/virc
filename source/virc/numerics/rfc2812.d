/++
+
+/
module virc.numerics.rfc2812;

import std.range : ElementType;

import virc.numerics.definitions;
/++
+ 004 RPL_MYINFO response.
+/
struct MyInfo {
	import virc.common : User;
	import virc.numerics.magicparser : Optional;
	User me;
	///Server name. Typically a valid hostname, but not necessarily.
	string name;
	///Version string of the software run by server.
	string version_;
	///Modes that can be set on users.
	string userModes;
	///Modes that can be set on channels.
	string channelModes;
	/++
	+ Modes that can be set on channels that have parameters. If non-empty, it is
	+ assumed that the modes in channelModes do not have parameters.
	+/
	@Optional string channelModesWithParams;
	/++
	+ Modes that can be set on users that have parameters. If non-empty, it is
	+ assumed that the modes in userModes do not have parameters.
	+/
	@Optional string userModesWithParams;
	///Modes that can be set on servers.
	@Optional string serverModes;
	/++
	+ Modes that can be set on servers that have parameters. If non-empty, it is
	+ assumed that the modes in serverModes do not have parameters.
	+/
	@Optional string serverModesWithParams;
}
/++
+
+/
//004 <username> <server_name> <version> <user_modes> <chan_modes> [<channel_modes_with_params> <user_modes_with_params> <server_modes> <server_modes_with_params>]
auto parseNumeric(Numeric numeric : Numeric.RPL_MYINFO, T)(T input) {
	import virc.numerics.magicparser : autoParse;
	return autoParse!MyInfo(input);
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
	{
		immutable info = parseNumeric!(Numeric.RPL_MYINFO)(only("someone", "localhost", "IRCd-2.0", "BGHIRSWcdgikorswx", "ABCDFGIJKLMNOPQRSTYabcefghijklmnopqrstuvz", "FIJLYabefghjkloqv", "q", "w", "x"));
		assert(info.name == "localhost");
		assert(info.version_ == "IRCd-2.0");
		assert(info.userModes == "BGHIRSWcdgikorswx");
		assert(info.userModesWithParams == "q");
		assert(info.channelModes == "ABCDFGIJKLMNOPQRSTYabcefghijklmnopqrstuvz");
		assert(info.channelModesWithParams == "FIJLYabefghjkloqv");
		assert(info.serverModes == "w");
		assert(info.serverModesWithParams == "x");
	}
	{
		immutable info = parseNumeric!(Numeric.RPL_MYINFO)(only("someone", "localhost", "IRCd-2.0", "BGHIRSWcdgikorswx ABCDFGIJKLMNOPQRSTYabcefghijklmnopqrstuvz FIJLYabefghjkloqv"));
		assert(info.isNull);
	}
}
struct RPL_TraceService {
	import virc.common : User;
	User me;
	string service;
	string class_;
	string name;
	string type;
	string activeType;
}
/++
+ Parser for RPL_TRACESERVICE.
+
+ Format is `207 <client> Service <class> <name> <type> <active_type>`
+/
auto parseNumeric(Numeric numeric : Numeric.RPL_TRACESERVICE, T)(T input) if (is(ElementType!T : string)) {
	import virc.numerics.magicparser : autoParse;
	return autoParse!RPL_TraceService(input);
}
///
@safe pure @nogc nothrow unittest {
	import std.range : only, takeNone;
	//Need real world examples... No idea what these will really look like
	{
		immutable trace = parseNumeric!(Numeric.RPL_TRACESERVICE)(only("someone", "Service", "classy", "fred", "something", "no_idea"));
		assert(trace.class_ == "classy");
		assert(trace.name == "fred");
		assert(trace.type == "something");
		assert(trace.activeType == "no_idea");
	}
	{
		immutable badTrace = parseNumeric!(Numeric.RPL_TRACESERVICE)(takeNone!(string[]));
		assert(badTrace.isNull);
	}
	{
		immutable badTrace = parseNumeric!(Numeric.RPL_TRACESERVICE)(only("someone"));
		assert(badTrace.isNull);
	}
	{
		immutable badTrace = parseNumeric!(Numeric.RPL_TRACESERVICE)(only("someone", "Service"));
		assert(badTrace.isNull);
	}
	{
		immutable badTrace = parseNumeric!(Numeric.RPL_TRACESERVICE)(only("someone", "Service", "classy"));
		assert(badTrace.isNull);
	}
	{
		immutable badTrace = parseNumeric!(Numeric.RPL_TRACESERVICE)(only("someone", "Service", "classy", "fred"));
		assert(badTrace.isNull);
	}
	{
		immutable badTrace = parseNumeric!(Numeric.RPL_TRACESERVICE)(only("someone", "Service", "classy", "fred", "something"));
		assert(badTrace.isNull);
	}
}
struct RPL_TraceClass {
	import virc.common : User;
	User me;
	string classConstant;
	string class_;
	string count;
}
/++
+ Parser for RPL_TRACECLASS.
+
+ Format is `209 <client> Class <class> <count>`
+/
auto parseNumeric(Numeric numeric : Numeric.RPL_TRACECLASS, T)(T input) {
	import virc.numerics.magicparser : autoParse;
	return autoParse!RPL_TraceClass(input);
}
///
@safe pure unittest {
	import std.range : only, takeNone;
	//Need real world examples... No idea what these will really look like
	{
		immutable trace = parseNumeric!(Numeric.RPL_TRACECLASS)(only("someone", "CLASS", "classy", "238525813"));
		assert(trace.class_ == "classy");
		assert(trace.count == "238525813");
	}
	{
		immutable badTrace = parseNumeric!(Numeric.RPL_TRACECLASS)(takeNone!(string[]));
		assert(badTrace.isNull);
	}
	{
		immutable badTrace = parseNumeric!(Numeric.RPL_TRACECLASS)(only("someone"));
		assert(badTrace.isNull);
	}
	{
		immutable badTrace = parseNumeric!(Numeric.RPL_TRACECLASS)(only("someone", "Class"));
		assert(badTrace.isNull);
	}
	{
		immutable badTrace = parseNumeric!(Numeric.RPL_TRACECLASS)(only("someone", "Class", "classy"));
		assert(badTrace.isNull);
	}
}