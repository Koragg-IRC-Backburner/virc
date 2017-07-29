/++
+ Module for splitting IRC commands into its individual arguments for easier
+ parsing.
+/
module virc.ircsplitter;

///
struct IRCSplitter {
	private string str;
	private size_t upper;
	private bool blankColon = false;
	/++
	+ This typically marks the command's main payload. No arguments will come
	+ after this one.
	+/
	bool isColonParameter = false;
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
				isColonParameter = true;
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
	}
	///
	auto empty() {
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
@safe pure nothrow unittest {
	import std.algorithm : equal;
	assert(IRCSplitter("").empty);
	assert(IRCSplitter("test").equal(["test"]));
	assert(IRCSplitter("test word2").equal(["test", "word2"]));
	assert(IRCSplitter("test :word2 word3").equal(["test", "word2 word3"]));
	assert(IRCSplitter("test :word2 :word3").equal(["test", "word2 :word3"]));
	assert(IRCSplitter(":").equal([""]));
}