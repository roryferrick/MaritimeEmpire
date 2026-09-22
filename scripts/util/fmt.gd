class_name Fmt
## Text formatting helpers.


static func money(amount: int) -> String:
	return ("-$" if amount < 0 else "$") + thousands(absi(amount))


## 12345 -> "12,345"
static func thousands(n: int) -> String:
	var digits := str(absi(n))
	var out := ""
	while digits.length() > 3:
		out = "," + digits.right(3) + out
		digits = digits.left(digits.length() - 3)
	return ("-" if n < 0 else "") + digits + out
