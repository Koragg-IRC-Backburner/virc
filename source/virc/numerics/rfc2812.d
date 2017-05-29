/++
+
+/
module virc.numerics.rfc2812;

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