/++
+
+/
module virc.numerics.rfc2812;

import virc.numerics.definitions;
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