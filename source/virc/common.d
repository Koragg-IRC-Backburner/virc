/++
+ Various bits common to different parts of IRC, such as channel and user
+ metadata.
+/
module virc.common;

import std.datetime : SysTime;
import std.range : isOutputRange, put;
import std.typecons : Nullable;

import virc.modes;
import virc.usermask;
/++
+ Metadata for an IRC channel.
+/
struct Channel {
	///
	string name;
	///
	ulong userCount;
	///
	Topic topic;
	///
	Mode[] modes;
	void toString(T)(T sink) const if (isOutputRange!(T, const(char))) {
		put(sink, name);
	}
}
/++
+ Channel topic metadata. A message is guaranteed, but the time and user
+ associated with setting it may not be present.
+/
struct Topic {
	///
	string message;
	///
	Nullable!SysTime time;
	///
	Nullable!User setBy;
	auto opEquals(const Topic b) const {
		return message == b.message;
	}
	///
	auto toHash() const {
		return message.hashOf;
	}
}
@system pure nothrow @nogc unittest {
	assert(Topic("Hello!").toHash == Topic("Hello!").toHash);
}
/++
+ User metadata. User's mask will always be present, but real name's presence
+ depends on the context. Account's presence depends on the server's
+ capabilities.
+/
struct User {
	///
	UserMask mask;
	///
	Nullable!string realName;
	///
	Nullable!string account;
	///
	this(string str) @safe pure nothrow @nogc {
		mask = UserMask(str);
	}
	///
	auto nickname() const {
		return mask.nickname;
	}
	///
	auto ident() const {
		return mask.ident;
	}
	///
	auto host() const  {
		return mask.host;
	}
	void toString(T)(T sink) const if (isOutputRange!(T, const(char))) {
		mask.toString(sink);
		if (!account.isNull) {
			put(sink, " (");
			put(sink, account);
			put(sink, ")");
		}
	}
	auto opEquals(const User b) const {
		if (!this.realName.isNull && !b.realName.isNull && (this.realName != b.realName)) {
			return false;
		}
		if (!this.account.isNull && !b.account.isNull && (this.account != b.account)) {
			return false;
		}
		return this.mask == b.mask;
	}
	///
	auto toHash() const {
		return mask.hashOf;
	}
}
@safe pure nothrow @nogc unittest {
	auto user = User("Test!Testo@Testy");
	auto compUser = User("Test!Testo@Testy");
	assert(user.mask.nickname == "Test");
	assert(user.mask.ident == "Testo");
	assert(user.mask.host == "Testy");
	assert(user == compUser);
	user.realName = "TestseT";
	compUser.realName = "whoever";
	assert(user != compUser);
	compUser.realName = user.realName;
	user.account = "Testeridoo";
	compUser.account = "Tototo";
	assert(user != compUser);
}
@safe pure unittest {
	import std.conv : text;
	auto user = User("Test!Testo@Testy");
	user.account = "Tester";
	assert(user.text == "Test!Testo@Testy (Tester)");
}
@system pure nothrow /+@nogc+/ unittest {
	immutable user = User("Test!Testo@Testy");
	immutable compUser = User("Test!Testo@Testy");
	assert(user.toHash == compUser.toHash);
}
/++
+ Parses a range of tokenized text into a tuple.
+/
auto toParsedTuple(Tup, Range)(Range range) {
	import std.conv : to;
	Nullable!Tup output = Tup();
	static foreach(i, MemberType; Tup.Types) {
		if (range.empty) {
			return Nullable!Tup.init;
		}
		try {
			output[i] = range.front.to!MemberType;
		} catch (Exception) {
			return Nullable!Tup.init;
		}
		range.popFront();
	}
	return output;
}
///
@safe pure nothrow unittest {
	import std.range : only, takeNone;
	import std.typecons : Tuple, tuple;
	assert(toParsedTuple!(Tuple!())(only("hi")) == tuple());
	assert(toParsedTuple!(Tuple!(string, "test"))(only("text")).test == "text");
	assert(toParsedTuple!(Tuple!(string, "test"))(takeNone(only("text"))).isNull);
	assert(toParsedTuple!(Tuple!(int, "test"))(only("100")).test == 100);
	assert(toParsedTuple!(Tuple!(int, "test", int, "test2", string, "test3"))(only("100", "200", "words")).test2 == 200);
	assert(toParsedTuple!(Tuple!(int, "test"))(only("aaaa")).isNull);
}