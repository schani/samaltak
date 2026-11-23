Object subclass: #HTTPCookieJar
	instanceVariableNames: 'cookies'
	classVariableNames: ''
	package: 'System-Net'!

HTTPCookieJar comment: 'I keep the cookies servers set (RFC 6265, as browsers do), in memory: receive: takes a response''s Set-Cookie headers for the URL it answered, headerFor: answers the Cookie header for a request to a URL (domain, path, Secure and expiry matched, longer paths first).

	jar := HTTPCookieJar new.
	response := client get: url headers: (jar headersFor: url).
	jar receive: response from: url.
	jar valueOf: ''session''

Each cookie is a Dictionary: name, value, domain, hostOnly, path, secure, expires (seconds since 1970, nil for a session cookie).'!

!HTTPCookieJar methodsFor: 'initialization'!
initialize
	cookies := OrderedCollection new
! !

!HTTPCookieJar methodsFor: 'accessing'!
cookies
	"The cookies that have not expired."
	self dropExpired.
	^cookies asArray
!
valueOf: aName
	"The value of the cookie named aName (the first, if several domains or paths set one), or nil."
	^(self cookies detect: [:c | (c at: #name) = aName] ifNone: [^nil]) at: #value
!
clear
	cookies := OrderedCollection new
!
isEmpty
	^self cookies isEmpty
! !

!HTTPCookieJar methodsFor: 'receiving'!
receive: aResponse from: url
	"Keep the cookies of aResponse's Set-Cookie headers (an HTTPResponse to a request for url)."
	| target |
	target := HTTPClient parse: url.
	(aResponse allAt: 'Set-Cookie') do: [:header |
		self set: header host: (target at: 2) asLowercase path: (target at: 4)]
!
set: aHeader host: host path: requestPath
	"Keep the cookie of one Set-Cookie header value, set by host for requestPath."
	| parts pair eq name value cookie domain maxAge expires |
	parts := aHeader subStrings: ';'.
	parts isEmpty ifTrue: [^self].
	pair := parts first.
	eq := pair indexOf: $=.
	eq = 0 ifTrue: [^self].
	name := (pair copyFrom: 1 to: eq - 1) trimBoth.
	value := (pair copyFrom: eq + 1 to: pair size) trimBoth.
	name isEmpty ifTrue: [^self].
	cookie := Dictionary new.
	cookie at: #name put: name; at: #value put: value; at: #secure put: false; at: #expires put: nil.
	domain := nil.
	maxAge := nil.
	expires := nil.
	parts allButFirst do: [:attribute |
		| i key arg |
		i := attribute indexOf: $=.
		key := (i = 0 ifTrue: [attribute] ifFalse: [attribute copyFrom: 1 to: i - 1]) trimBoth asLowercase.
		arg := i = 0 ifTrue: [''] ifFalse: [(attribute copyFrom: i + 1 to: attribute size) trimBoth].
		key = 'domain' ifTrue: [domain := (arg beginsWith: '.') ifTrue: [arg allButFirst asLowercase] ifFalse: [arg asLowercase]].
		key = 'path' ifTrue: [(arg beginsWith: '/') ifTrue: [cookie at: #path put: arg]].
		key = 'secure' ifTrue: [cookie at: #secure put: true].
		key = 'max-age' ifTrue: [maxAge := [arg asInteger] on: Error do: [:e | e return: nil]].
		key = 'expires' ifTrue: [expires := self class parseHTTPDate: arg]].
	(domain isNil or: [domain isEmpty])
		ifTrue: [cookie at: #domain put: host; at: #hostOnly put: true]
		ifFalse: [
			"a server sets cookies only for its own domain or a parent of it"
			(self class domain: host matches: domain) ifFalse: [^self].
			cookie at: #domain put: domain; at: #hostOnly put: false].
	(cookie includesKey: #path) ifFalse: [cookie at: #path put: (self class defaultPathOf: requestPath)].
	maxAge notNil
		ifTrue: [cookie at: #expires put: self now + maxAge]
		ifFalse: [cookie at: #expires put: expires].
	cookies := cookies reject: [:c |
		(c at: #name) = name and: [(c at: #domain) = (cookie at: #domain) and: [(c at: #path) = (cookie at: #path)]]].
	"an expiry in the past deletes the cookie"
	((cookie at: #expires) notNil and: [(cookie at: #expires) <= self now]) ifTrue: [^self].
	cookies add: cookie
! !

!HTTPCookieJar methodsFor: 'sending'!
headerFor: url
	"The Cookie header's value for a request to url, nil if no cookie goes with it."
	| target tls host path matching |
	target := HTTPClient parse: url.
	tls := target at: 1.
	host := (target at: 2) asLowercase.
	path := target at: 4.
	(path includes: $?) ifTrue: [path := path copyFrom: 1 to: (path indexOf: $?) - 1].
	matching := self cookies select: [:c |
		((c at: #hostOnly) ifTrue: [host = (c at: #domain)] ifFalse: [self class domain: host matches: (c at: #domain)])
			and: [(self class path: path matches: (c at: #path))
			and: [tls or: [(c at: #secure) not]]]].
	matching isEmpty ifTrue: [^nil].
	matching := matching asArray sort: [:a :b | (a at: #path) size >= (b at: #path) size].
	^String new: 100 streamContents: [:s |
		matching do: [:c | s nextPutAll: (c at: #name); nextPut: $=; nextPutAll: (c at: #value)] separatedBy: [s nextPutAll: '; ']]
!
headersFor: url
	"aDictionary with the Cookie header for url (empty if none)."
	^self add: url to: Dictionary new
!
add: url to: aDictionary
	"aDictionary (request headers) with the Cookie header for url added."
	(self headerFor: url) ifNotNil: [:value | aDictionary at: 'Cookie' put: value].
	^aDictionary
! !

!HTTPCookieJar methodsFor: 'private'!
now
	^Time utcMicroseconds // 1000000
!
dropExpired
	| t |
	t := self now.
	cookies := cookies reject: [:c | (c at: #expires) notNil and: [(c at: #expires) <= t]]
! !

!HTTPCookieJar class methodsFor: 'matching'!
domain: host matches: domain
	"RFC 6265 5.1.3: host is domain or ends with .domain (not an IP address)."
	host = domain ifTrue: [^true].
	(host allSatisfy: [:c | c isDigit or: [c = $.]]) ifTrue: [^false].
	^host endsWith: '.', domain
!
path: requestPath matches: cookiePath
	"RFC 6265 5.1.4."
	requestPath = cookiePath ifTrue: [^true].
	(requestPath beginsWith: cookiePath) ifFalse: [^false].
	^cookiePath last = $/ or: [(requestPath at: cookiePath size + 1) = $/]
!
defaultPathOf: requestPath
	"RFC 6265 5.1.4: the request path up to its last slash, / if that is the first."
	| path i |
	path := requestPath.
	(path includes: $?) ifTrue: [path := path copyFrom: 1 to: (path indexOf: $?) - 1].
	(path isEmpty or: [path first ~= $/]) ifTrue: [^'/'].
	i := path lastIndexOf: $/.
	i <= 1 ifTrue: [^'/'].
	^path copyFrom: 1 to: i - 1
! !

!HTTPCookieJar class methodsFor: 'dates'!
parseHTTPDate: aString
	"Seconds since 1970 of a cookie date (RFC 6265 5.1.1: a day of the month, a month name, a year and hh:mm:ss in any order, GMT), nil if it is not one."
	| tokens day month year time |
	tokens := aString subStrings: ' ,-'.
	tokens do: [:t |
		(time isNil and: [(t occurrencesOf: $:) = 2]) ifTrue: [
			| hms |
			hms := (t subStrings: ':') collect: [:x | x asInteger].
			(hms allSatisfy: [:x | x notNil]) ifTrue: [time := ((hms at: 1) * 3600) + ((hms at: 2) * 60) + (hms at: 3)]].
		(month isNil and: [t size >= 3]) ifTrue: [
			| i |
			i := #('jan' 'feb' 'mar' 'apr' 'may' 'jun' 'jul' 'aug' 'sep' 'oct' 'nov' 'dec') indexOf: (t copyFrom: 1 to: 3) asLowercase.
			i > 0 ifTrue: [month := i]].
		(t allSatisfy: [:c | c isDigit]) ifTrue: [
			(day isNil and: [t size <= 2]) ifTrue: [day := t asInteger] ifFalse: [
				(year isNil and: [t size >= 2]) ifTrue: [year := t asInteger]]]].
	(day isNil or: [month isNil or: [year isNil or: [time isNil]]]) ifTrue: [^nil].
	year < 70 ifTrue: [year := year + 2000] ifFalse: [year < 100 ifTrue: [year := year + 1900]].
	^((Date year: year month: month day: day) daysSinceEpoch * 86400) + time
! !
