class_name Fmt
## Text formatting helpers.


static func money(amount: int) -> String:
	return ("-$" if amount < 0 else "$") + thousands(absi(amount))


## 5.4 -> "5.40" with 2 places; trailing zeros are kept.
static func decimal(value: float, places: int) -> String:
	return String.num(value, places).pad_decimals(places)


## 45 -> "45 s", 90 -> "1 min 30 s"
static func duration(seconds: float) -> String:
	var total := roundi(seconds)
	if total < 60:
		return "%d s" % total
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
