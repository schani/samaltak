Object subclass: #HTTPResponse
	instanceVariableNames: 'status headers fields body'
	classVariableNames: ''
	package: 'System-Net'!

HTTPResponse comment: 'I am the response to an HTTPClient request: the status code, the headers (lowercase names; repeated headers joined with ", ", except in allAt:, which Set-Cookie needs) and the body bytes (empty when the body was streamed to a block).'!

!HTTPResponse methodsFor: 'initialization'!
setStatus: anInteger headers: aDictionary
	status := anInteger.
	headers := aDictionary.
	fields := Array new.
	headers keysAndValuesDo: [:k :v | fields := fields copyWith: k -> v].
	body := ByteArray new
!
setStatus: anInteger fields: anArray
	"anArray: the header fields in order, lowercase name -> value."
	status := anInteger.
	fields := anArray.
	headers := Dictionary new.
	fields do: [:f |
		headers at: f key put: ((headers at: f key ifAbsent: [nil]) ifNil: [f value] ifNotNil: [:old | old, ', ', f value])].
	body := ByteArray new
!
body: aByteArray
	body := aByteArray
! !

!HTTPResponse methodsFor: 'accessing'!
status
	^status
!
headers
	^headers
!
headerAt: aString
	"The value of the header named aString (any case), or nil."
	^headers at: aString asLowercase ifAbsent: [nil]
!
allAt: aString
	"Every value of the header named aString (any case), in order: Set-Cookie, whose values have commas of their own."
	| name |
	name := aString asLowercase.
	^(fields select: [:f | f key = name]) collect: [:f | f value]
!
body
	^body
!
string
	"The body decoded from UTF-8."
	^body utf8Decoded
!
json
	"The body parsed as JSON (JSONError if it is not)."
	^JSON parse: self string
!
isSuccess
	^status between: 200 and: 299
! !

!HTTPResponse methodsFor: 'printing'!
printOn: aStream
	aStream nextPutAll: 'an HTTPResponse '; print: status
! !
