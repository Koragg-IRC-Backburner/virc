module virc.common;

import std.datetime : SysTime;
import std.range : put, isOutputRange;
import std.typecons : Nullable;

import virc.modes;
import virc.usermask;

struct Channel {
	string name;
	ulong userCount;
	Topic topic;
	Mode[] modes;
	void toString(T)(T sink) const if (isOutputRange!(T, const(char))) {
		put(sink, name);
	}
}

struct Topic {
	string message;
	Nullable!SysTime time;
	Nullable!User setBy;
	bool opEquals(const Topic b) const @safe pure nothrow @nogc{
		return message == b.message;
	}
}

struct User {
	UserMask mask;
	this(string str) @safe pure nothrow @nogc {
		mask = UserMask(str);
	}
	string nickname() @safe pure nothrow @nogc const {
		return mask.nickname;
	}
	string ident() @safe pure nothrow @nogc const {
		return mask.ident;
	}
	string host() @safe pure nothrow @nogc const  {
		return mask.host;
	}
	Nullable!string realName;
	Nullable!string account;
	void toString(T)(T sink) const if (isOutputRange!(T, const(char))) {
		mask.toString(sink);
		if (!account.isNull) {
			put(sink, " (");
			put(sink, account);
			put(sink, ")");
		}
	}
	bool opEquals(const User b) const @safe pure nothrow @nogc {
		if (!this.realName.isNull && !b.realName.isNull && (this.realName != b.realName)) {
			return false;
		}
		if (!this.account.isNull && !b.account.isNull && (this.account != b.account)) {
			return false;
		}
		return this.mask == b.mask;
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