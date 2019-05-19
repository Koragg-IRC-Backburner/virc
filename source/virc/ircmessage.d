module virc.ircmessage;

import virc.ircv3.batch;

struct IRCMessage {
	string raw;
	private string tagString;
	private string nonTaggedString;
	string source;
	string verb;
	private string argString;
	BatchInformation batch;

	invariant() {
		import std.algorithm.searching : canFind;
		assert(!source.canFind(" "), "Source cannot contain spaces");
		assert(!verb.canFind(" "), "Verb cannot contain spaces");
	}

	this(string msg) @safe pure {
		import std.algorithm.iteration : splitter;
		import std.algorithm.searching : findSplit;
		import std.string : join;
		raw = msg;
		if (raw[0] == '@') {
			auto split = msg.findSplit(" ");
			assert(split, "Found nothing following tags");
			tagString = split[0][1..$];
			nonTaggedString = split[2];
		} else {
			nonTaggedString = msg;
		}
		auto split = nonTaggedString.splitter(" ");
		if (split.front[0] == ':') {
			source = split.front[1..$];
			split.popFront();
		}
		verb = split.front;
		split.popFront();
		argString = split.join(" ");
	}
	static IRCMessage fromClient(string str) @safe {
		return IRCMessage(str);
	}
	static IRCMessage fromServer(string str) @safe {
		return IRCMessage(str);
	}

	auto args() @safe {
		import virc.ircsplitter : IRCSplitter;
		return IRCSplitter(argString);
	}

	void args(string input) @safe {
		argString = ":"~input;
	}

	void args(string[] input) @safe {
		import std.algorithm.searching : canFind;
		import std.format : format;

		if (input.length == 0) {
			argString = "";
			return;
		}

		foreach (earlyArg; input[0..$-1]) {
			assert(!earlyArg.canFind(" "));
		}
		argString = format!"%-(%s %|%):%s"(input[0..$-1], input[$-1]);
	}
	auto tags() @safe {
		import virc.ircv3.tags : parseTagString;
		return parseTagString(tagString);
	}
	string toString() const @safe {
		string result;
		result.reserve(tagString.length + 2 + source.length + 2 + verb.length + 1 + argString.length + 1);
		if (tagString != "") {
			result ~= "@";
			result ~= tagString;
			result ~= " ";
		}
		if (source != "") {
			result ~= ":";
			result ~= source;
			result ~= " ";
		}
		result ~= verb;
		if (argString != "") {
			result ~= " ";
			result ~= argString;
		}
		return result;
	}
	bool opEquals(const IRCMessage other) const @safe pure {
		return ((this.tagString == other.tagString) && (this.source == other.source) && (this.verb == other.verb) && (this.argString == other.argString));
	}
}

@safe unittest {
	import std.algorithm.comparison : equal;
	with(IRCMessage(":remote!foo@example.com PRIVMSG local :I like turtles.")) {
		assert(source == "remote!foo@example.com");
		assert(verb == "PRIVMSG");
		assert(args.equal(["local", "I like turtles."]));
		assert(tags.length == 0);
		assert(toString() == ":remote!foo@example.com PRIVMSG local :I like turtles.");
	}
	with(IRCMessage("@aaa=bbb;ccc;example.com/ddd=eee :nick!ident@host.com PRIVMSG me :Hello")) {
		assert(source == "nick!ident@host.com");
		assert(verb == "PRIVMSG");
		assert(args.equal(["me", "Hello"]));
		assert(tags["aaa"] == "bbb");
		assert(tags["ccc"] == "");
		assert(tags["example.com/ddd"] == "eee");
		assert(toString() == "@aaa=bbb;ccc;example.com/ddd=eee :nick!ident@host.com PRIVMSG me :Hello");
	}
	{
		auto msg = IRCMessage();
		msg.source = "server";
		msg.verb = "HELLO";
		msg.args = "WORLD";
		assert(msg.toString() == ":server HELLO :WORLD");
	}
	{
		auto msg = IRCMessage();
		msg.source = "server";
		msg.verb = "HELLO";
		msg.args = string[].init;
		assert(msg.toString() == ":server HELLO");
	}
	{
		auto msg = IRCMessage();
		msg.source = "server";
		msg.verb = "HELLO";
		msg.args = ["WORLD"];
		assert(msg.toString() == ":server HELLO :WORLD");
	}
	{
		auto msg = IRCMessage();
		msg.source = "server";
		msg.verb = "HELLO";
		msg.args = ["WORLD", "!!!"];
		assert(msg.toString() == ":server HELLO WORLD :!!!");
	}
}
