module virc.casemapping;

import std.range.primitives : isInputRange;
import std.ascii : toUpper, toLower, isAlpha;
import std.algorithm : map;


enum CaseMapping {
	rfc1459 = "rfc1459",
	strictRFC1459 = "strict-rfc1459",
	rfc3454 = "rfc3454",
	ascii = "ascii"
}
auto toIRCUpper(CaseMapping caseMapping = CaseMapping.rfc1459)(string input) {
	static dchar upper(dchar input) {
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
	return input.map!upper;
}
///
unittest {
	import std.algorithm : equal;
	assert("test".toIRCUpper!(CaseMapping.rfc1459).equal("TEST"));
	assert("test".toIRCUpper!(CaseMapping.strictRFC1459).equal("TEST"));
	assert("test".toIRCUpper!(CaseMapping.ascii).equal("TEST"));
	assert("test{}|~".toIRCUpper!(CaseMapping.rfc1459).equal("TEST[]\\^"));
	assert("test{}|~".toIRCUpper!(CaseMapping.strictRFC1459).equal("TEST[]\\~"));
	assert("test{}|~".toIRCUpper!(CaseMapping.ascii).equal("TEST{}|~"));
}
auto toIRCLower(CaseMapping caseMapping = CaseMapping.rfc1459)(string input) {
	static dchar lower(dchar input) {
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
	return input.map!lower;
}
///
unittest {
	import std.algorithm : equal;
	assert("TEST".toIRCLower!(CaseMapping.rfc1459).equal("test"));
	assert("TEST".toIRCLower!(CaseMapping.strictRFC1459).equal("test"));
	assert("TEST".toIRCLower!(CaseMapping.ascii).equal("test"));
	assert("TEST[]\\^".toIRCLower!(CaseMapping.rfc1459).equal("test{}|~"));
	assert("TEST[]\\~".toIRCLower!(CaseMapping.strictRFC1459).equal("test{}|~"));
	assert("TEST{}|~".toIRCLower!(CaseMapping.ascii).equal("test{}|~"));
}