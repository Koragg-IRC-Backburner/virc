module virc.batch;
import virc.tags;


import std.stdio : writeln;
struct BatchProcessor {
	parsedMessage[] batchless;
	private Batch[string] batchCache;
	Batch[] batches;
	bool[] consumeBatch;
	void put(string line) {
		put(line.splitTag());
	}
	void put(parsedMessage splitMsg) {
		auto processed = BatchCommand(splitMsg.msg);
		Batch newBatch;
		if (processed.isValid && processed.isNew) {
			newBatch.referenceTag = processed.referenceTag;
			newBatch.type = processed.type;
			newBatch.parameters = processed.parameters;
		}
		if ("batch" !in splitMsg.tags) {
			if (processed.isValid) {
				if (processed.isNew) {
					batchCache[newBatch.referenceTag] = newBatch;
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
			void findBatch(ref Batch[string] searchBatches, string identifier) {
				foreach (ref batch; searchBatches) {
					if (batch.referenceTag == identifier) {
						if (processed.isValid) {
							if (processed.isNew)
								batch.nestedBatches[newBatch.referenceTag] = newBatch;
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
	bool empty() {
		import std.range : empty;
		return (batches.empty && batchless.empty);
	}
	void popFront() {
		if (consumeBatch[0]) {
			batches = batches[1..$];
		} else
			batchless = batchless[1..$];
		consumeBatch = consumeBatch[1..$];
	}
	Batch front() {
		if (consumeBatch[0])
			return batches[0];
		else
			return Batch(false, "", "NOT A BATCH", [], [batchless[0]]);
	}
}
private struct BatchCommand {
	this(string msg) {
		import std.string : split, toUpper;
		auto splitMsg = msg.split(" ");
		if ((splitMsg.length <= 2) || (splitMsg[1].toUpper() != "BATCH"))
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
	bool isClosed() { return !isNew; }
	bool isValid = false;
}
struct Batch {
	bool isValidBatch = true;
	string referenceTag; ///A simple string identifying the batch. Uniqueness is not guaranteed?
	string type; ///Indicates how the batch is to be processed. Examples include netsplit, netjoin, chathistory
	string[] parameters; ///Miscellaneous details associated with the batch. Meanings vary based on type.
	parsedMessage[] lines; ///Lines captured minus the batch tag and starting/ending commands.
	Batch[string] nestedBatches; ///Any batches nested inside this one.
	void put(parsedMessage line) {
		lines ~= line;
	}
}
unittest {
	import std.range : isOutputRange, isInputRange, takeOne;
	import std.algorithm : copy;
	static assert(isOutputRange!(BatchProcessor, string), "BatchProcessor failed outputrange test");
	static assert(isInputRange!BatchProcessor, "BatchProcessor failed inputrange test");
	//Example from http://ircv3.net/specs/extensions/batch-3.2.html
	{
		BatchProcessor batchProcessor;
		auto lines = [`:irc.host BATCH +yXNAbvnRHTRBv netsplit irc.hub other.host`,
					`@batch=yXNAbvnRHTRBv :aji!a@a QUIT :irc.hub other.host`,
					`@batch=yXNAbvnRHTRBv :nenolod!a@a QUIT :irc.hub other.host`,
					`:nick!user@host PRIVMSG #channel :This is not in batch, so processed immediately`,
					`@batch=yXNAbvnRHTRBv :jilles!a@a QUIT :irc.hub other.host`,
					`:irc.host BATCH -yXNAbvnRHTRBv`];
		copy(lines, &batchProcessor);
		{
			auto batch = takeOne(batchProcessor).front;
			assert(batch.lines == [parsedMessage(":nick!user@host PRIVMSG #channel :This is not in batch, so processed immediately")]);
		}
		batchProcessor.popFront();
		{
			auto batch = takeOne(batchProcessor).front;
			assert(batch.referenceTag == `yXNAbvnRHTRBv`);
			assert(batch.type == `netsplit`);
			assert(batch.parameters == [`irc.hub`, `other.host`]);
			assert(batch.lines == [parsedMessage(`:aji!a@a QUIT :irc.hub other.host`, ["batch": "yXNAbvnRHTRBv"]), parsedMessage(`:nenolod!a@a QUIT :irc.hub other.host`, ["batch": "yXNAbvnRHTRBv"]), parsedMessage(`:jilles!a@a QUIT :irc.hub other.host`, ["batch": "yXNAbvnRHTRBv"])]);
		}
		batchProcessor.popFront();
		assert(batchProcessor.empty);
	}
	//ditto
	{
		BatchProcessor batchProcessor;
		auto lines = [`:irc.host BATCH +1 example.com/foo`,
					`@batch=1 :nick!user@host PRIVMSG #channel :Message 1`,
					`:irc.host BATCH +2 example.com/foo`,
					`@batch=1 :nick!user@host PRIVMSG #channel :Message 2`,
					`@batch=2 :nick!user@host PRIVMSG #channel :Message 4`,
					`@batch=1 :nick!user@host PRIVMSG #channel :Message 3`,
					`:irc.host BATCH -1`,
					`@batch=2 :nick!user@host PRIVMSG #channel :Message 5`,
					`:irc.host BATCH -2`];
		copy(lines, &batchProcessor);
		{
			auto batch = takeOne(batchProcessor).front;
			assert(batch.type == "example.com/foo");
			assert(batch.referenceTag == "1");
			assert(batch.lines == [parsedMessage(":nick!user@host PRIVMSG #channel :Message 1", ["batch": "1"]), parsedMessage(":nick!user@host PRIVMSG #channel :Message 2", ["batch": "1"]), parsedMessage(":nick!user@host PRIVMSG #channel :Message 3", ["batch": "1"])]);
		}
		batchProcessor.popFront();
		{
			auto batch = takeOne(batchProcessor).front;
			assert(batch.type == "example.com/foo");
			assert(batch.referenceTag == "2");
			assert(batch.lines == [parsedMessage(":nick!user@host PRIVMSG #channel :Message 4", ["batch": "2"]), parsedMessage(":nick!user@host PRIVMSG #channel :Message 5", ["batch": "2"])]);
		}
		batchProcessor.popFront();
		assert(batchProcessor.empty);
	}
	//ditto
	{
		BatchProcessor batchProcessor;
		auto lines = [`:irc.host BATCH +outer example.com/foo`,
					`@batch=outer :irc.host BATCH +inner example.com/bar`,
					`@batch=inner :nick!user@host PRIVMSG #channel :Hi`,
					`@batch=outer :irc.host BATCH -inner`,
					`:irc.host BATCH -outer`];
		copy(lines, &batchProcessor);
		{
			auto batch = takeOne(batchProcessor).front;
			assert(batch.type == "example.com/foo");
			assert(batch.referenceTag == "outer");
			assert(batch.parameters == []);
			assert(batch.lines == []);
			assert("inner" in batch.nestedBatches);
			assert(batch.nestedBatches["inner"].type == "example.com/bar");
			assert(batch.nestedBatches["inner"].referenceTag == "inner");
			assert(batch.nestedBatches["inner"].parameters == []);
			assert(batch.nestedBatches["inner"].lines == [parsedMessage(":nick!user@host PRIVMSG #channel :Hi", ["batch": "inner"])]);
		}
		batchProcessor.popFront();
		assert(batchProcessor.empty);
	}
	//Example from http://ircv3.net/specs/extensions/batch/netsplit-3.2.html
	{
		BatchProcessor batchProcessor;
		auto lines = [`:irc.host BATCH +yXNAbvnRHTRBv netsplit irc.hub other.host`,
					`@batch=yXNAbvnRHTRBv :aji!a@a QUIT :irc.hub other.host`,
					`@batch=yXNAbvnRHTRBv :nenolod!a@a QUIT :irc.hub other.host`,
					`@batch=yXNAbvnRHTRBv :jilles!a@a QUIT :irc.hub other.host`,
					`:irc.host BATCH -yXNAbvnRHTRBv`];
		copy(lines, &batchProcessor);
		{
			auto batch = takeOne(batchProcessor).front;
			assert(batch.type == "netsplit");
			assert(batch.referenceTag == "yXNAbvnRHTRBv");
			assert(batch.parameters == ["irc.hub", "other.host"]);
			assert(batch.lines == [parsedMessage(":aji!a@a QUIT :irc.hub other.host", ["batch": "yXNAbvnRHTRBv"]), parsedMessage(":nenolod!a@a QUIT :irc.hub other.host", ["batch": "yXNAbvnRHTRBv"]), parsedMessage(`:jilles!a@a QUIT :irc.hub other.host`, ["batch": "yXNAbvnRHTRBv"])]);
		}
		batchProcessor.popFront();
		assert(batchProcessor.empty);
	}
	//ditto
	{
		BatchProcessor batchProcessor;
		auto lines = [`:irc.host BATCH +4lMeQwsaOMs6s netjoin irc.hub other.host`,
					`@batch=4lMeQwsaOMs6s :aji!a@a JOIN #atheme`,
					`@batch=4lMeQwsaOMs6s :nenolod!a@a JOIN #atheme`,
					`@batch=4lMeQwsaOMs6s :jilles!a@a JOIN #atheme`,
					`@batch=4lMeQwsaOMs6s :nenolod!a@a JOIN #ircv3`,
					`@batch=4lMeQwsaOMs6s :jilles!a@a JOIN #ircv3`,
					`@batch=4lMeQwsaOMs6s :Elizacat!a@a JOIN #ircv3`,
					`:irc.host BATCH -4lMeQwsaOMs6s`];
		copy(lines, &batchProcessor);
		{
			auto batch = takeOne(batchProcessor).front;
			assert(batch.type == "netjoin");
			assert(batch.referenceTag == "4lMeQwsaOMs6s");
			assert(batch.parameters == ["irc.hub", "other.host"]);
			assert(batch.lines == [parsedMessage(":aji!a@a JOIN #atheme", ["batch": "4lMeQwsaOMs6s"]), parsedMessage(":nenolod!a@a JOIN #atheme", ["batch": "4lMeQwsaOMs6s"]), parsedMessage(`:jilles!a@a JOIN #atheme`, ["batch": "4lMeQwsaOMs6s"]), parsedMessage(`:nenolod!a@a JOIN #ircv3`, ["batch": "4lMeQwsaOMs6s"]), parsedMessage(`:jilles!a@a JOIN #ircv3`, ["batch": "4lMeQwsaOMs6s"]), parsedMessage(`:Elizacat!a@a JOIN #ircv3`, ["batch": "4lMeQwsaOMs6s"])]);
		}
		batchProcessor.popFront();
		assert(batchProcessor.empty);
	}
	//Upcoming chathistory batch, subject to change
	{
		BatchProcessor batchProcessor;
		auto lines = [`:irc.host BATCH +sxtUfAeXBgNoD chathistory #channel`,
					`@batch=sxtUfAeXBgNoD;time=2015-06-26T19:40:31.230Z :foo!foo@example.com PRIVMSG #channel :I like turtles.`,
					`@batch=sxtUfAeXBgNoD;time=2015-06-26T19:43:53.410Z :bar!bar@example.com NOTICE #channel :Tortoises are better.`,
					`@batch=sxtUfAeXBgNoD;time=2015-06-26T19:48:18.140Z :irc.host PRIVMSG #channel :Squishy animals are inferior to computers.`,
					`:irc.host BATCH -sxtUfAeXBgNoD`];
		copy(lines, &batchProcessor);
		{
			auto batch = takeOne(batchProcessor).front;
			assert(batch.type == "chathistory");
			assert(batch.referenceTag == "sxtUfAeXBgNoD");
			assert(batch.parameters == ["#channel"]);
			assert(batch.lines == [parsedMessage(":foo!foo@example.com PRIVMSG #channel :I like turtles.", ["time":"2015-06-26T19:40:31.230Z", "batch": "sxtUfAeXBgNoD"]), parsedMessage(":bar!bar@example.com NOTICE #channel :Tortoises are better.", ["time":"2015-06-26T19:43:53.410Z", "batch": "sxtUfAeXBgNoD"]), parsedMessage(`:irc.host PRIVMSG #channel :Squishy animals are inferior to computers.`, ["time":"2015-06-26T19:48:18.140Z", "batch": "sxtUfAeXBgNoD"])]);
		}
		batchProcessor.popFront();
		assert(batchProcessor.empty);
	}
	//ditto
	{
		BatchProcessor batchProcessor;
		auto lines = [`:irc.host BATCH +sxtUfAeXBgNoD chathistory remote`,
					`@batch=sxtUfAeXBgNoD;time=2015-06-26T19:40:31.230Z :remote!foo@example.com PRIVMSG local :I like turtles.`,
					`@batch=sxtUfAeXBgNoD;time=2015-06-26T19:43:53.410Z :local!bar@example.com PRIVMSG remote :Tortoises are better.`,
					`:irc.host BATCH -sxtUfAeXBgNoD`];
		copy(lines, &batchProcessor);
		{
			auto batch = takeOne(batchProcessor).front;
			assert(batch.type == "chathistory");
			assert(batch.referenceTag == "sxtUfAeXBgNoD");
			assert(batch.parameters == ["remote"]);
			assert(batch.lines == [parsedMessage(":remote!foo@example.com PRIVMSG local :I like turtles.", ["time":"2015-06-26T19:40:31.230Z", "batch":"sxtUfAeXBgNoD"]), parsedMessage(":local!bar@example.com PRIVMSG remote :Tortoises are better.", ["time":"2015-06-26T19:43:53.410Z", "batch": "sxtUfAeXBgNoD"])]);
		}
		batchProcessor.popFront();
		assert(batchProcessor.empty);
	}
}