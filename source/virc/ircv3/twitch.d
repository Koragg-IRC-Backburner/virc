/++
+ Module handling various IRC extensions used by Twitch.
+/
module virc.ircv3.twitch;

import std.algorithm;
import std.conv : to;
import std.range :  chain, choose, drop, only, takeNone;
import std.typecons : Nullable;

import virc.ircmessage;
import virc.ircv3.tags;

///
alias banReason = stringTag!"ban-reason";
///
alias banDuration = secondDurationTag!"ban-duration";
///
alias bits = typeTag!("slow", ulong);
///
alias broadcasterLang = stringTag!"broadcaster-lang";
///
alias color = stringTag!"color";
///
alias displayName = stringTag!"display-name";
//alias emoteSets = arrayTag!("emote-sets", string);
alias mod = booleanTag!"mod";
///
alias login = stringTag!"login";
///
alias msgID = stringTag!"msg-id";
///
alias r9k = booleanTag!"r9k";
///
alias roomID = stringTag!"room-id";
///
alias slow = typeTag!("slow", ulong);
///
alias subsOnly = booleanTag!"subs-only";
///
alias subscriber = booleanTag!"subscriber";
///
alias systemMsg = stringTag!"system-msg";
///
alias turbo = booleanTag!"turbo";
///
alias userID = stringTag!"user-id";
///
alias userType = stringTag!"user-type";
///
auto emotes(IRCTags tags) {
	auto parseTag(string str) {
		return str.splitter("/")
		.map!(x =>
			x
			.splitter(",")
			.map!(y => y.findSplitAfter(":")[1])
			.map!(y =>
				TwitchEmote(
					x.splitter(":").front.to!ulong,
					y.findSplitBefore("-")[0].to!ulong,
					y.findSplitAfter("-")[1].to!ulong
				)
			)
		)
		.joiner;
	}
	if ("emotes" in tags)
		return Nullable!(typeof(parseTag("")))(parseTag(tags["emotes"]));
	return Nullable!(typeof(parseTag(""))).init;
}
/++
+
+/
struct TwitchEmote {
	///
	ulong id;
	///
	ulong beginPosition;
	///
	ulong endPosition;
}

@safe pure /+nothrow+/ unittest { //Source: https://github.com/justintv/Twitch-API/blob/master/IRC.md
	{
		import std.algorithm.comparison : equal;
		auto parsed = IRCMessage("@badges=global_mod/1,turbo/1;color=#0D4200;display-name=TWITCH_UserNaME;emotes=25:0-4,12-16/1902:6-10;mod=0;room-id=1337;subscriber=0;turbo=1;user-id=1337;user-type=global_mod :twitch_username!twitch_username@twitch_username.tmi.twitch.tv PRIVMSG #channel :Kappa Keepo Kappa");
		assert(parsed.tags.mod == false);
		assert(parsed.tags.displayName == "TWITCH_UserNaME");
		//assert(parsed.tags.badges.equal(only("global_mod", "turbo")));
		assert(parsed.tags.color == "#0D4200");
		assert(parsed.tags.emotes.equal(only(TwitchEmote(25, 0, 4), TwitchEmote(25, 12, 16), TwitchEmote(1902, 6, 10))));
		assert(parsed.tags.subscriber == false);
		assert(parsed.tags.turbo == true);
		assert(parsed.tags.roomID == "1337");
		assert(parsed.tags.userType == "global_mod");
	}
	{
		auto parsed = IRCMessage("@color=#0D4200;display-name=TWITCH_UserNaME;emote-sets=0,33,50,237,793,2126,3517,4578,5569,9400,10337,12239;mod=1;subscriber=1;turbo=1;user-type=staff :tmi.twitch.tv USERSTATE #channel");
		assert(parsed.tags.emotes.isNull);
		assert(parsed.tags.color == "#0D4200");
		assert(parsed.tags.turbo == true);
		assert(parsed.tags.subscriber == true);
		assert(parsed.tags.mod == true);
		assert(parsed.tags.displayName == "TWITCH_UserNaME");
		assert(parsed.tags.userType == "staff");
	}
	{
		auto parsed = IRCMessage("@color=#0D4200;display-name=TWITCH_UserNaME;emote-sets=0,33,50,237,793,2126,3517,4578,5569,9400,10337,12239;turbo=0;user-id=1337;user-type=admin :tmi.twitch.tv GLOBALUSERSTATE");
		//assert(parsed.tags.emoteSets.equal(only("0", "33", "50", "237", "793", "2126", "3517", "4578", "5569", "9400", "10337", "12239")));
		assert(parsed.tags.color == "#0D4200");
		assert(parsed.tags.mod.isNull);
		assert(parsed.tags.displayName == "TWITCH_UserNaME");
		assert(parsed.tags.userID == "1337");
		assert(parsed.tags.turbo == false);
		assert(parsed.tags.slow.isNull);
		assert(parsed.tags.userType == "admin");
	}
	{
		auto parsed = IRCMessage("@broadcaster-lang=;r9k=0;slow=0;subs-only=0 :tmi.twitch.tv ROOMSTATE #channel");
		assert(parsed.tags.r9k == false);
		assert(parsed.tags.broadcasterLang == "");
		assert(parsed.tags.displayName.isNull);
		assert(parsed.tags.slow == 0);
		assert(parsed.tags.subsOnly == false);
	}
	{
		auto parsed = IRCMessage("@slow=10 :tmi.twitch.tv ROOMSTATE #channel");
		assert(parsed.tags.slow == 10);
	}
	{
		auto parsed = IRCMessage("@badges=staff/1,broadcaster/1,turbo/1;color=#008000;display-name=TWITCH_UserName;emotes=;mod=0;msg-id=resub;msg-param-months=6;room-id=1337;subscriber=1;system-msg=TWITCH_UserName\\shas\\ssubscribed\\sfor\\s6\\smonths!;login=twitch_username;turbo=1;user-id=1337;user-type=staff :tmi.twitch.tv USERNOTICE #channel :Great stream -- keep it up!");
		assert(parsed.tags.emotes.empty);
		assert(parsed.tags.color == "#008000");
		assert(parsed.tags.displayName == "TWITCH_UserName");
		assert(parsed.tags.systemMsg == "TWITCH_UserName has subscribed for 6 months!");
		assert(parsed.tags.roomID == "1337");
		assert(parsed.tags.userID == "1337");
		assert(parsed.tags.userType == "staff");
		assert(parsed.tags.subscriber == true);
		assert(parsed.tags.turbo == true);
		assert(parsed.tags.login == "twitch_username");
		assert(parsed.tags.msgID == "resub");
	}
	{
		auto parsed = IRCMessage("@badges=staff/1,broadcaster/1,turbo/1;color=#008000;display-name=TWITCH_UserName;emotes=;mod=0;msg-id=resub;msg-param-months=6;room-id=1337;subscriber=1;system-msg=TWITCH_UserName\\shas\\ssubscribed\\sfor\\s6\\smonths!;login=twitch_username;turbo=1;user-id=1337;user-type=staff :tmi.twitch.tv USERNOTICE #channel");
		assert(parsed.tags.emotes.empty);
		assert(parsed.tags.color == "#008000");
		assert(parsed.tags.displayName == "TWITCH_UserName");
		assert(parsed.tags.systemMsg == "TWITCH_UserName has subscribed for 6 months!");
		assert(parsed.tags.roomID == "1337");
		assert(parsed.tags.userID == "1337");
		assert(parsed.tags.userType == "staff");
		assert(parsed.tags.subscriber == true);
		assert(parsed.tags.turbo == true);
		assert(parsed.tags.login == "twitch_username");
		assert(parsed.tags.msgID == "resub");
	}
	{
		import core.time : seconds;
		auto parsed = IRCMessage("@ban-duration=1;ban-reason=Follow\\sthe\\srules :tmi.twitch.tv CLEARCHAT #channel :target_username");
		assert(parsed.tags.banDuration == 1.seconds);
		assert(parsed.tags.banReason == "Follow the rules");
	}
	{
		auto parsed = IRCMessage("@ban-reason=Follow\\sthe\\srules :tmi.twitch.tv CLEARCHAT #channel :target_username");
		assert(parsed.tags.banDuration.isNull);
		assert(parsed.tags.banReason == "Follow the rules");
	}
}