import std.stdio;
import std.range;
import virc;
import vibe.stream.wrapper;
import vibe.stream.stdio;
import vibe.d;

mixin template Bot() {
	import std.stdio : writefln;
	void onMessage(const User user, const Target target, const Message msg, const MessageMetadata metadata) {
		if (msg.isCTCP) {
			if (msg.ctcpCommand == "ACTION") {
				writefln("<%s> * %s %s", metadata.time, user, msg.ctcpArgs);
			} if (msg.ctcpCommand == "RAW") {
				write(msg.ctcpArgs);
			} else {
				writefln("<%s> [%s:%s] %s", metadata.time, user, msg.ctcpCommand, msg.ctcpArgs);
			}
		} else if (!msg.isReplyable) {
			writefln("<%s> -%s- %s", metadata.time, user.nickname, msg.msg);
		} else if (msg.isReplyable) {
			writefln("<%s> <%s:%s> %s", metadata.time, user.nickname, target, msg.msg);
		}
	}

	void onJoin(const User user, const Channel channel, const MessageMetadata metadata) @safe {
		writefln("<%s> *** %s joined %s", metadata.time, user, channel);
	}

	void onPart(const User user, const Channel channel, const string message, const MessageMetadata metadata) @safe {
		writefln("<%s> *** %s parted %s: %s", metadata.time, user, channel, message);
	}

	void onQuit(const User user, const string message, const MessageMetadata metadata) @safe {
		writefln("<%s> *** %s quit IRC: %s", metadata.time, user, message);
	}

	void onNick(const User user, const User newname, const MessageMetadata metadata) @safe {
		writefln("<%s> *** %s changed name to %s", metadata.time, user, newname);
	}

	void onKick(const User user, const Channel channel, const User initiator, const string message, const MessageMetadata metadata) @safe {
		writefln("<%s> *** %s was kicked from %s by %s: %s", metadata.time, user, channel, initiator, message);
	}

	void onLogin(const User user, const MessageMetadata metadata) @safe {
		writefln("<%s> *** %s logged in", metadata.time, user);
	}

	void onLogout(const User user, const MessageMetadata metadata) @safe {
		writefln("<%s> *** %s logged out", metadata.time, user);
	}

	void onAway(const User user, const string message, const MessageMetadata metadata) @safe {
		writefln("<%s> *** %s is away: %s", metadata.time, user, message);
	}

	void onBack(const User user, const MessageMetadata metadata) @safe {
		writefln("<%s> *** %s is no longer away", metadata.time, user);
	}

	void onTopic(const User user, const Channel channel, const MessageMetadata metadata) @safe {
		writefln("<%s> *** %s changed topic on %s to %s", metadata.time, user, channel, channel.topic);
	}

	void onMode(const User user, const Target target, const ModeChange mode, const MessageMetadata metadata) @safe {
		writefln("<%s> *** %s changed modes on %s: %s", metadata.time, user, target, mode);
	}
	void onConnect() {
		join("#test");
	}
	void writeLine(string line) {
		write(line);
	}
}

void main() {
	import std.file : exists, readText;
	import std.json : JSON_TYPE, parseJSON;
	if (exists("settings.json")) {
		auto settings = readText("settings.json").parseJSON();
		auto conn = connectTCP(settings["address"].str, cast(ushort)settings["port"].integer);
		Stream stream;
		if (settings["ssl"].type == JSON_TYPE.TRUE) {
			auto sslctx = createTLSContext(TLSContextKind.client);
			sslctx.peerValidationMode = TLSPeerValidationMode.none;
			stream = createTLSStream(conn, sslctx);
		} else {
			stream = conn;
		}
		class Wrap {
			alias wrapped this;
			StreamOutputRange!Stream wrapped;
			this() {
				wrapped = streamOutputRange(stream);
			}
		}
		auto output = new Wrap;
		auto client = ircClient!Bot(output, NickInfo(settings["nickname"].str, settings["identd"].str, settings["real name"].str));

		void readIRC() {
			while(!stream.empty) {
				put(client, stream.readLine().idup);
			}
		}
		void readCLI() {
			auto standardInput = new StdinStream;
			while (true) {
				auto str = cast(string)readLine(standardInput);
				client.writeLine(str);
			}
		}
		runTask(&readIRC);
		runTask(&readCLI);
		runApplication();
	} else {
		stderr.writeln("No settings file found");
	}
}