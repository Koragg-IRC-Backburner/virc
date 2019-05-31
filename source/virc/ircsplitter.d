/++
+ Module for splitting IRC commands into its individual arguments for easier
+ parsing.
+/
module virc.ircsplitter;

import virc.common;

///
alias IRCSplitter = IRCSplitter_!(RFC2812Compliance.no);
///
struct IRCSplitter_(RFC2812Compliance RFC2812) {
	private string str;
	private size_t upper;
	private bool colon;
	static if (RFC2812) {
		size_t position;
		size_t endOffset = 15;
	}
	///
	this(string input) @nogc @safe pure nothrow {
		str = input;
		popFront();
	}
	///
	void popFront() @nogc @safe pure nothrow {
		if (colon) {
			colon = false;
			return;
		}
		str = str[upper .. $];
		upper = 0;
		while ((str.length > 0) && str[0] == ' ') {
			str = str[1 .. $];
		}
		if (str.length == 0) {
			return;
		}
		if (str[0] == ':') {
			str = str[1 .. $];
			upper = str.length;
			if (upper == 0) {
				colon = true;
			}
		} else {
			foreach (i, char c; str) {
				if (c == ' ') {
					upper = i;
					break;
				}
			}
			if (upper == 0) {
				upper = str.length;
			}
		}
		static if (RFC2812) {
			position++;
			if (position == endOffset) {
				upper = str.length;
			}
		}
	}
	///
	auto empty() const {
		static if (RFC2812) {
			if (position > endOffset) {
				return true;
			}
		}
		return !colon && str.length == 0;
	}
	///
	auto front() const @nogc nothrow
		in(!empty)
	{
		return str[0..upper];
	}
	///
	auto save() {
		return this;
	}
}
///
@safe pure nothrow @nogc unittest {
	import std.algorithm : equal;
	import std.range : only;
	assert(IRCSplitter("").empty);
	assert(IRCSplitter(" ").empty);
	assert(IRCSplitter("test").equal(only("test")));
	assert(IRCSplitter("test word2").equal(only("test", "word2")));
	assert(IRCSplitter("test  word2").equal(only("test", "word2")));
	assert(IRCSplitter("test  :word2").equal(only("test", "word2")));
	assert(IRCSplitter("test :word2 word3").equal(only("test", "word2 word3")));
	assert(IRCSplitter("test :word2 :word3").equal(only("test", "word2 :word3")));
	assert(IRCSplitter(":").equal(only("")));
	assert(IRCSplitter_!(RFC2812Compliance.yes)("word1 word2 word3 word4 word5 word6 word7 word8 word9 word10 word11 word12 word13 word14 word15 word16 word17").equal(only("word1", "word2", "word3", "word4", "word5", "word6", "word7", "word8", "word9", "word10", "word11", "word12", "word13", "word14", "word15 word16 word17")));
}