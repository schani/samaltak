Object subclass: #AgentUsage
	instanceVariableNames: 'record'
	classVariableNames: ''
	package: 'Agents'!

AgentUsage comment: 'I am one agent subscription''s usage as omarchy-agent-usage-update records it in ~/.local/state/omarchy/agents/usage/<id>.json (the bar''s Agents widget keeps those fresh): its name and plan, its rate-limit windows and its prepaid balance. I name and time the windows as the bar''s Agents panel and the desktop card do (windowsAt:): a window''s title (Session, Weekly, Monthly or its own), how full it is, when it resets, and its pace (how far through its span it is).

	(AgentUsage fromJSON: (File readText: path)) windowsAt: Time utcMicroseconds / 1000000'!

!AgentUsage methodsFor: 'initialization'!
setRecord: aDictionary
	record := aDictionary
! !

!AgentUsage methodsFor: 'accessing'!
at: aKey
	^record at: aKey ifAbsent: [nil]
!
id
	^self at: 'id'
!
name
	| n |
	n := self at: 'name'.
	^(n isString and: [n notEmpty]) ifTrue: [n] ifFalse: [self id]
!
tierLabel
	| t |
	t := self at: 'tierLabel'.
	^t isString ifTrue: [t] ifFalse: ['']
!
isStale
	^(self at: 'limitsStale') == true
!
limits
	| l |
	l := self at: 'limits'.
	^(l isKindOf: Array) ifTrue: [l select: [:each | each isKindOf: Dictionary]] ifFalse: [#()]
!
balance
	"{remaining. funded. currency}, or nil without a balance."
	| b remaining funded |
	b := self at: 'balance'.
	(b isKindOf: Dictionary) ifFalse: [^nil].
	remaining := self class number: (b at: 'remaining' ifAbsent: [nil]).
	remaining isNil ifTrue: [^nil].
	funded := (self class number: (b at: 'funded' ifAbsent: [nil])) ifNil: [0].
	^Array with: remaining with: funded with: (b at: 'currency' ifAbsent: ['USD'])
!
hasBalance
	^self balance notNil
!
windowsAt: nowSeconds
	"Each limit with a percentage: {title. percent (0 once it reset). seconds until it resets (-1 if unknown or past). pace (0..1, -1 if unknown)}."
	| out |
	out := OrderedCollection new.
	self limits do: [:e |
		| percent reset expired title span pace |
		percent := self class number: (e at: 'percent' ifAbsent: [nil]).
		(percent notNil and: [percent >= 0]) ifTrue: [
			reset := TimeZone local utcSecondsOf: (e at: 'resetsAt' ifAbsent: [nil]).
			expired := reset notNil and: [reset <= nowSeconds].
			title := e at: 'title' ifAbsent: [nil].
			(title isString and: [title notEmpty]) ifFalse: [title := self class windowTitle: (e at: 'label' ifAbsent: [''])].
			"a model-scoped label (Fable Weekly) still names its window's span"
			span := self class windowSpan: (e at: 'label' ifAbsent: ['']).
			span = 0 ifTrue: [span := self class windowSpan: title].
			pace := -1.
			(expired not and: [reset notNil and: [span > 0]]) ifTrue: [
				pace := ((1 - ((reset - nowSeconds) / span)) max: 0) min: 1].
			out add: (Array
				with: title
				with: (expired ifTrue: [0] ifFalse: [percent])
				with: ((expired or: [reset isNil]) ifTrue: [-1] ifFalse: [reset - nowSeconds])
				with: pace)]].
	^out asArray
!
isShown
	"The card leaves out agents with neither a window nor a balance."
	^(self windowsAt: 0) notEmpty or: [self hasBalance]
! !

!AgentUsage methodsFor: 'printing'!
printOn: aStream
	aStream nextPutAll: 'an AgentUsage '; print: self id
! !

!AgentUsage class methodsFor: 'instance creation'!
fromJSON: aString
	"An AgentUsage of a record, nil if it is not one (no id)."
	| r |
	r := [JSON parse: aString] on: Error do: [:e | e return: nil].
	(r isKindOf: Dictionary) ifFalse: [^nil].
	(r at: 'id' ifAbsent: [nil]) isString ifFalse: [^nil].
	^self new setRecord: r
! !

!AgentUsage class methodsFor: 'records'!
order
	"The bar's order of the agents; others follow by name."
	^#('claude' 'codex' 'grok' 'kimi' 'cursor' 'grokbot' 'copilot' 'muse' 'agy' 'kimchi' 'hermes' 'devin' 'vibe' 'qwen'
		'opencode' 'zai' 'ollama' 'minimax' 'openrouter' 'deepseek' 'fireworks' 'synthetic' 'local')
!
directory
	^XDG state: 'omarchy/agents/usage'
!
recordsIn: aDirectory hiding: hiddenIds
	"The records of aDirectory the card shows (not hidden, with a window or a balance), in the bar's order."
	| out |
	out := OrderedCollection new.
	([Directory fileNames: aDirectory] on: Error do: [:e | e return: #()]) do: [:file |
		(file endsWith: '.json') ifTrue: [
			| u |
			u := self fromJSON: ([File readText: (File join: aDirectory with: file)] on: Error do: [:e | e return: nil]).
			(u notNil and: [(hiddenIds includes: u id) not and: [u isShown]]) ifTrue: [out add: u]]].
	^out asArray sort: [:a :b | | ia ib |
		ia := self order indexOf: a id. ia = 0 ifTrue: [ia := 999].
		ib := self order indexOf: b id. ib = 0 ifTrue: [ib := 999].
		ia = ib ifTrue: [a name asString <= b name asString] ifFalse: [ia < ib]]
! !

!AgentUsage class methodsFor: 'windows'!
windowIsLong: lowercaseText
	^#('week' '7-day' 'seven' 'month' '30-day') anySatisfy: [:w | lowercaseText includesSubstring: w]
!
windowSpan: aLabel
	"The seconds a window named aLabel spans: a month, a week, n hours or n minutes; 0 if it does not say."
	| text |
	text := aLabel isString ifTrue: [aLabel asLowercase] ifFalse: [''].
	((text includesSubstring: 'month') or: [text includesSubstring: '30-day']) ifTrue: [^30 * 86400].
	(self windowIsLong: text) ifTrue: [^7 * 86400].
	(self count: text unit: #('hour' 'h')) ifNotNil: [:n | ^n * 3600].
	(self count: text unit: #('minutes' 'minute' 'mins' 'min' 'm')) ifNotNil: [:n | ^n * 60].
	^0
!
count: text unit: unitNames
	"The first number in text followed (after spaces, a dash, spaces) by one of unitNames ending a word: 5h, 5-hour, 30 min."
	| i |
	i := 1.
	[i <= text size] whileTrue: [
		(text at: i) isDigit
			ifTrue: [
				| n j |
				n := 0.
				j := i.
				[j <= text size and: [(text at: j) isDigit]] whileTrue: [n := n * 10 + (text at: j) digitValue. j := j + 1].
				[j <= text size and: [(text at: j) = $ ]] whileTrue: [j := j + 1].
				(j <= text size and: [(text at: j) = $-]) ifTrue: [j := j + 1].
				[j <= text size and: [(text at: j) = $ ]] whileTrue: [j := j + 1].
				unitNames do: [:u |
					| k |
					k := j + u size.
					((text copyFrom: j to: (k - 1 min: text size)) = u
						and: [k > text size or: [((text at: k) isLetter or: [(text at: k) isDigit or: [(text at: k) = $_]]) not]])
							ifTrue: [^n]].
				i := j max: i + 1]
			ifFalse: [i := i + 1]].
	^nil
!
windowTitle: aLabel
	"Monthly, Weekly, Session, or the label without its parenthesis (Limit if empty)."
	| text plain open |
	text := aLabel isString ifTrue: [aLabel asLowercase] ifFalse: [''].
	(text includesSubstring: 'month') ifTrue: [^'Monthly'].
	(self windowIsLong: text) ifTrue: [^'Weekly'].
	((text includesSubstring: 'session') or: [(self windowSpan: aLabel) > 0]) ifTrue: [^'Session'].
	plain := aLabel isString ifTrue: [aLabel] ifFalse: [''].
	"the card's replace(/\s*\(.*\)\s*/, ''): the first ( to the last ) and the spaces around them"
	open := plain indexOf: $(.
	open > 0 ifTrue: [
		| close |
		close := plain lastIndexOf: $).
		close > open ifTrue: [
			plain := (plain copyFrom: 1 to: open - 1) trimRight, (plain copyFrom: close + 1 to: plain size) trimLeft]].
	plain := plain trimBoth.
	^plain isEmpty ifTrue: ['Limit'] ifFalse: [plain]
! !

!AgentUsage class methodsFor: 'formatting'!
duration: seconds
	"Until a reset: 42m, 3h 5m, 6d 4h; empty if unknown."
	| m h |
	seconds < 0 ifTrue: [^''].
	m := (seconds / 60) rounded.
	m < 60 ifTrue: [^m printString, 'm'].
	h := m // 60.
	h < 24 ifTrue: [^h printString, 'h ', (m \\ 60) printString, 'm'].
	^(h // 24) printString, 'd ', (h \\ 24) printString, 'h'
!
percent: aFraction
	^(self grouped: (aFraction * 100) rounded), '%'
!
money: aNumber currency: aCode
	"$12.50, €3.00, £1,024.10, CHF 5.00."
	| code prefix cents |
	code := aCode isString ifTrue: [aCode asUppercase] ifFalse: ['USD'].
	prefix := code = 'USD' ifTrue: ['$'] ifFalse: [code = 'EUR' ifTrue: ['€'] ifFalse: [code = 'GBP' ifTrue: ['£'] ifFalse: [code, ' ']]].
	cents := ((aNumber ifNil: [0]) * 100) rounded.
	^prefix, (cents < 0 ifTrue: ['-'] ifFalse: ['']), (self grouped: cents abs // 100), '.', ((cents abs \\ 100) printPaddedWith: $0 to: 2)
!
grouped: anInteger
	"anInteger with a comma between thousands."
	| digits out |
	digits := anInteger abs printString.
	out := WriteStream on: String new.
	anInteger < 0 ifTrue: [out nextPut: $-].
	digits doWithIndex: [:c :i |
		(i > 1 and: [(digits size - i + 1) \\ 3 = 0]) ifTrue: [out nextPut: $,].
		out nextPut: c].
	^out contents
!
number: anObject
	"A JSON number, or a string of one; nil otherwise."
	anObject isNumber ifTrue: [^(anObject isFloat and: [anObject isNaN or: [anObject isInfinite]]) ifTrue: [nil] ifFalse: [anObject]].
	anObject isString ifTrue: [^[anObject trimBoth asNumber] on: Error do: [:e | e return: nil]].
	^nil
! !
