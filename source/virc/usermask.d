module virc.usermask;

import std.algorithm : findSplit;
import std.range;
import std.typecons : Nullable;

struct UserMask {
	string nickname;
	Nullable!string ident;
	Nullable!string host;
	this(string maskString) @safe pure nothrow @nogc {
		auto split = maskString.findSplit("!");
		nickname = split[0];
		if (split[2].length > 0) {
			auto split2 = split[2].findSplit("@");
			ident = split2[0];
			host = split2[2];
		}
	}
	void toString(T)(T sink) const if (isOutputRange!(T, const(char))) {
    		put(sink, nickname);
    		if (!ident.isNull) {
    			put(sink, '!');
    			put(sink, ident);
    			assert(!host.isNull);
    		}
    		if (!host.isNull) {
    			put(sink, '@');
    			put(sink, host);
    		}
	}
}

@safe pure nothrow @nogc unittest {
	with (UserMask("localhost")) {
		assert(nickname == "localhost");
		assert(ident.isNull);
		assert(host.isNull);
	}
	with (UserMask("user!id@example.net")) {
		assert(nickname == "user");
		assert(ident == "id");
		assert(host == "example.net");
	}
	with (UserMask("user!id@example!!!.net")) {
		assert(nickname == "user");
		assert(ident == "id");
		assert(host == "example!!!.net");
	}
	with (UserMask("user!id@ex@mple!!!.net")) {
		assert(nickname == "user");
		assert(ident == "id");
		assert(host == "ex@mple!!!.net");
	}
	with (UserMask("user!id!@ex@mple!!!.net")) {
		assert(nickname == "user");
		assert(ident == "id!");
		assert(host == "ex@mple!!!.net");
	}
}