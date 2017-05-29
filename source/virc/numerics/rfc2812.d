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
	///Server name. Typically a valid hostname, but not necessarily.
	string name;
	///Version string of the software run by server.
	string version_;
	///Modes that can be set on users.
	string userModes;
	/++
	+ Modes that can be set on users that have parameters. If non-empty, it is
	+ assumed that the modes in userModes do not have parameters.
	+/
	string userModesWithParams;
	///Modes that can be set on channels.
	string channelModes;
	/++
	+ Modes that can be set on channels that have parameters. If non-empty, it is
	+ assumed that the modes in channelModes do not have parameters.
	+/
	string channelModesWithParams;
	///Modes that can be set on servers.
	string serverModes;
	/++
	+ Modes that can be set on servers that have parameters. If non-empty, it is
	+ assumed that the modes in serverModes do not have parameters.
	+/
	string serverModesWithParams;
}
/++
+
+/
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
/++
+ Parser for RPL_TRACESERVICE.
+
+ Format is `207 <client> Service <class> <name> <type> <active_type>`
+/
auto parseNumeric(Numeric numeric : Numeric.RPL_TRACESERVICE, T)(T input) if (is(ElementType!T : string)) {
	import std.range : empty, front, popFront;
	import std.typecons : Nullable, Tuple;
	Tuple!(string, "class_", string, "name", string, "type", string, "activeType") output;
	//Drop client token
	if (input.empty) {
		return Nullable!(typeof(output)).init;
	}
	input.popFront();
	//Drop Service token
	if (input.empty) {
		return Nullable!(typeof(output)).init;
	}
	input.popFront();


	if (input.empty) {
		return Nullable!(typeof(output)).init;
	}
	output.class_ = input.front;
	input.popFront();

	if (input.empty) {
		return Nullable!(typeof(output)).init;
	}
	output.name = input.front;
	input.popFront();

	if (input.empty) {
		return Nullable!(typeof(output)).init;
	}
	output.type = input.front;
	input.popFront();

	if (input.empty) {
		return Nullable!(typeof(output)).init;
	}
	output.activeType = input.front;
	return Nullable!(typeof(output))(output);
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
/++
+ Parser for RPL_TRACECLASS.
+
+ Format is `209 <client> Class <class> <count>`
+/
auto parseNumeric(Numeric numeric : Numeric.RPL_TRACECLASS, T)(T input) {
	import std.range : empty, front, popFront;
	import std.typecons : Nullable, Tuple;
	Tuple!(string, "class_", string, "count") output;
	if (input.empty) {
		return Nullable!(typeof(output)).init;
	}
	//Drop client token
	input.popFront();
	if (input.empty) {
		return Nullable!(typeof(output)).init;
	}
	//Drop Class token
	input.popFront();

	if (input.empty) {
		return Nullable!(typeof(output)).init;
	}
	output.class_ = input.front;
	input.popFront();

	if (input.empty) {
		return Nullable!(typeof(output)).init;
	}
	output.count = input.front;
	return Nullable!(typeof(output))(output);
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