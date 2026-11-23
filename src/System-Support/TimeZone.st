Object subclass: #TimeZone
	instanceVariableNames: 'name transitions offsets defaultOffset rule'
	classVariableNames: 'Local LocalStamp'
	package: 'System-Support'!

TimeZone comment: 'I am a time zone as the system keeps it: a TZif file (RFC 8536) of the zoneinfo database, its transitions between UTC offsets and, past the last one, the POSIX TZ rule in its footer (std offset dst [offset],Mm.w.d[/time],Mm.w.d[/time]). The VM counts time in UTC; I turn it into local time.

	TimeZone local                                   "$TZ, else /etc/localtime; read again when the file changes"
	TimeZone local offsetAt: Time utcMicroseconds // 1000000   "seconds east of UTC, e.g. -28800"
	TimeZone local today                             "the local Date"
	TimeZone fromFile: ''/usr/share/zoneinfo/Europe/Vienna''
	TimeZone fromRule: ''CET-1CEST,M3.5.0,M10.5.0/3'''!

!TimeZone methodsFor: 'initialization'!
setName: aString transitions: anArray offsets: offsetArray default: seconds rule: aRuleOrNil
	name := aString.
	transitions := anArray.
	offsets := offsetArray.
	defaultOffset := seconds.
	rule := aRuleOrNil
! !

!TimeZone methodsFor: 'accessing'!
name
	^name
!
offsetAt: utcSeconds
	"Seconds east of UTC in effect at utcSeconds (since 1970)."
	| lo hi |
	(transitions isEmpty or: [utcSeconds < transitions first]) ifTrue: [
		^(transitions isEmpty and: [rule notNil]) ifTrue: [self ruleOffsetAt: utcSeconds] ifFalse: [defaultOffset]].
	(utcSeconds >= transitions last and: [rule notNil]) ifTrue: [^self ruleOffsetAt: utcSeconds].
	"the last transition at or before utcSeconds"
	lo := 1.
	hi := transitions size.
	[lo < hi] whileTrue: [
		| mid |
		mid := (lo + hi + 1) // 2.
		(transitions at: mid) <= utcSeconds ifTrue: [lo := mid] ifFalse: [hi := mid - 1]].
	^offsets at: lo
!
localSecondsAt: utcSeconds
	^utcSeconds + (self offsetAt: utcSeconds)
!
dateAt: utcSeconds
	"The local Date at utcSeconds."
	^Date fromDays: (self localSecondsAt: utcSeconds) // 86400
!
today
	^self dateAt: Time utcMicroseconds // 1000000
! !

!TimeZone methodsFor: 'parsing'!
utcSecondsOf: aString
	"The seconds since 1970 (UTC; a Float with a fraction) of an ISO 8601 date and time, YYYY-MM-DD[THH:MM[:SS[.fff]]][Z|±HH[:]MM]; without an offset a time is local (in me), a date alone UTC, as JavaScript's Date reads them. nil if aString is not one."
	| s n date time fraction offset local tail |
	s := aString isString ifTrue: [aString trimBoth] ifFalse: [^nil].
	s size >= 10 ifFalse: [^nil].
	n := [:from :to | | v |
		v := 0.
		from to: to do: [:i | (s at: i) isDigit ifFalse: [^nil]. v := v * 10 + (s at: i) digitValue].
		v].
	((s at: 5) = $- and: [(s at: 8) = $-]) ifFalse: [^nil].
	date := Date year: (n value: 1 value: 4) month: (n value: 6 value: 7) day: (n value: 9 value: 10).
	s size = 10 ifTrue: [^date daysSinceEpoch * 86400].
	((s at: 11) = $T or: [(s at: 11) = $t or: [(s at: 11) = $ ]]) ifFalse: [^nil].
	s size >= 16 ifFalse: [^nil].
	(s at: 14) = $: ifFalse: [^nil].
	time := ((n value: 12 value: 13) * 3600) + ((n value: 15 value: 16) * 60).
	tail := 17.
	(s size >= 19 and: [(s at: 17) = $:]) ifTrue: [
		time := time + (n value: 18 value: 19).
		tail := 20].
	fraction := 0.
	(tail <= s size and: [(s at: tail) = $.]) ifTrue: [
		| start scale |
		start := tail + 1.
		tail := start.
		scale := 1.
		[tail <= s size and: [(s at: tail) isDigit]] whileTrue: [
			scale := scale / 10.
			fraction := fraction + ((s at: tail) digitValue * scale).
			tail := tail + 1].
		fraction := fraction asFloat].
	local := (date daysSinceEpoch * 86400) + time.
	tail > s size ifTrue: [^(local - (self offsetAt: local - (self offsetAt: local))) + fraction].
	((s at: tail) = $Z or: [(s at: tail) = $z]) ifTrue: [^local + fraction].
	((s at: tail) = $+ or: [(s at: tail) = $-]) ifFalse: [^nil].
	s size >= (tail + 2) ifFalse: [^nil].
	offset := (n value: tail + 1 value: tail + 2) * 3600.
	s size >= (tail + 4) ifTrue: [
		| m |
		m := (s at: tail + 3) = $: ifTrue: [tail + 4] ifFalse: [tail + 3].
		s size >= (m + 1) ifTrue: [offset := offset + ((n value: m value: m + 1) * 60)]].
	(s at: tail) = $- ifTrue: [offset := offset negated].
	^(local - offset) + fraction
! !

!TimeZone methodsFor: 'rules'!
ruleOffsetAt: utcSeconds
	"The POSIX rule's offset: {std. dst. startMonthWeekDay. startTime. endMonthWeekDay. endTime}, dst nil without daylight time."
	| std dst year local start end |
	std := rule at: 1.
	dst := rule at: 2.
	dst isNil ifTrue: [^std].
	local := utcSeconds + std.
	year := (Date fromDays: local // 86400) year.
	"the switches in UTC: to daylight time at its start in standard time, back at its end in daylight time"
	start := (self secondsOf: (rule at: 3) year: year) + (rule at: 4) - std.
	end := (self secondsOf: (rule at: 5) year: year) + (rule at: 6) - dst.
	start < end
		ifTrue: [^(utcSeconds >= start and: [utcSeconds < end]) ifTrue: [dst] ifFalse: [std]]
		ifFalse: [^(utcSeconds >= end and: [utcSeconds < start]) ifTrue: [std] ifFalse: [dst]]
!
secondsOf: monthWeekDay year: year
	"Mm.w.d: day d (0 Sunday) of week w (5 the last) of month m, at midnight, in seconds since 1970."
	| m w d first firstDow day last |
	m := monthWeekDay at: 1.
	w := monthWeekDay at: 2.
	d := monthWeekDay at: 3.
	first := Date year: year month: m day: 1.
	firstDow := first dayOfWeek - 1.
	day := 1 + ((d - firstDow) \\ 7) + ((w - 1) * 7).
	last := first daysInMonth.
	[day > last] whileTrue: [day := day - 7].
	^((Date year: year month: m day: day) daysSinceEpoch) * 86400
! !

!TimeZone methodsFor: 'printing'!
printOn: aStream
	aStream nextPutAll: 'a TimeZone '; nextPutAll: (name ifNil: ['?'])
! !

!TimeZone class methodsFor: 'instance creation'!
utc
	^self new setName: 'UTC' transitions: #() offsets: #() default: 0 rule: nil
!
local
	"The system's zone: $TZ (a file, :file or a zone name under /usr/share/zoneinfo, or a POSIX rule), else /etc/localtime; UTC if there is none. Read again when the file changes."
	| path stamp |
	path := self localPath.
	stamp := Array with: path with: ([File modificationTime: path] on: Error do: [:e | e return: nil]).
	(Local notNil and: [LocalStamp = stamp]) ifTrue: [^Local].
	Local := [path isNil
			ifTrue: [self fromRule: (Smalltalk vm getenv: 'TZ')]
			ifFalse: [self fromFile: path]]
		on: Error do: [:e | e return: self utc].
	LocalStamp := stamp.
	^Local
!
localPath
	"The TZif file of $TZ or /etc/localtime; nil if $TZ is a POSIX rule."
	| tz |
	tz := Smalltalk vm getenv: 'TZ'.
	(tz isNil or: [tz isEmpty]) ifTrue: [^'/etc/localtime'].
	(tz first = $:) ifTrue: [tz := tz allButFirst].
	(tz notEmpty and: [tz first = $/]) ifTrue: [^tz].
	(File exists: '/usr/share/zoneinfo/', tz) ifTrue: [^'/usr/share/zoneinfo/', tz].
	^nil
!
fromFile: aPath
	^self fromTZif: (File readBytes: aPath) name: aPath
!
fromTZif: bytes name: aString
	"Read a TZif file: the 64-bit data of version 2 and later (else the 32-bit), and the footer's rule."
	| header counts timeSize data times indices types offsets rule footer |
	((bytes copyFrom: 1 to: 4) asString = 'TZif') ifFalse: [^self error: 'not a TZif file'].
	header := 1.
	counts := self countsIn: bytes at: header.
	timeSize := 4.
	(bytes at: 5) >= 50 ifTrue: [
		"version 2 and later: skip the 32-bit block to the 64-bit one"
		header := header + 44 + (self dataSize: counts timeSize: 4).
		counts := self countsIn: bytes at: header.
		timeSize := 8].
	data := header + 44.
	times := (1 to: (counts at: 4)) collect: [:i | self signed: bytes at: data + ((i - 1) * timeSize) size: timeSize].
	data := data + ((counts at: 4) * timeSize).
	indices := (1 to: (counts at: 4)) collect: [:i | (bytes at: data + i - 1) + 1].
	data := data + (counts at: 4).
	types := (1 to: (counts at: 5)) collect: [:i | self signed: bytes at: data + ((i - 1) * 6) size: 4].
	offsets := indices collect: [:i | types at: i].
	rule := nil.
	timeSize = 8 ifTrue: [
		footer := self footerOf: bytes from: header + 44 + (self dataSize: counts timeSize: 8).
		footer isEmpty ifFalse: [rule := [self parseRule: footer] on: Error do: [:e | e return: nil]]].
	"before the first transition: type 0"
	^self new setName: aString transitions: times offsets: offsets default: (types isEmpty ifTrue: [0] ifFalse: [types first]) rule: rule
!
fromRule: aString
	"A zone of a POSIX TZ rule alone (UTC if aString is not one)."
	| rule |
	rule := (aString isNil or: [aString isEmpty]) ifTrue: [nil] ifFalse: [[self parseRule: aString] on: Error do: [:e | e return: nil]].
	rule isNil ifTrue: [^self utc].
	^self new setName: aString transitions: #() offsets: #() default: (rule at: 1) rule: rule
! !

!TimeZone class methodsFor: 'private'!
countsIn: bytes at: pos
	"isutcnt isstdcnt leapcnt timecnt typecnt charcnt of the header at pos."
	^(0 to: 5) collect: [:i | self unsigned: bytes at: pos + 20 + (i * 4) size: 4]
!
dataSize: counts timeSize: n
	"The bytes of a data block after its header."
	^((counts at: 4) * n) + (counts at: 4) + ((counts at: 5) * 6) + (counts at: 6) + ((counts at: 3) * (n + 4)) + (counts at: 2) + (counts at: 1)
!
footerOf: bytes from: pos
	"The rule between the newlines that follow the 64-bit block."
	| start stop |
	start := pos.
	(start <= bytes size and: [(bytes at: start) = 10]) ifFalse: [^''].
	stop := start + 1.
	[stop <= bytes size and: [(bytes at: stop) ~= 10]] whileTrue: [stop := stop + 1].
	^(bytes copyFrom: start + 1 to: stop - 1) asString
!
unsigned: bytes at: pos size: n
	| v |
	v := 0.
	0 to: n - 1 do: [:i | v := (v bitShift: 8) + (bytes at: pos + i)].
	^v
!
signed: bytes at: pos size: n
	| v |
	v := self unsigned: bytes at: pos size: n.
	^v >= (1 bitShift: n * 8 - 1) ifTrue: [v - (1 bitShift: n * 8)] ifFalse: [v]
!
parseRule: aString
	"{std. dst. start. startTime. end. endTime} of a POSIX TZ rule, offsets in seconds east of UTC; dst nil without daylight time."
	| s pos std dst start startTime end endTime readName readOffset readDate |
	s := aString.
	pos := 1.
	readName := [
		(pos <= s size and: [(s at: pos) = $<])
			ifTrue: [pos := (s indexOf: $> startingAt: pos) + 1]
			ifFalse: [[pos <= s size and: [(s at: pos) isLetter]] whileTrue: [pos := pos + 1]]].
	readOffset := [
		| sign h m sec |
		sign := 1.
		(pos <= s size and: [(s at: pos) = $+ or: [(s at: pos) = $-]]) ifTrue: [
			(s at: pos) = $- ifTrue: [sign := -1].
			pos := pos + 1].
		h := m := sec := 0.
		h := self readIntegerIn: s at: pos into: [:n :next | pos := next. n].
		(pos <= s size and: [(s at: pos) = $:]) ifTrue: [
			m := self readIntegerIn: s at: pos + 1 into: [:n :next | pos := next. n].
			(pos <= s size and: [(s at: pos) = $:]) ifTrue: [
				sec := self readIntegerIn: s at: pos + 1 into: [:n :next | pos := next. n]]].
		sign * ((h * 3600) + (m * 60) + sec)].
	readDate := [
		| parts time |
		(s at: pos) = $M ifFalse: [^self error: 'only Mm.w.d rules'].
		pos := pos + 1.
		parts := (1 to: 3) collect: [:i |
			| n |
			n := self readIntegerIn: s at: pos into: [:v :next | pos := next. v].
			(pos <= s size and: [(s at: pos) = $.]) ifTrue: [pos := pos + 1].
			n].
		time := 7200.
		(pos <= s size and: [(s at: pos) = $/]) ifTrue: [pos := pos + 1. time := readOffset value].
		Array with: parts with: time].
	readName value.
	"POSIX offsets are west of UTC"
	std := readOffset value negated.
	pos > s size ifTrue: [^Array with: std with: nil with: nil with: nil with: nil with: nil].
	readName value.
	dst := std + 3600.
	(pos <= s size and: [(s at: pos) ~= $,]) ifTrue: [dst := readOffset value negated].
	(pos <= s size and: [(s at: pos) = $,]) ifFalse: [^Array with: std with: nil with: nil with: nil with: nil with: nil].
	pos := pos + 1.
	start := readDate value.
	(s at: pos) = $, ifFalse: [^self error: 'bad rule'].
	pos := pos + 1.
	end := readDate value.
	startTime := start last. start := start first.
	endTime := end last. end := end first.
	^Array with: std with: dst with: start with: startTime with: end with: endTime
!
readIntegerIn: aString at: start into: aBlock
	"aBlock value: the decimal integer at start value: the position after it."
	| pos n |
	pos := start.
	n := 0.
	[pos <= aString size and: [(aString at: pos) isDigit]] whileTrue: [
		n := n * 10 + (aString at: pos) digitValue.
		pos := pos + 1].
	pos = start ifTrue: [^self error: 'number expected'].
	^aBlock value: n value: pos
! !
