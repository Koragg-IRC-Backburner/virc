module virc.modes;

import std.algorithm : among, splitter;
import std.range.primitives : isInputRange, isOutputRange;
import std.range : put;
import std.typecons : Nullable, Tuple;


/++
 + IRC modes. These are settings for channels and users on an IRC network,
 + responsible for things ranging from user bans, flood control and colour
 + stripping to registration status.
 + Consists of a single character and (often) an argument string to go along
 + with it.
 +/
struct Mode {
	ModeType type = ModeType.d;
	char mode;
	Nullable!string arg;
	invariant() {
		assert((type != ModeType.d) || arg.isNull);
	}
	auto opEquals(Mode b) const {
		return (mode == b.mode);
	}
}

enum ModeType {
	///Adds/removes nick/address to a list. always has a parameter.
	a,
	///Mode that changes a setting and always has a parameter.
	b,
	///Mode that changes a setting and only has a parameter when set.
	c ,
	///Mode that changes a setting and never has a parameter.
	d
}

enum Change {
	///Mode was set.
	set,
	///Mode was unset.
	unset
}

struct ModeChange {
	Mode mode;
	Change change;
	void toString(T)(T sink) const if (isOutputRange!(T, const(char))) {
		final switch(change) {
			case Change.set:
				put(sink, '+');
				break;
			case Change.unset:
				put(sink, '-');
				break;
		}
		put(sink, mode.mode);
	}
}

auto parseModeString(string input, ModeType[char] channelModeTypes) {
	ModeChange[] changes;
	bool unsetMode = false;
	auto split = input.splitter(" ");
	auto modeList = split.front;
	split.popFront();
	foreach (mode; modeList) {
		if (mode == '+') {
			unsetMode = false;
		} else if (mode == '-') {
			unsetMode = true;
		} else {
			if (unsetMode) {
				auto modeType = mode in channelModeTypes ? channelModeTypes[mode] : ModeType.d;
				if (modeType.among(ModeType.a, ModeType.b)) {
					auto arg = split.front;
					split.popFront();
					changes ~= ModeChange(Mode(modeType, mode, Nullable!string(arg)), Change.unset);
				} else {
					changes ~= ModeChange(Mode(modeType, mode), Change.unset);
				}
			} else {
				auto modeType = mode in channelModeTypes ? channelModeTypes[mode] : ModeType.d;
				if (modeType.among(ModeType.a, ModeType.b, ModeType.c)) {
					auto arg = split.front;
					split.popFront();
					changes ~= ModeChange(Mode(modeType, mode, Nullable!string(arg)), Change.set);
				} else {
					changes ~= ModeChange(Mode(modeType, mode), Change.set);
				}
			}
		}
	}
	return changes;
}

@safe pure nothrow unittest {
	import std.algorithm : canFind, filter, map;
	import std.range : empty;
	{
		const testParsed = parseModeString("+s", null);
		assert(testParsed.filter!(x => x.change == Change.set).map!(x => x.mode).canFind(Mode(ModeType.d, 's')));
		assert(testParsed.filter!(x => x.change == Change.unset).empty);
	}
	{
		const testParsed = parseModeString("-s", null);
		assert(testParsed.filter!(x => x.change == Change.set).empty);
		assert(testParsed.filter!(x => x.change == Change.unset).map!(x => x.mode).canFind(Mode(ModeType.d, 's')));
	}
	{
		const testParsed = parseModeString("+s-n", null);
		assert(testParsed.filter!(x => x.change == Change.set).map!(x => x.mode).canFind(Mode(ModeType.d, 's')));
		assert(testParsed.filter!(x => x.change == Change.unset).map!(x => x.mode).canFind(Mode(ModeType.d, 'n')));
	}
	{
		const testParsed = parseModeString("-s+n", null);
		assert(testParsed.filter!(x => x.change == Change.set).map!(x => x.mode).canFind(Mode(ModeType.d, 'n')));
		assert(testParsed.filter!(x => x.change == Change.unset).map!(x => x.mode).canFind(Mode(ModeType.d, 's')));
	}
	{
		const testParsed = parseModeString("-s+nk secret", ['k': ModeType.b]);
		assert(testParsed.filter!(x => x.change == Change.set).map!(x => x.mode).canFind(Mode(ModeType.d, 'n')));
		assert(testParsed.filter!(x => x.change == Change.set).map!(x => x.mode).canFind(Mode(ModeType.b, 'k', Nullable!string("secret"))));
		assert(testParsed.filter!(x => x.change == Change.unset).map!(x => x.mode).canFind(Mode(ModeType.d, 's')));
	}
	{
		const testParsed = parseModeString("-sk+nl secret 4", ['k': ModeType.b, 'l': ModeType.c]);
		assert(testParsed.filter!(x => x.change == Change.set).map!(x => x.mode).canFind(Mode(ModeType.d, 'n')));
		assert(testParsed.filter!(x => x.change == Change.set).map!(x => x.mode).canFind(Mode(ModeType.b, 'l', Nullable!string("4"))));
		assert(testParsed.filter!(x => x.change == Change.unset).map!(x => x.mode).canFind(Mode(ModeType.b, 'k', Nullable!string("secret"))));
		assert(testParsed.filter!(x => x.change == Change.unset).map!(x => x.mode).canFind(Mode(ModeType.d, 's')));
	}
	{
		const testParsed = parseModeString("-s+nl 3333", ['l': ModeType.c]);
		assert(testParsed.filter!(x => x.change == Change.set).map!(x => x.mode).canFind(Mode(ModeType.d, 'n')));
		assert(testParsed.filter!(x => x.change == Change.set).map!(x => x.mode).canFind(Mode(ModeType.c, 'l', Nullable!string("3333"))));
		assert(testParsed.filter!(x => x.change == Change.unset).map!(x => x.mode).canFind(Mode(ModeType.d, 's')));
	}
	{
		const testParsed = parseModeString("+s-nl", ['l': ModeType.c]);
		assert(testParsed.filter!(x => x.change == Change.unset).map!(x => x.mode).canFind(Mode(ModeType.d, 'n')));
		assert(testParsed.filter!(x => x.change == Change.unset).map!(x => x.mode).canFind(Mode(ModeType.c, 'l')));
		assert(testParsed.filter!(x => x.change == Change.set).map!(x => x.mode).canFind(Mode(ModeType.d, 's')));
	}
}