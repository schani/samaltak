| check a b product wide retained stats |
check := [:ok :label | ok ifFalse: [
	Smalltalk vm stderrWrite: label, (String with: Character lf).
	Smalltalk quit: 1]].
a := 1 bitShift: 127.
check value: a = 170141183460469231731687303715884105728 value: 'small allocation'.
b := (1 bitShift: 65) + 3.
product := 6277101735386680764346212973589074111297417355611686830080.
wide := (1 bitShift: 1100000) + 37.
check value: (wide highBit = 1100001 and: [(wide bitAnd: 255) = 37]) value: 'large allocation'.
retained := Array new: 256.
24 timesRepeat: [
	1 to: retained size do: [:i | retained at: i put: (wide bitShift: -1099000) + i].
	1 to: 256 do: [:i |
		check value: a * b = product value: 'multiply'.
		check value: ((product + i) quo: b) = a value: 'quotient'.
		check value: ((product + i) rem: b) = i value: 'remainder'.
		check value: ((a negated + i) bitShift: -64) = -9223372036854775808 value: 'negative shift'].
	16 timesRepeat: [wide + a].
	(Delay forMilliseconds: 15) wait].
check value: ((retained last bitShift: -1000) = 1 and: [(retained last bitAnd: 511) = 256])
	value: 'retained result across C4 cycles'.
stats := Smalltalk vm primStatistics.
check value: (stats first = 0 and: [stats second = 0 and: [(stats at: 7) = 0]])
	value: 'legacy collection or eden use'.
Smalltalk vm stdoutWrite: 'C4 bignums ok', (String with: Character lf).
Smalltalk quit: 0
