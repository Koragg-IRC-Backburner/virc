/++
+ Module for dealing with IRC formatting.
+/
module virc.style;

///
enum MIRCColours {
	///RGB(255,255,255)
	white = 0,
	///RGB(0,0,0)
	black = 1,
	///RGB(0,0,127)
	blue = 2,
	///RGB(0,147,0)
	green = 3,
	///RGB(255,0,0)
	lightRed = 4,
	///RGB(127,0,0)
	brown = 5,
	///RGB(156,0,156)
	purple = 6,
	///RGB(252,127,0)
	orange = 7,
	///RGB(255,255,0)
	yellow = 8,
	///RGB(0,252,0)
	lightGreen = 9,
	///RGB(0,147,147)
	cyan = 10,
	///RGB(0,255,255)
	lightCyan = 11,
	///RGB(0,0,252)
	lightBlue = 12,
	///RGB(255,0,255)
	pink = 13,
	///RGB(127,127,127)
	grey = 14,
	///RGB(210,210,210)
	lightGrey = 15,
	///"Default" colour
	transparent = 99
}

///
enum ControlCharacters {
	///
	bold = '\x02',
	///
	underline = '\x1F',
	///
	italic = '\x1D',
	///
	plain = '\x0F',
	///
	color = '\x03',
	///
	extendedColor = '\x04',
	///
	reverse = '\x16'
}