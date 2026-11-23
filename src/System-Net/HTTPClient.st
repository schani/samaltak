Object subclass: #HTTPClient
	instanceVariableNames: 'socket origin session pending position cancelled carry'
	classVariableNames: 'Session'
	package: 'System-Net'!

HTTPClient comment: 'I am an HTTP/1.1 client over TLS (https:, a TLSSocket) or plain TCP (http:). I keep one connection open between requests to the same origin, and connect again when the server has closed it. Response bodies are Content-Length, chunked or up to the end of the connection; no compression is asked for. Request methods answer an HTTPResponse; they signal HTTPError when there is no connection, it is lost, or close cancels the request from another Process.

	client := HTTPClient new.
	(client get: ''https://example.com/'' headers: nil) string.
	client post: url json: aDictionary headers: nil do: [:aString | "each piece of a 2xx body as it arrives, UTF-8 decoded"].
	client close

One request at a time. A connection saved in the image is dropped after a restart (the startup list).'!

!HTTPClient methodsFor: 'requests'!
get: url headers: aDictionary
	^self request: 'GET' url: url headers: aDictionary body: nil do: nil
!
post: url json: anObject headers: aDictionary
	^self post: url json: anObject headers: aDictionary do: nil
!
post: url json: anObject headers: aDictionary do: aBlock
	"aBlock (if not nil) gets the body of a 2xx response in Strings as it arrives, and the response's body stays empty; any other status' body is collected."
	^self request: 'POST' url: url
		headers: (self headers: aDictionary contentType: 'application/json')
		body: (JSON render: anObject) utf8Encoded
		do: aBlock
!
post: url form: fields headers: aDictionary
	"fields: a Dictionary of Strings, sent application/x-www-form-urlencoded."
	^self request: 'POST' url: url
		headers: (self headers: aDictionary contentType: 'application/x-www-form-urlencoded')
		body: (self class formEncode: fields) asByteArray
		do: nil
!
request: method url: url headers: aDictionary body: bytes do: aBlock
	| target head reused response |
	target := self class parse: url.
	head := self head: method target: target headers: aDictionary body: bytes.
	cancelled := false.
	reused := self connectTo: target.
	response := self send: head body: bytes.
	(response isNil and: [reused and: [cancelled not]]) ifTrue: [
		"the server closed the connection we kept"
		self disconnect.
		self connectTo: target.
		response := self send: head body: bytes].
	response isNil ifTrue: [
		self disconnect.
		^self lost].
	[self readBodyOf: response method: method do: aBlock] ifCurtailed: [self disconnect].
	(response headerAt: 'connection') = 'close' ifTrue: [self disconnect].
	^response
!
close
	"Close the connection. A request waiting in another Process ends with an HTTPError."
	cancelled := true.
	self disconnect
! !

!HTTPClient methodsFor: 'private'!
headers: aDictionary contentType: aString
	| all |
	all := aDictionary isNil ifTrue: [Dictionary new] ifFalse: [aDictionary copy].
	all at: 'Content-Type' put: aString.
	^all
!
head: method target: target headers: aDictionary body: bytes
	"The request line and headers, encoded."
	| port |
	port := target at: 3.
	^(String new: 256 streamContents: [:s |
		s nextPutAll: method; space; nextPutAll: (target at: 4); nextPutAll: ' HTTP/1.1'; crlf.
		s nextPutAll: 'Host: '; nextPutAll: (target at: 2).
		port = ((target at: 1) ifTrue: [443] ifFalse: [80]) ifFalse: [s nextPut: $:; print: port].
		s crlf.
		(aDictionary isNil or: [(aDictionary includesKey: 'User-Agent') not]) ifTrue: [s nextPutAll: 'User-Agent: Samaltak'; crlf].
		bytes isNil ifFalse: [s nextPutAll: 'Content-Length: '; print: bytes size; crlf].
		aDictionary isNil ifFalse: [
			aDictionary keysAndValuesDo: [:k :v | s nextPutAll: k; nextPutAll: ': '; nextPutAll: v; crlf]].
		s crlf]) utf8Encoded
!
connectTo: target
	"Connect to target's origin unless the connection is open; answer whether it was."
	| key s |
	key := target copyFrom: 1 to: 3.
	(socket notNil and: [session == self class session and: [socket isOpen and: [origin = key]]]) ifTrue: [^true].
	self disconnect.
	s := [(target at: 1)
		ifTrue: [TLSSocket connectTo: (target at: 2) port: (target at: 3)]
		ifFalse: [RemoteSocket connectTo: (target at: 2) port: (target at: 3)]]
			on: RemoteError do: [:e | cancelled == true ifTrue: [self lost]. HTTPError signal: e messageText].
	"closed while connecting"
	cancelled == true ifTrue: [
		s close.
		^self lost].
	socket := s.
	session := self class session.
	origin := key.
	pending := ByteArray new.
	position := 1.
	^false
!
disconnect
	"A socket of a VM that saved the image is forgotten, not closed."
	| s |
	s := socket.
	socket := nil.
	s isNil ifTrue: [^self].
	session == self class session ifTrue: [s close] ifFalse: [s forget]
!
lost
	^HTTPError signal: (cancelled == true ifTrue: ['request cancelled'] ifFalse: ['connection closed by the server'])
!
send: head body: bytes
	"Send the request; answer the response's status and headers, or nil if the connection closed before the response began."
	| s line status fields |
	s := socket.
	s isNil ifTrue: [^nil].
	(s sendAll: head) ifFalse: [^nil].
	(bytes isNil or: [bytes isEmpty or: [s sendAll: bytes]]) ifFalse: [^nil].
	[line := self readLine.
	 line isNil ifTrue: [^nil].
	 status := ((line subStrings: ' ') at: 2 ifAbsent: ['']) asInteger.
	 status isNil ifTrue: [^HTTPError signal: 'not an HTTP response: ', line].
	 fields := self readHeaders.
	 status < 200] whileTrue.
	^HTTPResponse new setStatus: status fields: fields
!
readHeaders
	"The header fields up to the empty line, in order: name (lowercase) -> value."
	| fields line colon |
	fields := OrderedCollection new.
	[line := self readLine.
	 line isNil ifTrue: [^self lost].
	 line isEmpty] whileFalse: [
		colon := line indexOf: $:.
		colon > 0 ifTrue: [
			fields add: (line copyFrom: 1 to: colon - 1) trimBoth asLowercase -> (line copyFrom: colon + 1 to: line size) trimBoth]].
	^fields asArray
!
readBodyOf: response method: method do: aBlock
	| streams out sink length |
	(method = 'HEAD' or: [response status = 204 or: [response status = 304]]) ifTrue: [^self].
	streams := aBlock notNil and: [response isSuccess].
	streams
		ifTrue: [
			carry := ByteArray new.
			sink := [:bytes | self deliver: bytes to: aBlock]]
		ifFalse: [
			out := WriteStream on: (ByteArray new: 1024).
			sink := [:bytes | out nextPutAll: bytes]].
	((response headerAt: 'transfer-encoding') ifNil: [''] ifNotNil: [:te | te asLowercase]) = 'chunked'
		ifTrue: [self readChunksDo: sink]
		ifFalse: [
			length := response headerAt: 'content-length'.
			length isNil
				ifTrue: [
					self readToEndDo: sink.
					self disconnect]
				ifFalse: [self read: length asInteger do: sink]].
	streams
		ifTrue: [carry isEmpty ifFalse: [aBlock value: carry utf8Decoded]]
		ifFalse: [response body: out contents]
!
deliver: bytes to: aBlock
	"Hand aBlock the UTF-8 text of carry and bytes up to the last complete character; keep the rest in carry."
	| all cut |
	all := carry, bytes.
	cut := self class completeUTF8Size: all.
	carry := all copyFrom: cut + 1 to: all size.
	cut > 0 ifTrue: [aBlock value: (all copyFrom: 1 to: cut) utf8Decoded]
! !

!HTTPClient methodsFor: 'reading'!
fill
	"Receive more bytes into pending; false at the end of the connection."
	| s chunk n |
	s := socket.
	s isNil ifTrue: [^false].
	chunk := ByteArray new: 16384.
	n := s receiveInto: chunk.
	n = 0 ifTrue: [^false].
	pending := (pending copyFrom: position to: pending size), (chunk copyFrom: 1 to: n).
	position := 1.
	^true
!
readLine
	"The next line without its CR LF, or nil at the end of the connection."
	| i line |
	[i := position.
	 [i < pending size and: [((pending at: i) = 13 and: [(pending at: i + 1) = 10]) not]] whileTrue: [i := i + 1].
	 i < pending size] whileFalse: [self fill ifFalse: [^nil]].
	line := (pending copyFrom: position to: i - 1) asString.
	position := i + 2.
	^line
!
read: count do: aBlock
	"Hand aBlock the next count bytes, in pieces as they arrive."
	| remaining k |
	remaining := count.
	[remaining > 0] whileTrue: [
		position > pending size ifTrue: [self fill ifFalse: [^self lost]].
		k := remaining min: pending size - position + 1.
		aBlock value: (pending copyFrom: position to: position + k - 1).
		position := position + k.
		remaining := remaining - k]
!
readToEndDo: aBlock
	[position <= pending size ifTrue: [
		aBlock value: (pending copyFrom: position to: pending size).
		position := pending size + 1].
	 self fill] whileTrue.
	cancelled == true ifTrue: [self lost]
!
readChunksDo: aBlock
	| size |
	[size := self class hexValue: ((self readLine ifNil: [^self lost]) copyUpTo: $;) trimBoth.
	 size > 0] whileTrue: [
		self read: size do: aBlock.
		(self readLine ifNil: [^self lost]) isEmpty ifFalse: [^HTTPError signal: 'bad chunk']].
	"the trailer"
	[(self readLine ifNil: [^self lost]) isEmpty] whileFalse
! !

!HTTPClient class methodsFor: 'class initialization'!
initialize
	Smalltalk addToStartUpList: self
! !

!HTTPClient class methodsFor: 'system startup'!
session
	^Session ifNil: [Session := Object new]
!
startUp: resuming
	"Connections saved in the image died with the VM that saved it."
	resuming ifTrue: [Session := Object new]
! !

!HTTPClient class methodsFor: 'encoding'!
parse: url
	"{isTLS. host. port. path and query} of an http: or https: URL."
	| tls rest slash hostPort path colon |
	(url beginsWith: 'https://')
		ifTrue: [
			tls := true.
			rest := url copyFrom: 9 to: url size]
		ifFalse: [
			(url beginsWith: 'http://') ifFalse: [^HTTPError signal: 'not an http or https URL: ', url].
			tls := false.
			rest := url copyFrom: 8 to: url size].
	slash := rest indexOf: $/.
	slash = 0
		ifTrue: [
			hostPort := rest.
			path := '/']
		ifFalse: [
			hostPort := rest copyFrom: 1 to: slash - 1.
			path := rest copyFrom: slash to: rest size].
	colon := hostPort indexOf: $:.
	colon = 0 ifTrue: [^Array with: tls with: hostPort with: (tls ifTrue: [443] ifFalse: [80]) with: path].
	^Array with: tls with: (hostPort copyFrom: 1 to: colon - 1) with: (hostPort copyFrom: colon + 1 to: hostPort size) asInteger with: path
!
formEncode: aDictionary
	"aDictionary's keys and values as application/x-www-form-urlencoded (keys sorted)."
	^String new: 64 streamContents: [:s |
		aDictionary keys asSortedCollection
			do: [:k | s nextPutAll: (self percentEncode: k); nextPut: $=; nextPutAll: (self percentEncode: (aDictionary at: k))]
			separatedBy: [s nextPut: $&]]
!
percentEncode: aString
	^String new: aString size streamContents: [:s |
		aString utf8Encoded do: [:b |
			(b < 128 and: [(Character value: b) isLetter or: [(Character value: b) isDigit or: ['-._~' includes: (Character value: b)]]])
				ifTrue: [s nextPut: (Character value: b)]
				ifFalse: [s nextPut: $%; nextPutAll: ((b printString: 16) asUppercase padLeftTo: 2 with: $0)]]]
!
hexValue: aString
	| value |
	aString isEmpty ifTrue: [^HTTPError signal: 'bad chunk size'].
	value := 0.
	aString do: [:c |
		(c digitValue between: 0 and: 15) ifFalse: [^HTTPError signal: 'bad chunk size: ', aString].
		value := value * 16 + c digitValue].
	^value
!
completeUTF8Size: bytes
	"The size of the longest prefix of bytes that does not end inside a UTF-8 sequence."
	| i b need |
	i := bytes size.
	[i > 0 and: [i > (bytes size - 3) and: [((bytes at: i) bitAnd: 16rC0) = 16r80]]] whileTrue: [i := i - 1].
	(i = 0 or: [(b := bytes at: i) < 16rC0]) ifTrue: [^bytes size].
	need := b < 16rE0 ifTrue: [2] ifFalse: [b < 16rF0 ifTrue: [3] ifFalse: [4]].
	^bytes size - i + 1 >= need ifTrue: [bytes size] ifFalse: [i - 1]
! !
