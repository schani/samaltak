Object subclass: #WodifyService
	instanceVariableNames: 'configPath cachePath refreshMinutes process wakeup onChange client clientKey ok error url days loading retrySoon lastAttempt today configStamp'
	classVariableNames: ''
	package: 'Wodify'!

WodifyService comment: 'I keep today''s and tomorrow''s workouts current, in a Process of my own, as the desktop card''s wodify.py and its timers do: I fetch them (WodifyClient) when I start, when the local day changes, when ~/.config/omarchy/wodify.json changes, every refreshMinutes (30, at least 10) and a minute after network trouble (not after a rejected password: trying that every minute could lock the account). My Process looks at the wall clock every two seconds, so a fetch due while the machine slept happens as it wakes. After every attempt onChange runs (in my Process).

What I fetched is kept in ~/.local/state/samaltak/wodify/last.json (the workouts only) and shown, marked offline, while Wodify cannot be reached.

The config:
	{ "host": "<gym>.wodify.com", "email": "...", "password": "...", "gym": "<one of the account''s gyms>" }   (chmod 600; gym optional)

	service := WodifyService new onChange: [:s | ...]; start.
	service days. service isOk. service error. service url. service refreshNow. service stop'!

!WodifyService methodsFor: 'initialization'!
initialize
	configPath := XDG config: 'omarchy/wodify.json'.
	cachePath := XDG state: 'samaltak/wodify/last.json'.
	refreshMinutes := 30.
	wakeup := Semaphore new.
	ok := false.
	error := ''.
	url := nil.
	days := #().
	loading := true.
	retrySoon := false.
	lastAttempt := nil
! !

!WodifyService methodsFor: 'accessing'!
configPath: aPath
	configPath := aPath
!
cachePath: aPath
	cachePath := aPath
!
refreshMinutes: aNumber
	"Minutes between fetches (at least 10)."
	refreshMinutes := (aNumber isNumber ifTrue: [aNumber] ifFalse: [30]) max: 10
!
onChange: aBlock
	"[:service | ...] after each attempt, in my Process."
	onChange := aBlock
!
days
	"The WodifyDays fetched last (or cached), today's first; the card leaves out past ones."
	^days
!
isOk
	"Whether the last attempt got the workouts."
	^ok
!
error
	"Why it did not ('' if it did)."
	^error
!
url
	"The gym's member app (nil before the first fetch)."
	^url
!
isLoading
	"Before the first attempt ended."
	^loading
!
today
	"The local date, as an ISO string."
	^(TimeZone local dateAt: self now) printString
! !

!WodifyService methodsFor: 'running'!
start
	(process notNil and: [process isTerminated not]) ifTrue: [^self].
	self readCache.
	process := [[self step. wakeup waitTimeoutMSecs: 2000] repeat] newProcess.
	process priority: Processor userBackgroundPriority; name: 'Wodify service'.
	process resume
!
stop
	process isNil ifFalse: [process terminate. process := nil].
	client isNil ifFalse: [client close. client := nil]
!
refreshNow
	"Fetch at once (a middle click)."
	lastAttempt := nil.
	wakeup signal
!
step
	"Fetch when the config changed, the day did, or a fetch is due."
	| stamp day |
	stamp := [File modificationTime: configPath] on: Error do: [:e | e return: nil].
	day := self today.
	(stamp = configStamp and: [day = today and: [lastAttempt notNil and: [self now - lastAttempt < self interval]]])
		ifTrue: [^self].
	configStamp := stamp.
	today := day.
	self fetch
!
interval
	^retrySoon ifTrue: [60] ifFalse: [refreshMinutes * 60]
!
now
	^Time utcMicroseconds // 1000000
!
fetch
	"Fetch today's and tomorrow's workouts; on failure keep what I have (or the cache), with the error."
	| config |
	lastAttempt := self now.
	config := self readConfig.
	config isNil
		ifTrue: [
			ok := false.
			error := 'No config: create ~/.config/omarchy/wodify.json'.
			retrySoon := false]
		ifFalse: [
			[self fetchWith: config.
			 ok := true.
			 error := ''.
			 retrySoon := false.
			 self writeCache]
				on: Error do: [:e |
					"network trouble is worth a quick retry, a rejected login or a changed app is not"
					(e isKindOf: WodifyError)
						ifTrue: [self failed: e messageText retryable: e retryable]
						ifFalse: [self failed: ((e isKindOf: HTTPError) ifTrue: [e messageText] ifFalse: [e description]) retryable: true].
					e return: nil]].
	loading := false.
	onChange isNil ifFalse: [onChange value: self]
!
fetchWith: config
	| key first |
	key := self class keyOf: config.
	(client isNil or: [key ~= clientKey]) ifTrue: [
		client isNil ifFalse: [client close].
		client := nil.
		client := WodifyClient config: config.
		clientKey := key].
	url := client url.
	first := TimeZone local dateAt: self now.
	days := client days: (Array with: first with: (first addDays: 1)) config: config
!
failed: aString retryable: aBoolean
	ok := false.
	error := (aString isNil or: [aString isEmpty]) ifTrue: ['Couldn''t fetch workouts'] ifFalse: [aString].
	retrySoon := aBoolean.
	days isEmpty ifTrue: [self readCache]
! !

!WodifyService methodsFor: 'files'!
readConfig
	"The config (a Dictionary), nil if there is none."
	| c |
	c := [JSON parse: (File readText: configPath)] on: Error do: [:e | e return: nil].
	^((c isKindOf: Dictionary) and: [c notEmpty]) ifTrue: [c] ifFalse: [nil]
!
readCache
	"The workouts fetched last, from the offline cache."
	| cached |
	cached := [JSON parse: (File readText: cachePath)] on: Error do: [:e | e return: nil].
	(cached isKindOf: Dictionary) ifFalse: [^self].
	url isNil ifTrue: [url := cached at: 'url' ifAbsent: [nil]].
	days := ((cached at: 'days' ifAbsent: [#()]) isKindOf: Array)
		ifTrue: [((cached at: 'days') collect: [:d | WodifyDay fromJSON: d]) reject: [:d | d isNil]]
		ifFalse: [#()]
!
writeCache
	"Keep the workouts for when Wodify cannot be reached."
	| tmp |
	[Directory ensureExists: (File directoryOf: cachePath).
	 tmp := cachePath, '.tmp'.
	 File writeText: (JSON render: (Dictionary new
			at: 'url' put: url;
			at: 'fetchedAt' put: (WodifyClient isoLocal: (TimeZone local localSecondsAt: self now));
			at: 'days' put: (days collect: [:d | d asJSON]);
			yourself)) to: tmp.
	 File rename: tmp to: cachePath] on: Error do: [:e | e return: nil]
! !

!WodifyService class methodsFor: 'config'!
keyOf: aConfig
	"What a session is for: host, email and gym; a change logs in anew."
	^String new: 64 streamContents: [:s |
		#('host' 'email' 'gym') do: [:k | s nextPutAll: (WodifyClient str: ((aConfig at: k ifAbsent: [nil]) ifNil: [''])) asLowercase]
			separatedBy: [s nextPut: $|]]
! !
