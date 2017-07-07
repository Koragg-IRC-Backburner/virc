/++
+ Module for IRCv3 core features.
+/
module virc.ircv3;

/++
+
+/
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

/++
+
+/
enum CapabilityServerSubcommands {
	ls = "LS",
	acknowledge = "ACK",
	notAcknowledge = "NAK",
	list = "LIST",
	new_ = "NEW",
	delete_ = "DEL"
}

/++
+
+/
enum CapabilityClientSubcommands {
	ls = "LS",
	list = "LIST",
	request = "REQ",
	end = "END"
}

/++
+
+/
struct Capability {
	///
	string name;
	///
	bool isVendorSpecific;
	///
	bool isSticky;
	///
	bool isDisabled;
	///
	bool isAcked;
	///
	string value;

	alias name this;

	@disable this();

	///
	this(string str) @safe pure @nogc {
		import std.algorithm.comparison : among;
		import std.algorithm.searching : canFind, findSplit;
		import std.range : empty, front, popFront;
		import std.utf : byCodeUnit;
		assert(!str.empty);
		auto prefix = str.byCodeUnit.front;
		switch (prefix) {
			case '~':
				isAcked = true;
				break;
			case '=':
				isSticky = true;
				break;
			case '-':
				isDisabled = true;
				break;
			default:
				break;
		}
		if (prefix.among('~', '=', '-')) {
			str.popFront();
		}
		auto split = str.findSplit("=");
		name = split[0];
		value = split[2];
		isVendorSpecific = name.byCodeUnit.canFind('/');
	}
	///
	string toString() const pure @safe {
		import std.range : empty;
		return name~(value.empty ? "" : "=")~value;
	}
}
///
@safe pure @nogc unittest {
	{
		auto cap = Capability("~account-notify");
		assert(cap.name == "account-notify");
		assert(cap.isAcked);
	}
	{
		auto cap = Capability("=account-notify");
		assert(cap.name == "account-notify");
		assert(cap.isSticky);
	}
	{
		auto cap = Capability("-account-notify");
		assert(cap.name == "account-notify");
		assert(cap.isDisabled);
	}
	{
		auto cap = Capability("example.com/cap");
		assert(cap.name == "example.com/cap");
		assert(cap.isVendorSpecific);
	}
	{
		auto cap = Capability("cap=value");
		assert(cap.name == "cap");
		assert(cap.value == "value");
	}
	{
		auto cap = Capability("cap=value/notvendor");
		assert(cap.name == "cap");
		assert(cap.value == "value/notvendor");
		assert(!cap.isVendorSpecific);
	}
}
@system pure unittest {
	import core.exception : AssertError;
	import std.exception : assertThrown;
	{
		assertThrown!AssertError(Capability(""));
	}
}
