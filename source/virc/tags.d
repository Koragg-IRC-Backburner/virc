module virc.tags;


import core.time : Duration, seconds;
import std.algorithm : startsWith, map, splitter, filter, findSplit;
import std.array : front, empty;
import std.datetime : SysTime, UTC, msecs;
import std.exception : enforce;
import std.meta : aliasSeqOf;
import std.range : dropOne, isInputRange, only;
import std.typecons : Nullable;
import std.utf;

struct parsedMessage {
	string msg;
	IRCTags tags;
	this(string text) {
		msg = text;
	}
	this(string text, string[string] inTags) {
		msg = text;
		tags = IRCTags(inTags);
	}
}
struct IRCTags {
	string[string] tags;
	alias tags this;
}

Nullable!bool booleanTag(string tag)(IRCTags tags) {
	if (tag !in tags) {
		return Nullable!bool.init;
	}
	return Nullable!bool(tags[tag] == "1");
}
Nullable!string stringTag(string tag)(IRCTags tags) {
	if (tag !in tags) {
		return Nullable!string.init;
	}
	return Nullable!string(tags[tag]);
}
Nullable!type typeTag(string tag, type)(IRCTags tags) {
	import std.conv : to;
	if (tag !in tags) {
		return Nullable!type.init;
	}
	return Nullable!type(tags[tag].to!type);
}
//auto arrayTag(string tag, type)(IRCTags tags) {
//	import std.conv : to;
//	if (tag !in tags) {
//		return Nullable!type.init;
//	}
//	return Nullable!type(tags[tag].to!type);
//}
Nullable!Duration secondDurationTag(string tag)(IRCTags tags) {
	import std.conv : to;
	if (tag !in tags) {
		return Nullable!Duration.init;
	}
	return Nullable!Duration(tags[tag].to!long.seconds);
}
auto splitTag(string input) @safe pure {
	parsedMessage output;
	if (input.startsWith("@")) {
		auto splitMsg = input.dropOne.findSplit(" ");
		auto splitTags = splitMsg[0].splitter(";").filter!(a => !a.empty);
		foreach (tag; splitTags) {
			auto splitKV = tag.findSplit("=");
			auto key = splitKV[0];
			if (!splitKV[1].empty)
				output.tags[key] = splitKV[2].replaceEscape!(string, only(`\\`, `\`), only(`\:`, `;`), only(`\r`, "\r"), only(`\n`, "\n"), only(`\s`, " "));
			else
				output.tags[key] = "";
		}
		output.msg = splitMsg[2];
	} else
		output.msg = input;
	return output;
}
SysTime parseTime(string[string] tags) @safe {
	enforce("time" in tags);
	return SysTime.fromISOExtString(tags["time"], UTC());
}
///
@safe pure /+nothrow @nogc+/ unittest {
	//Example from http://ircv3.net/specs/core/message-tags-3.2.html
	{
		auto splitStr = ":nick!ident@host.com PRIVMSG me :Hello".splitTag;
		assert(splitStr.msg == ":nick!ident@host.com PRIVMSG me :Hello");
		assert(splitStr.tags.length == 0);
	}
	//ditto
	{
		auto splitStr = "@aaa=bbb;ccc;example.com/ddd=eee :nick!ident@host.com PRIVMSG me :Hello".splitTag;
		assert(splitStr.msg == ":nick!ident@host.com PRIVMSG me :Hello");
		assert(splitStr.tags.length == 3);
		assert(splitStr.tags["aaa"] == "bbb");
		assert(splitStr.tags["ccc"] == "");
		assert(splitStr.tags["example.com/ddd"] == "eee");
	}
	//escape test
	{
		auto splitStr = `@whatevs=\\s :Angel!angel@example.org PRIVMSG Wiz :Hello`.splitTag;
		assert(splitStr.msg == ":Angel!angel@example.org PRIVMSG Wiz :Hello");
		assert(splitStr.tags.length == 1);
		assert("whatevs" in splitStr.tags);
		assert(splitStr.tags["whatevs"] == `\s`);
	}
	//Example from http://ircv3.net/specs/extensions/batch-3.2.html
	{
		auto splitStr = `@batch=yXNAbvnRHTRBv :aji!a@a QUIT :irc.hub other.host`.splitTag;
		assert(splitStr.msg == ":aji!a@a QUIT :irc.hub other.host");
		assert(splitStr.tags.length == 1);
		assert("batch" in splitStr.tags);
		assert(splitStr.tags["batch"] == "yXNAbvnRHTRBv");
	}
	//Example from http://ircv3.net/specs/extensions/account-tag-3.2.html
	{
		auto splitStr = `@account=hax0r :user PRIVMSG #atheme :Now I'm logged in.`.splitTag;
		assert(splitStr.msg == ":user PRIVMSG #atheme :Now I'm logged in.");
		assert(splitStr.tags.length == 1);
		assert("account" in splitStr.tags);
		assert(splitStr.tags["account"] == "hax0r");
	}
}
///
@safe /+pure nothrow @nogc+/ unittest {
	import std.datetime : SysTime, DateTime, UTC, msecs;
	//Example from http://ircv3.net/specs/extensions/server-time-3.2.html
	{
		auto splitStr = "@time=2011-10-19T16:40:51.620Z :Angel!angel@example.org PRIVMSG Wiz :Hello".splitTag;
		assert(splitStr.msg == ":Angel!angel@example.org PRIVMSG Wiz :Hello");
		assert(splitStr.tags.length == 1);
		assert("time" in splitStr.tags);
		assert(splitStr.tags["time"] == "2011-10-19T16:40:51.620Z");
		immutable testTime = SysTime(DateTime(2011,10,19,16,40,51), 620.msecs, UTC());
		assert(parseTime(splitStr.tags) == testTime);
	}
	//ditto
	{
		auto splitStr = "@time=2012-06-30T23:59:60.419Z :John!~john@1.2.3.4 JOIN #chan".splitTag;
		assert(splitStr.msg == ":John!~john@1.2.3.4 JOIN #chan");
		assert(splitStr.tags.length == 1);
		assert("time" in splitStr.tags);
		assert(splitStr.tags["time"] == "2012-06-30T23:59:60.419Z");
		//assert(parseTime(splitStr.tags) == SysTime(DateTime(2012,06,30,23,59,60), 419.msecs, UTC()));
	}
}

T replaceEscape(T, replacements...)(T input) {
	static if (replacements.length == 0) {
		return input;
	} else {
		T output;
		enum findStrs = aliasSeqOf!([replacements].map!((x) => x[0]));
		for (size_t position = 0; position < input.length; position++) {
			final switch(input[position..$].startsWith(findStrs)) {
				case 0:
					output ~= input[position]; break;
				foreach (index, replacement; replacements) {
					static assert(replacements[index][0].length >= 1);
					case index+1:
						output ~= replacements[index][1];
						position += replacements[index][0].length-1;
						break;
				}
			}
		}
		return output;
	}
}
///
@safe /+pure @nogc nothrow+/ unittest {
	assert(replaceEscape("") == "");
	assert(replaceEscape!(string, only("a", "b"))("a") == "b");
	assert(replaceEscape!(string, only("a", "b"), only("aa", "b"))("aa") == "bb");
	//assert(replaceEscape!(string, only("aa", "b"), only("a", "b"))("aa") == "b");
}