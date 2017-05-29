/++
+
+/
module virc.numerics.misc;

import virc.numerics.definitions;
/++
+
+/
auto parseNumeric(Numeric numeric)() if (numeric.among(noInformationNumerics)) {
	static assert(0, "Cannot parse "~numeric~": No information to parse.");
}
/++
+
+/
//333 <channel> <setter> <timestamp>
auto parseNumeric(Numeric numeric : Numeric.RPL_TOPICWHOTIME, T)(T input) {
	return "";
}
///
unittest {

}