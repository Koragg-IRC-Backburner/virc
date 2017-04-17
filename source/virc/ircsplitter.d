module virc.ircsplitter;

struct IRCSplitter {
	private string str;
	private size_t upper;
	private bool blankColon = false;
	bool isColonParameter = false;
	this(string input) @nogc @safe pure nothrow {
		str = input;
		popFront();
	}
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
	bool empty() @nogc @safe pure nothrow {
		return str.length == 0 && !blankColon;
	}
	string front() @nogc @safe pure nothrow {
		return str[0..upper];
	}
	auto save() @nogc @safe pure nothrow {
		return this;
	}
}

@safe pure nothrow unittest {
	import std.algorithm : equal;
	import std.array;
	import std.stdio;
	import std.range;
	assert(IRCSplitter("").empty);
	assert(IRCSplitter("test").equal(["test"]));
	assert(IRCSplitter("test word2").equal(["test", "word2"]));
	assert(IRCSplitter("test :word2 word3").equal(["test", "word2 word3"]));
	assert(IRCSplitter("test :word2 :word3").equal(["test", "word2 :word3"]));
	assert(IRCSplitter(":").equal([""]));
}