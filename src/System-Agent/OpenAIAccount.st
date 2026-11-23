Object subclass: #OpenAIAccount
	instanceVariableNames: 'issuer idToken accessToken refreshToken deviceAuthId loginCode loginURL interval loginDeadline loginSemaphore lock storePath storeStamp'
	classVariableNames: 'Default'
	package: 'System-Agent'!

OpenAIAccount comment: 'I am a ChatGPT sign-in, as the Codex CLI does it: a device-code login at my issuer, then OAuth tokens. The id token tells the account (email, accountId, planType); the access token is refreshed before it expires and after a 401 (refresh tokens rotate: I keep each one returned). The tokens are saved with the image; signOut forgets them. Or, after keepIn: aPath, in that file (only the user may read it), so that the processes of applications share one sign-in: each reads it again when it changed, writes it after a login or refresh, and deletes it on signOut; a refresh that finds its refresh token used up by another process takes the newer one from the file.

	account := OpenAIAccount default.
	account startLogin.
	account loginURL. account loginCode.   "show these to the user"
	account finishLogin.   "waits for the approval: true, or false if it expired or was cancelled"
	account accessToken'!

!OpenAIAccount methodsFor: 'initialization'!
initialize
	issuer := 'https://auth.openai.com'.
	lock := Mutex new
! !

!OpenAIAccount methodsFor: 'accessing'!
issuer
	^issuer
!
issuer: aURLString
	"The auth server's base URL."
	issuer := aURLString
!
isSignedIn
	self reloadIfChanged.
	^accessToken notNil
!
storePath
	"The file I keep the tokens in, or nil (the image keeps them)."
	^storePath
!
email
	^self claims at: 'email' ifAbsent: [nil]
!
accountId
	^self authClaims at: 'chatgpt_account_id' ifAbsent: [nil]
!
planType
	^self authClaims at: 'chatgpt_plan_type' ifAbsent: [nil]
!
loginURL
	"Where the user enters loginCode; nil unless a login is pending."
	^loginURL
!
loginCode
	^loginCode
! !

!OpenAIAccount methodsFor: 'login'!
startLogin
	"Ask for a device code; then loginURL and loginCode are set."
	| r json |
	r := self post: '/api/accounts/deviceauth/usercode' json: (Dictionary new at: 'client_id' put: self class clientId; yourself).
	r isSuccess ifFalse: [^AgentError signal: 'Cannot start the ChatGPT sign-in: ', (self class describe: r)].
	json := r json.
	deviceAuthId := json at: 'device_auth_id'.
	loginCode := json at: 'user_code'.
	interval := (json at: 'interval' ifAbsent: [nil]) ifNil: [5] ifNotNil: [:v | v isString ifTrue: [v asNumber ifNil: [5]] ifFalse: [v]].
	loginURL := issuer, '/codex/device'.
	loginDeadline := Time millisecondClockValue + (15 * 60 * 1000).
	loginSemaphore := Semaphore new
!
finishLogin
	"Poll every interval seconds until the user approves the pending login (store the tokens, answer true) or it expires or is cancelled (answer false)."
	| semaphore r json |
	semaphore := loginSemaphore.
	[deviceAuthId notNil] whileTrue: [
		r := self post: '/api/accounts/deviceauth/token' json: (Dictionary new at: 'device_auth_id' put: deviceAuthId; at: 'user_code' put: loginCode; yourself).
		deviceAuthId isNil ifTrue: [^false].
		r isSuccess ifTrue: [
			json := r json.
			self clearLogin.
			self exchange: (json at: 'authorization_code') verifier: (json at: 'code_verifier').
			^true].
		(r status = 403 or: [r status = 404]) ifFalse: [
			self clearLogin.
			^AgentError signal: 'The ChatGPT sign-in failed: ', (self class describe: r)].
		Time millisecondClockValue >= loginDeadline ifTrue: [
			self clearLogin.
			^false].
		semaphore waitTimeoutMSecs: (interval * 1000) rounded].
	^false
!
cancelLogin
	"A pending finishLogin answers false."
	| semaphore |
	semaphore := loginSemaphore.
	self clearLogin.
	semaphore isNil ifFalse: [semaphore signal]
!
tokens: aDictionary
	"Install the tokens of an /oauth/token response (those it has)."
	(aDictionary at: 'id_token' ifAbsent: [nil]) ifNotNil: [:t | idToken := t].
	(aDictionary at: 'access_token' ifAbsent: [nil]) ifNotNil: [:t | accessToken := t].
	(aDictionary at: 'refresh_token' ifAbsent: [nil]) ifNotNil: [:t | refreshToken := t].
	self save
!
signOut
	idToken := nil.
	accessToken := nil.
	refreshToken := nil.
	self save
! !

!OpenAIAccount methodsFor: 'file'!
keepIn: aPath
	"Keep the tokens in the file aPath from now on, shared with other processes: read it if there is one (its sign-in replaces mine), else write mine to it."
	storePath = aPath ifTrue: [^self].
	storePath := aPath.
	storeStamp := nil.
	(File exists: aPath) ifTrue: [self load] ifFalse: [self save]
!
load
	"Take the tokens from my file (none if it is gone or unreadable)."
	| json |
	storeStamp := self fileStamp.
	json := [JSON parse: (File readText: storePath)] on: Error do: [:e | e return: nil].
	(json isKindOf: Dictionary) ifFalse: [json := Dictionary new].
	idToken := json at: 'id_token' ifAbsent: [nil].
	accessToken := json at: 'access_token' ifAbsent: [nil].
	refreshToken := json at: 'refresh_token' ifAbsent: [nil]
!
reloadIfChanged
	"Another process signed in, refreshed or signed out: take its tokens. Answer whether my file changed."
	storePath isNil ifTrue: [^false].
	self fileStamp = storeStamp ifTrue: [^false].
	self load.
	^true
!
save
	"Write my tokens to my file (only the user may read it), or delete it when I am signed out."
	storePath isNil ifTrue: [^self].
	[accessToken isNil
		ifTrue: [File deleteIfExists: storePath]
		ifFalse: [
			Directory ensureExists: (File directoryOf: storePath).
			File writeSecret: (JSON render: (Dictionary new
				at: 'id_token' put: idToken;
				at: 'access_token' put: accessToken;
				at: 'refresh_token' put: refreshToken;
				yourself)) to: storePath]]
		on: Error do: [:e | e return: nil].
	storeStamp := self fileStamp
!
fileStamp
	"My file's modification time and size (nil if there is none)."
	| st |
	st := [File stat: storePath] on: Error do: [:e | e return: nil].
	(st isNil or: [st first not]) ifTrue: [^nil].
	^Array with: st fourth with: st third
! !

!OpenAIAccount methodsFor: 'tokens'!
accessToken
	"A current access token, refreshed first when it expires within 5 minutes. AgentError when signed out."
	^lock critical: [
		self reloadIfChanged.
		accessToken isNil ifTrue: [AgentError signal: 'Not signed in to ChatGPT'].
		(self expiresWithin: 300) ifTrue: [self refreshBecause: 'proactive_expiry'].
		accessToken]
!
refresh
	"Refresh the tokens now (after a 401). If the refresh token is no longer valid, sign out and signal AgentError."
	lock critical: [
		"another process may have refreshed already"
		(self reloadIfChanged and: [accessToken notNil]) ifFalse: [self refreshBecause: 'unauthorized_recovery']]
! !

!OpenAIAccount methodsFor: 'private'!
claims
	^self class claimsOf: idToken
!
authClaims
	^(self claims at: 'https://api.openai.com/auth' ifAbsent: [nil]) ifNil: [Dictionary new]
!
expiresWithin: seconds
	| exp |
	exp := (self class claimsOf: accessToken) at: 'exp' ifAbsent: [^false].
	^exp - (Time utcMicroseconds // 1000000) < seconds
!
refreshBecause: reason
	| r code |
	refreshToken isNil ifTrue: [^AgentError signal: 'Not signed in to ChatGPT'].
	r := self post: '/oauth/token' json: (Dictionary new
		at: 'client_id' put: self class clientId;
		at: 'grant_type' put: 'refresh_token';
		at: 'refresh_token' put: refreshToken;
		at: 'refresh_reason' put: reason;
		yourself).
	r isSuccess ifTrue: [^self tokens: r json].
	code := self class errorCodeOf: r.
	"Another process refreshed first (refresh tokens rotate): its tokens are in the file."
	(self reloadIfChanged and: [accessToken notNil]) ifTrue: [^self].
	(r status = 401 or: [#('invalid_grant' 'refresh_token_expired' 'refresh_token_reused' 'refresh_token_invalidated') includes: code]) ifTrue: [
		self signOut.
		^AgentError signal: 'The ChatGPT sign-in has expired; sign in again'].
	^AgentError signal: 'Cannot refresh the ChatGPT sign-in: ', (self class describe: r)
!
exchange: code verifier: verifier
	| r |
	r := self post: '/oauth/token' form: (Dictionary new
		at: 'grant_type' put: 'authorization_code';
		at: 'client_id' put: self class clientId;
		at: 'code' put: code;
		at: 'redirect_uri' put: issuer, '/deviceauth/callback';
		at: 'code_verifier' put: verifier;
		yourself).
	r isSuccess ifFalse: [^AgentError signal: 'The ChatGPT sign-in failed: ', (self class describe: r)].
	self tokens: r json
!
clearLogin
	deviceAuthId := nil.
	loginCode := nil.
	loginURL := nil.
	loginSemaphore := nil
!
post: path json: aDictionary
	^self request: [:client | client post: issuer, path json: aDictionary headers: nil]
!
post: path form: aDictionary
	^self request: [:client | client post: issuer, path form: aDictionary headers: nil]
!
request: aBlock
	| client |
	client := HTTPClient new.
	^[[aBlock value: client] ensure: [client close]]
		on: HTTPError do: [:e | AgentError signal: 'Cannot reach ', issuer, ': ', e messageText]
! !

!OpenAIAccount methodsFor: 'printing'!
printOn: aStream
	aStream nextPutAll: 'an OpenAIAccount'.
	self isSignedIn
		ifTrue: [aStream nextPutAll: ' ('; nextPutAll: (self email ifNil: ['signed in']); nextPut: $)]
		ifFalse: [aStream nextPutAll: ' (signed out)']
! !

!OpenAIAccount class methodsFor: 'accessing'!
default
	"The image's account."
	^Default ifNil: [Default := self new]
!
reset
	Default := nil
!
clientId
	"The Codex CLI's."
	^'app_EMoamEEZ73f0CkXaXp7hrann'
! !

!OpenAIAccount class methodsFor: 'decoding'!
claimsOf: aJWT
	"The claims of a JSON Web Token (not verified), an empty Dictionary if there are none."
	| parts |
	aJWT isNil ifTrue: [^Dictionary new].
	parts := aJWT subStrings: '.'.
	parts size < 2 ifTrue: [^Dictionary new].
	^[JSON parse: (Base64 decode: (parts at: 2)) utf8Decoded] on: Error do: [:e | e return: Dictionary new]
!
errorCodeOf: aResponse
	"The OAuth error code of a failed response: error, or error.code."
	| error |
	error := [aResponse json at: 'error' ifAbsent: [nil]] on: Error do: [:e | e return: nil].
	error isString ifTrue: [^error].
	(error isKindOf: Dictionary) ifTrue: [^error at: 'code' ifAbsent: [nil]].
	^nil
!
describe: aResponse
	"The status and the server's message, for the user."
	| json message |
	json := [aResponse json] on: Error do: [:e | e return: nil].
	(json isKindOf: Dictionary) ifTrue: [
		message := json at: 'detail' ifAbsent: [nil].
		message isString ifFalse: [
			message := json at: 'error' ifAbsent: [nil].
			(message isKindOf: Dictionary) ifTrue: [message := message at: 'message' ifAbsent: [nil]]].
		message isString ifFalse: [message := json at: 'error_description' ifAbsent: [nil]]].
	message isString ifFalse: [message := aResponse string trimBoth].
	message size > 300 ifTrue: [message := (message copyFrom: 1 to: 300), '...'].
	^'HTTP ', aResponse status printString, (message isEmpty ifTrue: [''] ifFalse: [': ', message])
! !
