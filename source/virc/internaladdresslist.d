/++
+ Maintains user information for use where it may otherwise be missing.
+/
module virc.internaladdresslist;

import virc.common;

///
struct InternalAddressList {
	private User[string] users;
	///
	void update(User user) @safe pure nothrow {
		if (user.nickname !in users) {
			users[user.nickname] = user;
		} else {
			if (!user.account.isNull) {
				users[user.nickname].account = user.account;
			}
			if (!user.realName.isNull) {
				users[user.nickname].realName = user.realName;
			}
			if (!user.mask.ident.isNull) {
				users[user.nickname].mask.ident = user.mask.ident;
			}
			if (!user.mask.host.isNull) {
				users[user.nickname].mask.host = user.mask.host;
			}
			users[user.nickname].mask.nickname = user.mask.nickname;
		}
	}
	///
	void rename(User user, string oldNick) @safe pure nothrow {
		users[user.nickname] = users[oldNick];
		users.remove(oldNick);
		update(user);
	}
	///
	void invalidate(string deadUser) @safe pure nothrow {
		users.remove(deadUser);
	}
	///
	auto opIndex(string name) {
		return users[name];
	}
	///
	auto opIn_r(string name) {
		return ((name in users) !is null);
	}
}
///
@safe pure nothrow unittest {
	auto test = InternalAddressList();
	test.update((User("Test!testo@testy")));
	assert("Test" in test);
	assert("NotTest" !in test);
	assert(test["Test"] == User("Test!testo@testy"));
	auto testUser = User("Test!testo2@testy2");
	testUser.account = "Testly";
	testUser.realName = "Von Testington";
	test.update(testUser);
	assert(test["Test"] == User("Test!testo2@testy2"));
	assert(test["Test"].account == "Testly");
	assert(test["Test"].realName == "Von Testington");
	test.update(User("Test"));
	assert(test["Test"] == User("Test!testo2@testy2"));

	test.rename(User("Test3"), "Test");
	assert(test["Test3"] == User("Test3!testo2@testy2"));

	assert("Test" !in test);

	test.invalidate("Test3");
	assert("Test3" !in test);
}