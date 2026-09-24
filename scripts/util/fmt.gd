class_name Fmt
## Text formatting helpers.


static func money(amount: int) -> String:
	return ("-$" if amount < 0 else "$") + thousands(absi(amount))


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
