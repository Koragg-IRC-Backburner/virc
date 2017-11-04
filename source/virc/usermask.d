/++
+ IRC user masks.
+/
module virc.usermask;

import std.algorithm : findSplit;
import std.range;
import std.typecons : Nullable;

/++
+ IRC user masks are generally in the form nick!ident@hostname. This struct
+ exists for easy separation and manipulation of each piece of the mask. This
+ also accepts cases where the ident and host are not present.
+/
struct UserMask {
	///
	string nickname;
	///
	Nullable!string ident;
	///
	Nullable!string host;
	///
	this(string maskString) @safe pure nothrow @nogc {
		auto split = maskString.findSplit("!");
		nickname = split[0];
		if ((split[1] == "!") && (split[2].length > 0)) {
			auto split2 = split[2].findSplit("@");
			ident = split2[0];
			if (split2[1] == "@") {
				host = split2[2];
			}
		} else {
			auto split2 = maskString.findSplit("@");
			nickname = split2[0];
			if (split2[1] == "@") {
				host = split2[2];
			}
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
	with (UserMask("user!id")) {
		assert(nickname == "user");
		assert(ident == "id");
		assert(host.isNull);
	}
	with (UserMask("user@example.net")) {
		assert(nickname == "user");
		assert(ident.isNull);
		assert(host == "example.net");
	}
}
@safe pure unittest {
	import std.conv : text;
	{
		UserMask mask;
		mask.nickname = "Nick";
		assert(mask.text == "Nick");
	}
	{
		UserMask mask;
		mask.nickname = "Nick";
		mask.ident = "user";
		mask.host = "domain";
		assert(mask.text == "Nick!user@domain");
	}
}