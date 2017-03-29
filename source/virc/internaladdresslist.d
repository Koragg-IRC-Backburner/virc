module virc.internaladdresslist;

import virc.common;

struct InternalAddressList {
	private User[string] users;
	void update(User user) {
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
	void rename(User user, string oldNick) {
		users[user.nickname] = users[oldNick];
		users.remove(oldNick);
		update(user);
	}
	void invalidate(string deadUser) {
		users.remove(deadUser);
	}
	User opIndex(string name) @safe {
		return users[name];
	}
	bool opIn_r(string name) @safe {
		return ((name in users) !is null);
	}
}
///
unittest {
	auto test = InternalAddressList();
	test.update((User("Test!testo@testy")));
	assert("Test" in test);
	assert("NotTest" !in test);
	assert(test["Test"] == User("Test!testo@testy"));
	test.update(User("Test!testo2@testy2"));
	assert(test["Test"] == User("Test!testo2@testy2"));
	test.update(User("Test"));
	assert(test["Test"] == User("Test!testo2@testy2"));

	test.rename(User("Test3"), "Test");
	assert(test["Test3"] == User("Test3!testo2@testy2"));

	assert("Test" !in test);

	test.invalidate("Test3");
	assert("Test3" !in test);
}