module virc.ircmessage;


struct IRCMessage {
	string raw;
	private string tagString;
	private string nonTaggedString;
	string source;
	string verb;
	private string argString;

	this(string msg) @safe {
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
	auto tags() @safe {
		import virc.ircv3.tags : parseTagString;
		return parseTagString(tagString);
	}
	string toString() @safe {
		return raw;
	}
}

@safe unittest {
	import std.algorithm.comparison : equal;
	with(IRCMessage(":remote!foo@example.com PRIVMSG local :I like turtles.")) {
		assert(source == "remote!foo@example.com");
		assert(verb == "PRIVMSG");
		assert(args.equal(["local", "I like turtles."]));
		assert(tags.length == 0);
	}
	with(IRCMessage("@aaa=bbb;ccc;example.com/ddd=eee :nick!ident@host.com PRIVMSG me :Hello")) {
		assert(source == "nick!ident@host.com");
		assert(verb == "PRIVMSG");
		assert(args.equal(["me", "Hello"]));
		assert(tags["aaa"] == "bbb");
		assert(tags["ccc"] == "");
		assert(tags["example.com/ddd"] == "eee");
	}
}
