/++
+ Module for handling the various CASEMAPPING methods used by IRC networks.
+/
module virc.casemapping;

import std.algorithm : map;
import std.ascii : isAlpha, toLower, toUpper;
import std.range.primitives : isInputRange;

/++
+
+/
enum CaseMapping {
	unknown = "",
	rfc1459 = "rfc1459",
	strictRFC1459 = "strict-rfc1459",
	rfc3454 = "rfc3454",
	ascii = "ascii"
}
/++
+
+/
auto toIRCUpper(CaseMapping caseMapping = CaseMapping.rfc1459)(string input) {
	import std.utf : byCodeUnit;
	static char upper(char input) {
		if (input.isAlpha) {
			return input.toUpper();
		}
		static if (caseMapping != CaseMapping.ascii) {
			switch (input) {
				case '{': return '[';
				case '}': return ']';
				case '|': return '\\';
				static if (caseMapping == CaseMapping.rfc1459) {
					case '~': return '^';
				}
				default: break;
			}
		}
		return input;
	}
	return input.byCodeUnit.map!upper;
}
///
@safe pure nothrow unittest {
	import std.algorithm : equal;
	import std.utf : byCodeUnit;
	assert("test".toIRCUpper!(CaseMapping.rfc1459).equal("TEST"d));
	assert("test".toIRCUpper!(CaseMapping.strictRFC1459).equal("TEST"d));
	assert("test".toIRCUpper!(CaseMapping.ascii).equal("TEST"d));
	assert("test{}|~".toIRCUpper!(CaseMapping.rfc1459).equal("TEST[]\\^"d));
	assert("test{}|~".toIRCUpper!(CaseMapping.strictRFC1459).equal("TEST[]\\~"d));
	assert("test{}|~".toIRCUpper!(CaseMapping.ascii).equal("TEST{}|~"d));
}
/++
+
+/
auto toIRCLower(CaseMapping caseMapping = CaseMapping.rfc1459)(string input) {
	import std.utf : byCodeUnit;
	static char lower(char input) {
		if (input.isAlpha) {
			return input.toLower();
		}
		static if (caseMapping != CaseMapping.ascii) {
			switch (input) {
				case '[': return '{';
				case ']': return '}';
				case '\\': return '|';
				static if (caseMapping == CaseMapping.rfc1459) {
					case '^': return '~';
				}
				default: break;
			}
		}
		return input;
	}
	return input.byCodeUnit.map!lower;
}
///
@safe pure nothrow unittest {
	import std.algorithm : equal;
	assert("TEST".toIRCLower!(CaseMapping.rfc1459).equal("test"d));
	assert("TEST".toIRCLower!(CaseMapping.strictRFC1459).equal("test"d));
	assert("TEST".toIRCLower!(CaseMapping.ascii).equal("test"d));
	assert("TEST[]\\^".toIRCLower!(CaseMapping.rfc1459).equal("test{}|~"d));
	assert("TEST[]\\~".toIRCLower!(CaseMapping.strictRFC1459).equal("test{}|~"d));
	assert("TEST{}|~".toIRCLower!(CaseMapping.ascii).equal("test{}|~"d));
}