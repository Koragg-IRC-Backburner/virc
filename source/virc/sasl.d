///SASL support module
module virc.sasl;

/++
+ Interface for SASL authentication mechanisms.
+/
interface SASLMechanism {
	///
	string name() @safe pure @nogc nothrow;
	///
	bool empty() @safe nothrow;
	///
	string front() @safe nothrow;
	///
	void popFront() @safe nothrow;
	///
	void put(string) @safe nothrow;
}

/++
+ EXTERNAL SASL mechanism support. For authentication based on other network
+ layers, such as TLS or IPSec.
+/
class SASLExternal : SASLMechanism {
	override string name() @safe pure @nogc nothrow { return "EXTERNAL"; }
	override bool empty() @safe pure @nogc nothrow { return true; }
	override string front() @safe pure @nogc nothrow { return ""; }
	override void popFront() @safe pure @nogc nothrow {}
	override void put(string) @safe pure @nogc nothrow {}
}
/++
+ PLAIN SASL mechanism support. For authentication with plaintext username and
+ password combination.
+/
class SASLPlain : SASLMechanism {
	override string name() @safe pure @nogc nothrow { return "PLAIN"; }
	override bool empty() @safe pure @nogc nothrow { return true; }
	override string front() @safe pure @nogc nothrow { return ""; }
	override void popFront() @safe pure @nogc nothrow {}
	override void put(string) @safe pure @nogc nothrow {}
}