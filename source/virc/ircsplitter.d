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
	private bool blankColon = false;
	static if (RFC2812) {
		size_t position;
		size_t endOffset = 16;
	}
	///
	this(string input) @nogc @safe pure nothrow {
		str = input;
		popFront();
	}
	///
	void popFront() @nogc @safe pure nothrow {
		if (blankColon) {
			blankColon = false;
		} else {
			if ((str.length > upper) && (str[upper] == ' ')) {
				upper++;
			}
			str = str[upper..$];
			upper = 0;
			if ((str.length > 0) && (str[0] == ':')) {
				str = str[1..$];
				upper = str.length;
				if (str.length == 0) {
					blankColon = true;
				}
			} else {
				foreach (index, chr; str) {
					if (chr == ' ')
						break;
					upper = index+1;
				}
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
	auto empty() {
		static if (RFC2812) {
			if (position > endOffset) {
				return true;
			}
		}
		return str.length == 0 && !blankColon;
	}
	///
	auto front() in {
		assert(!empty);
	} body {
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
	assert(IRCSplitter("test").equal(only("test")));
	assert(IRCSplitter("test word2").equal(only("test", "word2")));
	assert(IRCSplitter("test :word2 word3").equal(only("test", "word2 word3")));
	assert(IRCSplitter("test :word2 :word3").equal(only("test", "word2 :word3")));
	assert(IRCSplitter(":").equal(only("")));
	assert(IRCSplitter_!(RFC2812Compliance.yes)("COMMAND word1 word2 word3 word4 word5 word6 word7 word8 word9 word10 word11 word12 word13 word14 word15 word16 word17").equal(only("COMMAND", "word1", "word2", "word3", "word4", "word5", "word6", "word7", "word8", "word9", "word10", "word11", "word12", "word13", "word14", "word15 word16 word17")));
}