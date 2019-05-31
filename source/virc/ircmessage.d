module virc.ircmessage;

import virc.common : User;
import virc.ircv3.batch;
import virc.ircv3.tags;

import std.typecons : Nullable;

struct IRCMessage {
	string raw;
	IRCTags tags;
	private string nonTaggedString;
	Nullable!User sourceUser;
	string verb;
	private string argString;
	BatchInformation batch;

	invariant() {
		import std.algorithm.searching : canFind;
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
			tags = IRCTags(split[0][1..$]);
			nonTaggedString = split[2];
		} else {
			nonTaggedString = msg;
		}
		auto split = nonTaggedString.splitter(" ");
		if (split.front[0] == ':') {
			sourceUser = User(split.front[1..$]);
			do {
				split.popFront();
			} while((split.front == "") && !split.empty);
		}
		verb = split.front;
		do {
			split.popFront();
		} while(!split.empty && (split.front == ""));
		argString = split.join(" ");
	}
	static IRCMessage fromClient(string str) @safe {
		return IRCMessage(str);
	}
	static IRCMessage fromServer(string str) @safe {
		return IRCMessage(str);
	}

	auto args() const @safe {
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
	string toString() const @safe {
		import std.conv : text;
		string result;
		auto tagString = tags.toString();
		auto source = sourceUser.text;
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
		return ((this.tags == other.tags) && (this.sourceUser == other.sourceUser) && (this.verb == other.verb) && (this.argString == other.argString));
	}
}

@safe unittest {
	import std.algorithm.comparison : equal;
	with(IRCMessage(":remote!foo@example.com PRIVMSG local :I like turtles.")) {
		assert(sourceUser == User("remote!foo@example.com"));
		assert(verb == "PRIVMSG");
		assert(args.equal(["local", "I like turtles."]));
		assert(tags.length == 0);
	}
	assert(IRCMessage(IRCMessage(":remote!foo@example.com PRIVMSG local :I like turtles.").toString()) == IRCMessage(":remote!foo@example.com PRIVMSG local :I like turtles."));
	with(IRCMessage("@aaa=bbb;ccc;example.com/ddd=eee :nick!ident@host.com PRIVMSG me :Hello")) {
		assert(sourceUser == User("nick!ident@host.com"));
		assert(verb == "PRIVMSG");
		assert(args.equal(["me", "Hello"]));
		assert(tags["aaa"] == "bbb");
		assert(tags["ccc"] == "");
		assert(tags["example.com/ddd"] == "eee");
	}
	assert(IRCMessage(IRCMessage("@aaa=bbb;ccc;example.com/ddd=eee :nick!ident@host.com PRIVMSG me :Hello").toString()) == IRCMessage("@aaa=bbb;ccc;example.com/ddd=eee :nick!ident@host.com PRIVMSG me :Hello"));
	{
		auto msg = IRCMessage();
		msg.sourceUser = User("server");
		msg.verb = "HELLO";
		msg.args = "WORLD";
		assert(msg.toString() == ":server HELLO :WORLD");
	}
	with(IRCMessage(":example.com                   PRIVMSG              local           :I like turtles.")) {
		assert(sourceUser == User("example.com"));
		assert(verb == "PRIVMSG");
		assert(args.equal(["local", "I like turtles."]));
		assert(tags.length == 0);
	}
	{
		auto msg = IRCMessage();
		msg.sourceUser = User("server");
		msg.verb = "HELLO";
		msg.args = string[].init;
		assert(msg.toString() == ":server HELLO");
	}
	{
		auto msg = IRCMessage();
		msg.sourceUser = User("server");
		msg.verb = "HELLO";
		msg.args = ["WORLD"];
		assert(msg.toString() == ":server HELLO :WORLD");
	}
	{
		auto msg = IRCMessage();
		msg.sourceUser = User("server");
		msg.verb = "HELLO";
		msg.args = ["WORLD", "!!!"];
		assert(msg.toString() == ":server HELLO WORLD :!!!");
	}
}
