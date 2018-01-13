module virc.numerics.magicparser;

import std.datetime : UTC;
import std.range : isInputRange, ElementType;
import std.traits : hasUDA;
import std.typecons : Nullable;

enum Optional;

enum isOptional(T, string member) = hasUDA!(__traits(getMember, T, member), Optional);

static immutable utc = UTC();

Nullable!T autoParse(T, Range)(Range input) if (isInputRange!Range && is(ElementType!Range == string)){
	import std.array : empty, front, popFront;
	import std.conv : to;
	import std.traits : FieldNameTuple, hasIndirections, hasUDA;
	Nullable!T output = T.init;
	foreach (member; FieldNameTuple!T) {
		alias MemberType = typeof(__traits(getMember, T, member));
		if (input.empty) {
			static if (isOptional!(T, member)) {
				continue;
			} else {
				return Nullable!T.init;
			}
		}
		import std.datetime : SysTime;
		static if (is(MemberType == SysTime)) {
			try {
				__traits(getMember, output, member) = SysTime.fromUnixTime(input.front.to!ulong, utc);
			} catch (Exception) {
				static if (isOptional!(T, member)) {
					continue;
				} else {
					return Nullable!T.init;
				}
			}
		} else {
			__traits(getMember, output, member) = input.front.to!MemberType;
		}
		input.popFront();
	}
	return output;
}