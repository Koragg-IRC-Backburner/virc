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
	assert(IRCTags(null).booleanTag!"test".isNull);
	assert(IRCTags(["test": "aaaaa"]).booleanTag!"test".isNull);
	assert(!IRCTags(["test": "0"]).booleanTag!"test");
	assert(IRCTags(["test": "1"]).booleanTag!"test");
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
	assert(IRCTags(null).typeTag!("test", uint).isNull);
	assert(IRCTags(["test": "a"]).typeTag!("test", uint).isNull);
	assert(IRCTags(["test": "0"]).typeTag!("test", uint) == 0);
	assert(IRCTags(["test": "10"]).typeTag!("test", uint) == 10);
	assert(IRCTags(["test": "words"]).typeTag!("test", string) == "words");
	assert(IRCTags(["test": "words"]).stringTag!"test" == "words");
	static struct Something {
		char val;
		this(string str) @safe pure nothrow {
			val = str[0];
		}
	}
	assert(IRCTags(["test": "words"]).typeTag!("test", Something).val == 'w');
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
	assert(IRCTags(null).arrayTag!("test").isNull);
	assert(IRCTags(["test":""]).arrayTag!("test").empty);
	assert(IRCTags(["test":"a"]).arrayTag!("test").front == "a");
	assert(IRCTags(["test":"a,b"]).arrayTag!("test") == ["a", "b"]);
	assert(IRCTags(["test":"a:b"]).arrayTag!("test", ":") == ["a", "b"]);
	assert(IRCTags(["test":"9,1"]).arrayTag!("test", ",", uint[]) == [9, 1]);
	assert(IRCTags(["test":"9,a"]).arrayTag!("test", ",", uint[]).isNull);
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
	assert(IRCTags(null).secondDurationTag!("test").isNull);
	assert(IRCTags(["test": "a"]).secondDurationTag!("test").isNull);
	assert(IRCTags(["test": "3600"]).secondDurationTag!("test") == 1.hours);
}
/++
+
+/
auto parseTime(string[string] tags) {
	enforce("time" in tags);
	return SysTime.fromISOExtString(tags["time"], UTC());
}

auto parseTagString(string input) {
	IRCTags output;
	auto splitTags = input.splitter(";").filter!(a => !a.empty);
	foreach (tag; splitTags) {
		auto splitKV = tag.findSplit("=");
		auto key = splitKV[0];
		if (!splitKV[1].empty) {
			output[key] = splitKV[2].replaceEscape!(string, only(`\\`, `\`), only(`\:`, `;`), only(`\r`, "\r"), only(`\n`, "\n"), only(`\s`, " "));
		} else {
			output[key] = "";
		}
	}
	return output;
}

///
@safe pure /+nothrow @nogc+/ unittest {
	//Example from http://ircv3.net/specs/core/message-tags-3.2.html
	{
		immutable tags = parseTagString("");
		assert(tags.length == 0);
	}
	//ditto
	{
		immutable tags = parseTagString("aaa=bbb;ccc;example.com/ddd=eee");
		assert(tags.length == 3);
		assert(tags["aaa"] == "bbb");
		assert(tags["ccc"] == "");
		assert(tags["example.com/ddd"] == "eee");
	}
	//escape test
	{
		immutable tags = parseTagString(`whatevs=\\s`);
		assert(tags.length == 1);
		assert("whatevs" in tags);
		assert(tags["whatevs"] == `\s`);
	}
	//Example from http://ircv3.net/specs/extensions/batch-3.2.html
	{
		immutable tags = parseTagString(`batch=yXNAbvnRHTRBv`);
		assert(tags.length == 1);
		assert("batch" in tags);
		assert(tags["batch"] == "yXNAbvnRHTRBv");
	}
	//Example from http://ircv3.net/specs/extensions/account-tag-3.2.html
	{
		immutable tags = parseTagString(`account=hax0r`);
		assert(tags.length == 1);
		assert("account" in tags);
		assert(tags["account"] == "hax0r");
	}
	{
		immutable tags = parseTagString(`testk=test\`);
		assert("testk" in tags);
		assert(tags["testk"] == "test");
	}
}
///
@safe /+pure nothrow @nogc+/ unittest {
	import std.datetime : DateTime, msecs, SysTime, UTC;
	//Example from http://ircv3.net/specs/extensions/server-time-3.2.html
	{
		auto tags = parseTagString("time=2011-10-19T16:40:51.620Z");
		assert(tags.length == 1);
		assert("time" in tags);
		assert(tags["time"] == "2011-10-19T16:40:51.620Z");
		immutable testTime = SysTime(DateTime(2011,10,19,16,40,51), 620.msecs, UTC());
		assert(parseTime(tags) == testTime);
	}
	//ditto
	{
		immutable tags = parseTagString("time=2012-06-30T23:59:60.419Z");
		assert(tags.length == 1);
		assert("time" in tags);
		assert(tags["time"] == "2012-06-30T23:59:60.419Z");
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