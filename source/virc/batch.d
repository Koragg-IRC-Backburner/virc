/++
+ Module for supporting IRCv3's BATCH capability.
+/
module virc.batch;
import virc.tags;
/++
+
+/
struct BatchProcessor {
	///
	ParsedMessage[] batchless;
	private Batch[string] batchCache;
	///
	Batch[] batches;
	///
	bool[] consumeBatch;
	///
	void put(string line) @safe pure {
		put(line.splitTag());
	}
	///
	void put(ParsedMessage splitMsg) @safe pure {
		auto processed = BatchCommand(splitMsg.msg);
		Batch newBatch;
		if (processed.isValid && processed.isNew) {
			newBatch.info.referenceTag = processed.referenceTag;
			newBatch.info.type = processed.type;
			newBatch.info.parameters = processed.parameters;
		}
		if ("batch" !in splitMsg.tags) {
			if (processed.isValid) {
				if (processed.isNew) {
					batchCache[newBatch.info.referenceTag] = newBatch;
				} else if (processed.isClosed) {
					batches ~= batchCache[processed.referenceTag];
					consumeBatch ~= true;
					batchCache.remove(processed.referenceTag);
				}
			} else {
				batchless ~= splitMsg;
				consumeBatch ~= false;
			}
		} else {
			void findBatch(ref Batch[string] searchBatches, string identifier) @safe pure {
				foreach (ref batch; searchBatches) {
					if (batch.info.referenceTag == identifier) {
						if (processed.isValid) {
							if (processed.isNew)
								batch.nestedBatches[newBatch.info.referenceTag] = newBatch;
						} else {
							batch.put(splitMsg);
						}
						return;
					}
					else
						findBatch(batch.nestedBatches, identifier);
				}
			}
			findBatch(batchCache, splitMsg.tags["batch"]);
		}
	}
	///
	auto empty() {
		import std.range : empty;
		return (batches.empty && batchless.empty);
	}
	///
	void popFront() @safe pure {
		if (consumeBatch[0]) {
			batches = batches[1..$];
		} else
			batchless = batchless[1..$];
		consumeBatch = consumeBatch[1..$];
	}
	///
	auto front() {
		if (consumeBatch[0])
			return batches[0];
		else
			return Batch(BatchInformation(false, "", "NOT A BATCH", []), [batchless[0]]);
	}
}
private struct BatchCommand {
	this(string msg) @safe pure nothrow {
		import std.string : split;
		import std.uni : sicmp;
		auto splitMsg = msg.split(" ");
		if ((splitMsg.length <= 2) || (sicmp(splitMsg[1],"BATCH")))
			return;
		isValid = true;
		server = splitMsg[0];
		referenceTag = splitMsg[2][1..$];
		isNew = splitMsg[2][0] == '+';
		if (isNew) {
			type = splitMsg[3];
			if (splitMsg.length >= 4)
				parameters = splitMsg[4..$];
		}
	}
	string server;
	string referenceTag;
	string type;
	string[] parameters;
	bool isNew;
	auto isClosed() { return !isNew; }
	bool isValid = false;
}
/++
+
+/
struct Batch {
	///Metadata attached to this batch
	BatchInformation info;
	///Lines captured minus the batch tag and starting/ending commands.
	ParsedMessage[] lines;
	///Any batches nested inside this one.
	Batch[string] nestedBatches;
	///
	void put(ParsedMessage line) @safe pure {
		line.batch = info;
		lines ~= line;
	}
}
/++
+
+/
struct BatchInformation {
	///
	bool isValidBatch = false;
	///A simple string identifying the batch. Uniqueness is not guaranteed?
	string referenceTag;
	///Indicates how the batch is to be processed. Examples include netsplit, netjoin, chathistory
	string type;
	///Miscellaneous details associated with the batch. Meanings vary based on type.
	string[] parameters;
}
@safe pure /+nothrow+/ unittest {
	import std.algorithm : copy;
	import std.range : isInputRange, isOutputRange, takeOne;
	static assert(isOutputRange!(BatchProcessor, string), "BatchProcessor failed outputrange test");
	static assert(isInputRange!BatchProcessor, "BatchProcessor failed inputrange test");
	//Example from http://ircv3.net/specs/extensions/batch-3.2.html
	{
		auto batchProcessor = new BatchProcessor;
		auto lines = [`:irc.host BATCH +yXNAbvnRHTRBv netsplit irc.hub other.host`,
					`@batch=yXNAbvnRHTRBv :aji!a@a QUIT :irc.hub other.host`,
					`@batch=yXNAbvnRHTRBv :nenolod!a@a QUIT :irc.hub other.host`,
					`:nick!user@host PRIVMSG #channel :This is not in batch, so processed immediately`,
					`@batch=yXNAbvnRHTRBv :jilles!a@a QUIT :irc.hub other.host`,
					`:irc.host BATCH -yXNAbvnRHTRBv`];
		copy(lines, batchProcessor);
		{
			const batch = takeOne(batchProcessor).front;
			assert(batch.lines == [ParsedMessage(":nick!user@host PRIVMSG #channel :This is not in batch, so processed immediately")]);
		}
		batchProcessor.popFront();
		{
			const batch = takeOne(batchProcessor).front;
			assert(batch.info.referenceTag == `yXNAbvnRHTRBv`);
			assert(batch.info.type == `netsplit`);
			assert(batch.info.parameters == [`irc.hub`, `other.host`]);
			assert(batch.lines == [ParsedMessage(`:aji!a@a QUIT :irc.hub other.host`, ["batch": "yXNAbvnRHTRBv"]), ParsedMessage(`:nenolod!a@a QUIT :irc.hub other.host`, ["batch": "yXNAbvnRHTRBv"]), ParsedMessage(`:jilles!a@a QUIT :irc.hub other.host`, ["batch": "yXNAbvnRHTRBv"])]);
		}
		batchProcessor.popFront();
		assert(batchProcessor.empty);
	}
	//ditto
	{
		auto batchProcessor = new BatchProcessor;
		auto lines = [`:irc.host BATCH +1 example.com/foo`,
					`@batch=1 :nick!user@host PRIVMSG #channel :Message 1`,
					`:irc.host BATCH +2 example.com/foo`,
					`@batch=1 :nick!user@host PRIVMSG #channel :Message 2`,
					`@batch=2 :nick!user@host PRIVMSG #channel :Message 4`,
					`@batch=1 :nick!user@host PRIVMSG #channel :Message 3`,
					`:irc.host BATCH -1`,
					`@batch=2 :nick!user@host PRIVMSG #channel :Message 5`,
					`:irc.host BATCH -2`];
		copy(lines, batchProcessor);
		{
			const batch = takeOne(batchProcessor).front;
			assert(batch.info.type == "example.com/foo");
			assert(batch.info.referenceTag == "1");
			assert(batch.lines == [ParsedMessage(":nick!user@host PRIVMSG #channel :Message 1", ["batch": "1"]), ParsedMessage(":nick!user@host PRIVMSG #channel :Message 2", ["batch": "1"]), ParsedMessage(":nick!user@host PRIVMSG #channel :Message 3", ["batch": "1"])]);
		}
		batchProcessor.popFront();
		{
			const batch = takeOne(batchProcessor).front;
			assert(batch.info.type == "example.com/foo");
			assert(batch.info.referenceTag == "2");
			assert(batch.lines == [ParsedMessage(":nick!user@host PRIVMSG #channel :Message 4", ["batch": "2"]), ParsedMessage(":nick!user@host PRIVMSG #channel :Message 5", ["batch": "2"])]);
		}
		batchProcessor.popFront();
		assert(batchProcessor.empty);
	}
	//ditto
	{
		auto batchProcessor = new BatchProcessor;
		auto lines = [`:irc.host BATCH +outer example.com/foo`,
					`@batch=outer :irc.host BATCH +inner example.com/bar`,
					`@batch=inner :nick!user@host PRIVMSG #channel :Hi`,
					`@batch=outer :irc.host BATCH -inner`,
					`:irc.host BATCH -outer`];
		copy(lines, batchProcessor);
		{
			auto batch = takeOne(batchProcessor).front;
			assert(batch.info.type == "example.com/foo");
			assert(batch.info.referenceTag == "outer");
			assert(batch.info.parameters == []);
			assert(batch.lines == []);
			assert("inner" in batch.nestedBatches);
			assert(batch.nestedBatches["inner"].info.type == "example.com/bar");
			assert(batch.nestedBatches["inner"].info.referenceTag == "inner");
			assert(batch.nestedBatches["inner"].info.parameters == []);
			assert(batch.nestedBatches["inner"].lines == [ParsedMessage(":nick!user@host PRIVMSG #channel :Hi", ["batch": "inner"])]);
		}
		batchProcessor.popFront();
		assert(batchProcessor.empty);
	}
	//Example from http://ircv3.net/specs/extensions/batch/netsplit-3.2.html
	{
		auto batchProcessor = new BatchProcessor;
		auto lines = [`:irc.host BATCH +yXNAbvnRHTRBv netsplit irc.hub other.host`,
					`@batch=yXNAbvnRHTRBv :aji!a@a QUIT :irc.hub other.host`,
					`@batch=yXNAbvnRHTRBv :nenolod!a@a QUIT :irc.hub other.host`,
					`@batch=yXNAbvnRHTRBv :jilles!a@a QUIT :irc.hub other.host`,
					`:irc.host BATCH -yXNAbvnRHTRBv`];
		copy(lines, batchProcessor);
		{
			const batch = takeOne(batchProcessor).front;
			assert(batch.info.type == "netsplit");
			assert(batch.info.referenceTag == "yXNAbvnRHTRBv");
			assert(batch.info.parameters == ["irc.hub", "other.host"]);
			assert(batch.lines == [ParsedMessage(":aji!a@a QUIT :irc.hub other.host", ["batch": "yXNAbvnRHTRBv"]), ParsedMessage(":nenolod!a@a QUIT :irc.hub other.host", ["batch": "yXNAbvnRHTRBv"]), ParsedMessage(`:jilles!a@a QUIT :irc.hub other.host`, ["batch": "yXNAbvnRHTRBv"])]);
		}
		batchProcessor.popFront();
		assert(batchProcessor.empty);
	}
	//ditto
	{
		auto batchProcessor = new BatchProcessor;
		auto lines = [`:irc.host BATCH +4lMeQwsaOMs6s netjoin irc.hub other.host`,
					`@batch=4lMeQwsaOMs6s :aji!a@a JOIN #atheme`,
					`@batch=4lMeQwsaOMs6s :nenolod!a@a JOIN #atheme`,
					`@batch=4lMeQwsaOMs6s :jilles!a@a JOIN #atheme`,
					`@batch=4lMeQwsaOMs6s :nenolod!a@a JOIN #ircv3`,
					`@batch=4lMeQwsaOMs6s :jilles!a@a JOIN #ircv3`,
					`@batch=4lMeQwsaOMs6s :Elizacat!a@a JOIN #ircv3`,
					`:irc.host BATCH -4lMeQwsaOMs6s`];
		copy(lines, batchProcessor);
		{
			const batch = takeOne(batchProcessor).front;
			assert(batch.info.type == "netjoin");
			assert(batch.info.referenceTag == "4lMeQwsaOMs6s");
			assert(batch.info.parameters == ["irc.hub", "other.host"]);
			assert(batch.lines == [ParsedMessage(":aji!a@a JOIN #atheme", ["batch": "4lMeQwsaOMs6s"]), ParsedMessage(":nenolod!a@a JOIN #atheme", ["batch": "4lMeQwsaOMs6s"]), ParsedMessage(`:jilles!a@a JOIN #atheme`, ["batch": "4lMeQwsaOMs6s"]), ParsedMessage(`:nenolod!a@a JOIN #ircv3`, ["batch": "4lMeQwsaOMs6s"]), ParsedMessage(`:jilles!a@a JOIN #ircv3`, ["batch": "4lMeQwsaOMs6s"]), ParsedMessage(`:Elizacat!a@a JOIN #ircv3`, ["batch": "4lMeQwsaOMs6s"])]);
		}
		batchProcessor.popFront();
		assert(batchProcessor.empty);
	}
	//Upcoming chathistory batch, subject to change
	{
		auto batchProcessor = new BatchProcessor;
		auto lines = [`:irc.host BATCH +sxtUfAeXBgNoD chathistory #channel`,
					`@batch=sxtUfAeXBgNoD;time=2015-06-26T19:40:31.230Z :foo!foo@example.com PRIVMSG #channel :I like turtles.`,
					`@batch=sxtUfAeXBgNoD;time=2015-06-26T19:43:53.410Z :bar!bar@example.com NOTICE #channel :Tortoises are better.`,
					`@batch=sxtUfAeXBgNoD;time=2015-06-26T19:48:18.140Z :irc.host PRIVMSG #channel :Squishy animals are inferior to computers.`,
					`:irc.host BATCH -sxtUfAeXBgNoD`];
		copy(lines, batchProcessor);
		{
			const batch = takeOne(batchProcessor).front;
			assert(batch.info.type == "chathistory");
			assert(batch.info.referenceTag == "sxtUfAeXBgNoD");
			assert(batch.info.parameters == ["#channel"]);
			assert(batch.lines == [ParsedMessage(":foo!foo@example.com PRIVMSG #channel :I like turtles.", ["time":"2015-06-26T19:40:31.230Z", "batch": "sxtUfAeXBgNoD"]), ParsedMessage(":bar!bar@example.com NOTICE #channel :Tortoises are better.", ["time":"2015-06-26T19:43:53.410Z", "batch": "sxtUfAeXBgNoD"]), ParsedMessage(`:irc.host PRIVMSG #channel :Squishy animals are inferior to computers.`, ["time":"2015-06-26T19:48:18.140Z", "batch": "sxtUfAeXBgNoD"])]);
		}
		batchProcessor.popFront();
		assert(batchProcessor.empty);
	}
	//ditto
	{
		auto batchProcessor = new BatchProcessor;
		auto lines = [`:irc.host BATCH +sxtUfAeXBgNoD chathistory remote`,
					`@batch=sxtUfAeXBgNoD;time=2015-06-26T19:40:31.230Z :remote!foo@example.com PRIVMSG local :I like turtles.`,
					`@batch=sxtUfAeXBgNoD;time=2015-06-26T19:43:53.410Z :local!bar@example.com PRIVMSG remote :Tortoises are better.`,
					`:irc.host BATCH -sxtUfAeXBgNoD`];
		copy(lines, batchProcessor);
		{
			const batch = takeOne(batchProcessor).front;
			assert(batch.info.type == "chathistory");
			assert(batch.info.referenceTag == "sxtUfAeXBgNoD");
			assert(batch.info.parameters == ["remote"]);
			assert(batch.lines == [ParsedMessage(":remote!foo@example.com PRIVMSG local :I like turtles.", ["time":"2015-06-26T19:40:31.230Z", "batch":"sxtUfAeXBgNoD"]), ParsedMessage(":local!bar@example.com PRIVMSG remote :Tortoises are better.", ["time":"2015-06-26T19:43:53.410Z", "batch": "sxtUfAeXBgNoD"])]);
		}
		batchProcessor.popFront();
		assert(batchProcessor.empty);
	}
	{ //Non-batch
		auto batchProcessor = new BatchProcessor;
		auto lines = [`@time=2015-06-26T19:40:31.230Z :remote!foo@example.com PRIVMSG local :I like turtles.`];
		copy(lines, batchProcessor);
		{
			const batch = takeOne(batchProcessor).front;
			assert(batch.lines == [ParsedMessage(":remote!foo@example.com PRIVMSG local :I like turtles.", ["time":"2015-06-26T19:40:31.230Z"])]);
		}
		batchProcessor.popFront();
		assert(batchProcessor.empty);
	}
	{ //Non-batch
		auto batchProcessor = new BatchProcessor;
		batchProcessor.put(`@time=2015-06-26T19:40:31.230Z :remote!foo@example.com PRIVMSG local :I like turtles.`);
		{
			const batch = takeOne(batchProcessor).front;
			assert(batch.lines == [ParsedMessage(":remote!foo@example.com PRIVMSG local :I like turtles.", ["time":"2015-06-26T19:40:31.230Z"])]);
		}
		batchProcessor.popFront();
		batchProcessor.put(`@time=2015-06-26T19:40:31.230Z :remote!foo@example.com PRIVMSG local :I like turtles.`);
		{
			const batch = takeOne(batchProcessor).front;
			assert(batch.lines == [ParsedMessage(":remote!foo@example.com PRIVMSG local :I like turtles.", ["time":"2015-06-26T19:40:31.230Z"])]);
		}
		batchProcessor.popFront();
		assert(batchProcessor.empty);
	}
}