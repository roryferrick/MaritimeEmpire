class_name Fmt
## Text formatting helpers.


static func money(amount: int) -> String:
	return ("-$" if amount < 0 else "$") + thousands(absi(amount))


## Money to 3 significant figures from $100k up, for tight tables:
## 23080085871 -> "$23.1B", -571387754 -> "-$571M", 1830000 -> "$1.83M",
## 985485 -> "$985k"; below $100k as money() ("$29,509").
static func money_short(amount: int) -> String:
	var size := absf(amount)
	if size < 1e5:
		return money(amount)
	var unit := "B" if size >= 1e9 else ("M" if size >= 1e6 else "k")
	var scaled: float = size / {B = 1e9, M = 1e6, k = 1e3}[unit]
	var places := 2 if scaled < 10.0 else (1 if scaled < 100.0 else 0)
	return "%s$%s%s" % ["-" if amount < 0 else "", String.num(scaled, places), unit]


## 5.4 -> "5.40" with 2 places; trailing zeros are kept.
static func decimal(value: float, places: int) -> String:
	return String.num(value, places).pad_decimals(places)


## 45 -> "45 s", 90 -> "1 min 30 s", 4380 -> "1 h 13 min"
static func duration(seconds: float) -> String:
	var total := roundi(seconds)
	if total < 60:
		return "%d s" % total
	if total >= 3600:
		var hours := floori(total / 3600.0)
		var mins := floori((total % 3600) / 60.0)
		return "%d h" % hours if mins == 0 else "%d h %d min" % [hours, mins]
	var minutes := floori(total / 60.0)
	if total % 60 == 0:
		return "%d min" % minutes
	return "%d min %d s" % [minutes, total % 60]


## 12345 -> "12,345"
static func thousands(n: int) -> String:
	var digits := str(absi(n))
	var out := ""
	while digits.length() > 3:
		out = "," + digits.right(3) + out
		digits = digits.left(digits.length() - 3)
	return ("-" if n < 0 else "") + digits + out


## 1830000 -> "1.83M", 555000 -> "555k", 7950 -> "7,950"
static func short(n: float) -> String:
	if absf(n) >= 1e6:
		return String.num(n / 1e6, 2 if absf(n) < 1e7 else 1).trim_suffix(".0") + "M"
	if absf(n) >= 1e5:
		return "%dk" % roundi(n / 1e3)
	return thousands(roundi(n))


## Like duration(), but rounded to whole minutes from a minute up:
## 45 -> "45 s", 100 -> "2 min", 4380 -> "1 h 13 min"
static func rough_duration(seconds: float) -> String:
	return duration(seconds if seconds < 60.0 else roundf(seconds / 60.0) * 60.0)


## 1 -> "1st", 2 -> "2nd", 11 -> "11th", 23 -> "23rd"
static func ordinal(n: int) -> String:
	var suffix := "th"
	if n % 100 < 11 or n % 100 > 13:
		suffix = ["th", "st", "nd", "rd", "th", "th", "th", "th", "th", "th"][n % 10]
	return "%d%s" % [n, suffix]


const _DAYS := ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
const _MONTHS := ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]


## A Unix time as "Sat 1 Jan 2000, 14:30".
static func calendar(unix_time: int) -> String:
	var d := Time.get_datetime_dict_from_unix_time(unix_time)
	return "%s %d %s %d, %02d:%02d" % [_DAYS[d.weekday], d.day, _MONTHS[d.month - 1], d.year, d.hour, d.minute]


## A Unix time as "3 Jan 09:10" (no weekday or year), for arrivals and log lines.
static func calendar_short(unix_time: int) -> String:
	var d := Time.get_datetime_dict_from_unix_time(unix_time)
	return "%d %s %02d:%02d" % [d.day, _MONTHS[d.month - 1], d.hour, d.minute]


## Calendar seconds as "45 min", "20 h" or "31 days 4 h".
static func calendar_duration(seconds: float) -> String:
	var minutes := roundi(seconds / 60.0)
	if minutes < 60:
		return "%d min" % minutes
	var hours := roundi(seconds / 3600.0)
	if hours < 48:
		return "%d h" % hours
	var days := floori(seconds / 86400.0)
	var rest := roundi((seconds - days * 86400.0) / 3600.0)
	return "%d days" % days if rest == 0 else "%d days %d h" % [days, rest]
