/++
+ IRCv3 tags capability support.
+/
module virc.ircv3.tags;


import core.time : Duration, seconds;
import std.algorithm : filter, findSplit, map, splitter, startsWith;
import std.array : empty, front;
import std.datetime : msecs, SysTime, UTC;
import std.exception : enforce;
import std.meta : aliasSeqOf;
import std.range : dropOne, isInputRange, only;
import std.traits : isArray;
import std.typecons : Nullable;
import std.utf;

import virc.ircv3.batch;
/++
+
+/
struct ParsedMessage {
	///
	string msg;
	///
	IRCTags tags;
	///
	BatchInformation batch;
	///
	this(string text) pure @safe nothrow @nogc {
		msg = text;
	}
	///
	this(string text, string[string] inTags) pure @safe nothrow @nogc {
		msg = text;
		tags = IRCTags(inTags);
	}
	auto opEquals(const ParsedMessage b) const {
		return(this.msg == b.msg);
	}
}
/++
+
+/
struct IRCTags {
	///
	string[string] tags;
	alias tags this;
}
/++
+
+/
Nullable!bool booleanTag(string tag)(IRCTags tags) {
	Nullable!bool output;
	if (tag in tags) {
		if (tags[tag] == "1") {
			output = true;
		} else if (tags[tag] == "0") {
			output = false;
		} //Other values treated as if tag not present
	}
	return output;
}
///
@safe pure nothrow unittest {
	assert(ParsedMessage("").tags.booleanTag!"test".isNull);
	assert(ParsedMessage("", ["test": "aaaaa"]).tags.booleanTag!"test".isNull);
	assert(!ParsedMessage("", ["test": "0"]).tags.booleanTag!"test");
	assert(ParsedMessage("", ["test": "1"]).tags.booleanTag!"test");
}
/++
+
+/
Nullable!string stringTag(string tag)(IRCTags tags) {
	return typeTag!(tag, string)(tags);
}
/++
+
+/
Nullable!Type typeTag(string tag, Type)(IRCTags tags) {
	import std.conv : to;
	Nullable!Type output;
	if (tag in tags) {
		try {
			output = tags[tag].to!Type;
		} catch (Exception) {} //Act as if tag doesn't exist if malformed
	}
	return output;
}
///
@safe pure nothrow unittest {
	assert(ParsedMessage("").tags.typeTag!("test", uint).isNull);
	assert(ParsedMessage("", ["test": "a"]).tags.typeTag!("test", uint).isNull);
	assert(ParsedMessage("", ["test": "0"]).tags.typeTag!("test", uint) == 0);
	assert(ParsedMessage("", ["test": "10"]).tags.typeTag!("test", uint) == 10);
	assert(ParsedMessage("", ["test": "words"]).tags.typeTag!("test", string) == "words");
	assert(ParsedMessage("", ["test": "words"]).tags.stringTag!"test" == "words");
	static struct Something {
		char val;
		this(string str) @safe pure nothrow {
			val = str[0];
		}
	}
	assert(ParsedMessage("", ["test": "words"]).tags.typeTag!("test", Something).val == 'w');
}
/++
+
+/
auto arrayTag(string tag, string delimiter = ",", Type = string[])(IRCTags tags) if (isArray!Type){
	import std.algorithm : splitter;
	import std.conv : to;
	import std.range : ElementType;
	Nullable!Type output;
	if (tag in tags) {
		auto split = tags[tag].splitter(delimiter);
		output = [];
		foreach (element; split) {
			try {
				output ~= element.to!(ElementType!Type);
			} catch (Exception) { //Malformed, reset everything
				output = output.init;
				break;
			}
		}
	}
	return output;
}
///
@safe pure nothrow unittest {
	assert(ParsedMessage("").tags.arrayTag!("test").isNull);
	assert(ParsedMessage("", ["test":""]).tags.arrayTag!("test").empty);
	assert(ParsedMessage("", ["test":"a"]).tags.arrayTag!("test").front == "a");
	assert(ParsedMessage("", ["test":"a,b"]).tags.arrayTag!("test") == ["a", "b"]);
	assert(ParsedMessage("", ["test":"a:b"]).tags.arrayTag!("test", ":") == ["a", "b"]);
	assert(ParsedMessage("", ["test":"9,1"]).tags.arrayTag!("test", ",", uint[]) == [9, 1]);
	assert(ParsedMessage("", ["test":"9,a"]).tags.arrayTag!("test", ",", uint[]).isNull);
}
/++
+
+/
Nullable!Duration secondDurationTag(string tag)(IRCTags tags) {
	import std.conv : to;
	Nullable!Duration output;
	if (tag in tags) {
		try {
			output = tags[tag].to!long.seconds;
		} catch (Exception) {} //Not a duration. Act like tag is nonexistent.
	}
	return output;
}
///
@safe pure nothrow unittest {
	import core.time : hours;
	assert(ParsedMessage("").tags.secondDurationTag!("test").isNull);
	assert(ParsedMessage("", ["test": "a"]).tags.secondDurationTag!("test").isNull);
	assert(ParsedMessage("", ["test": "3600"]).tags.secondDurationTag!("test") == 1.hours);
}
/++
+
+/
auto parseTime(string[string] tags) {
	enforce("time" in tags);
	return SysTime.fromISOExtString(tags["time"], UTC());
}
/++
+
+/
auto splitTag(string input) {
	ParsedMessage output;
	if (input.startsWith("@")) {
		auto splitMsg = input.dropOne.findSplit(" ");
		auto splitTags = splitMsg[0].splitter(";").filter!(a => !a.empty);
		foreach (tag; splitTags) {
			auto splitKV = tag.findSplit("=");
			auto key = splitKV[0];
			if (!splitKV[1].empty) {
				output.tags[key] = splitKV[2].replaceEscape!(string, only(`\\`, `\`), only(`\:`, `;`), only(`\r`, "\r"), only(`\n`, "\n"), only(`\s`, " "));
			} else {
				output.tags[key] = "";
			}
		}
		output.msg = splitMsg[2];
	} else {
		output.msg = input;
	}
	return output;
}
///
@safe pure /+nothrow @nogc+/ unittest {
	//Example from http://ircv3.net/specs/core/message-tags-3.2.html
	{
		immutable splitStr = ":nick!ident@host.com PRIVMSG me :Hello".splitTag;
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
	{
		auto splitStr = `@testk=test\ :user QUIT :bye`.splitTag;
		assert("testk" in splitStr.tags);
		assert(splitStr.tags["testk"] == "test");
	}
}
///
@safe /+pure nothrow @nogc+/ unittest {
	import std.datetime : DateTime, msecs, SysTime, UTC;
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
		//leap seconds not currently representable
		//assert(parseTime(splitStr.tags) == SysTime(DateTime(2012,06,30,23,59,60), 419.msecs, UTC()));
	}
}
/++
+
+/
T replaceEscape(T, replacements...)(T input) {
	static if (replacements.length == 0) {
		return input;
	} else {
		T output;
		enum findStrs = aliasSeqOf!([replacements].map!((x) => x[0].byCodeUnit));
		if ((input.length > 0) && (input[$-1] == '\\')) {
			input = input[0..$-1];
		}
		for (size_t position = 0; position < input.length; position++) {
			final switch(input[position..$].byCodeUnit.startsWith(findStrs)) {
				case 0:
					output ~= input[position];
					break;
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
@safe pure nothrow unittest {
	assert(replaceEscape("") == "");
	assert(replaceEscape!(string, only("a", "b"))("a") == "b");
	assert(replaceEscape!(string, only("a", "b"), only("aa", "b"))("aa") == "bb");
}