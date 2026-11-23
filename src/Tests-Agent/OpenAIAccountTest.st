TestCase subclass: #OpenAIAccountTest
	instanceVariableNames: 'server account replies'
	classVariableNames: ''
	package: 'Tests-Agent'!

OpenAIAccountTest comment: 'Tests OpenAIAccount against an HTTPTestServer standing in for the auth server: the id token''s claims, refreshing before expiry, a refused refresh signing out, the device login, cancelling it, the tokens kept in a file. replies maps a path to the responses to give in turn (the last one repeats). The tokens are unsigned JWTs made for the tests.'!

!OpenAIAccountTest methodsFor: 'running'!
setUp
	replies := Dictionary new.
	server := HTTPTestServer on: [:request | | queue |
		queue := replies at: request path ifAbsent: [nil].
		queue isNil
			ifTrue: [HTTPTestServer response: 404 body: '{}']
			ifFalse: [queue size > 1 ifTrue: [queue removeFirst] ifFalse: [queue first]]].
	account := OpenAIAccount new issuer: server url
!
tearDown
	account cancelLogin.
	server stop
!
reply: path with: responses
	replies at: path put: responses asOrderedCollection
!
requestsTo: path
	^server requests select: [:r | r path = path]
! !

!OpenAIAccountTest methodsFor: 'tokens'!
idToken
	"email ada@example.com, account acct-1, plan pro"
	^'eyJhbGciOiJub25lIn0.eyJlbWFpbCI6ImFkYUBleGFtcGxlLmNvbSIsImh0dHBzOi8vYXBpLm9wZW5haS5jb20vYXV0aCI6eyJjaGF0Z3B0X2FjY291bnRfaWQiOiJhY2N0LTEiLCJjaGF0Z3B0X3BsYW5fdHlwZSI6InBybyJ9fQ.x'
!
freshToken
	"exp 2100"
	^'eyJhbGciOiJub25lIn0.eyJleHAiOjQxMDI0NDQ4MDAsIm4iOjF9.x'
!
freshToken2
	^'eyJhbGciOiJub25lIn0.eyJleHAiOjQxMDI0NDQ4MDAsIm4iOjJ9.x'
!
expiredToken
	"exp 2001"
	^'eyJhbGciOiJub25lIn0.eyJleHAiOjEwMDAwMDAwMDB9.x'
!
tokens: access refresh: refresh
	^Dictionary new at: 'id_token' put: self idToken; at: 'access_token' put: access; at: 'refresh_token' put: refresh; yourself
!
tokenResponse: access refresh: refresh
	^HTTPTestServer response: 200 body: (JSON render: (self tokens: access refresh: refresh))
! !

!OpenAIAccountTest methodsFor: 'tests'!
testClaims
	self deny: account isSignedIn.
	self assert: account email isNil.
	account tokens: (self tokens: self freshToken refresh: 'r1').
	self assert: account isSignedIn.
	self assert: account email equals: 'ada@example.com'.
	self assert: account accountId equals: 'acct-1'.
	self assert: account planType equals: 'pro'.
	self assert: account accessToken equals: self freshToken.
	self assert: server requests isEmpty.
	account signOut.
	self deny: account isSignedIn.
	self should: [account accessToken] raise: AgentError
!
testRefreshBeforeExpiry
	| body |
	account tokens: (self tokens: self expiredToken refresh: 'r1').
	self reply: '/oauth/token' with: {self tokenResponse: self freshToken refresh: 'r2'}.
	self assert: account accessToken equals: self freshToken.
	self assert: account accessToken equals: self freshToken.
	self assert: (self requestsTo: '/oauth/token') size equals: 1.
	body := (self requestsTo: '/oauth/token') first json.
	self assert: (body at: 'grant_type') equals: 'refresh_token'.
	self assert: (body at: 'refresh_token') equals: 'r1'.
	self assert: (body at: 'client_id') equals: OpenAIAccount clientId.
	self assert: (body at: 'refresh_reason') equals: 'proactive_expiry'.
	"the rotated refresh token is the next one used"
	self reply: '/oauth/token' with: {self tokenResponse: self freshToken2 refresh: 'r3'}.
	account refresh.
	self assert: ((self requestsTo: '/oauth/token') last json at: 'refresh_token') equals: 'r2'.
	self assert: account accessToken equals: self freshToken2
!
testRefusedRefreshSignsOut
	account tokens: (self tokens: self freshToken refresh: 'r1').
	self reply: '/oauth/token' with: {HTTPTestServer response: 400 body: '{"error":"invalid_grant"}'}.
	self should: [account refresh] raise: AgentError.
	self deny: account isSignedIn.
	account tokens: (self tokens: self freshToken refresh: 'r1').
	self reply: '/oauth/token' with: {HTTPTestServer response: 401 body: '{"error":{"code":"refresh_token_reused","message":"used"}}'}.
	self should: [account refresh] raise: AgentError.
	self deny: account isSignedIn
!
testKeptInAFile
	"keepIn: shares the sign-in through a file: another account on it sees the tokens, a sign-out deletes it, and a refresh another process already made is taken from the file."
	| path other |
	path := self scratchDirectory / 'agent' / 'account.json'.
	account keepIn: path.
	self deny: (File exists: path).
	account tokens: (self tokens: self freshToken refresh: 'r1').
	self assert: (File exists: path).
	other := OpenAIAccount new issuer: server url; keepIn: path; yourself.
	self assert: other isSignedIn.
	self assert: other email equals: 'ada@example.com'.
	"the other process refreshes: its rotated tokens reach me before I refresh"
	other tokens: (self tokens: self freshToken2 refresh: 'r2').
	self assert: account accessToken equals: self freshToken2.
	account tokens: (self tokens: self freshToken refresh: 'r1').
	other tokens: (self tokens: self freshToken2 refresh: 'r3').
	account refresh.
	self assert: account isSignedIn.
	self assert: account accessToken equals: self freshToken2.
	self assert: (self requestsTo: '/oauth/token') isEmpty.
	other signOut.
	self deny: (File exists: path).
	self deny: account isSignedIn
!
testFailedRefreshKeepsTheTokens
	account tokens: (self tokens: self freshToken refresh: 'r1').
	self reply: '/oauth/token' with: {HTTPTestServer response: 503 body: 'busy'}.
	self should: [account refresh] raise: AgentError withExceptionDo: [:e |
		self assert: (e messageText includesSubstring: '503: busy')].
	self assert: account isSignedIn
!
testDeviceLogin
	| form |
	self reply: '/api/accounts/deviceauth/usercode' with: {HTTPTestServer response: 200 body: '{"device_auth_id":"dev-1","user_code":"ABCD-1234","interval":"0.01","expires_at":"2100-01-01T00:00:00+00:00"}'}.
	self reply: '/api/accounts/deviceauth/token' with: {
		HTTPTestServer response: 403 body: '{"error":{"code":"deviceauth_authorization_pending"}}'.
		HTTPTestServer response: 403 body: '{"error":{"code":"deviceauth_authorization_pending"}}'.
		HTTPTestServer response: 200 body: '{"authorization_code":"code-1","code_verifier":"verifier-1"}'}.
	self reply: '/oauth/token' with: {self tokenResponse: self freshToken refresh: 'r1'}.
	self assert: account loginURL isNil.
	account startLogin.
	self assert: account loginURL equals: server url, '/codex/device'.
	self assert: account loginCode equals: 'ABCD-1234'.
	self assert: (((self requestsTo: '/api/accounts/deviceauth/usercode') first json) at: 'client_id') equals: OpenAIAccount clientId.
	self assert: account finishLogin.
	self assert: (self requestsTo: '/api/accounts/deviceauth/token') size equals: 3.
	self assert: ((self requestsTo: '/api/accounts/deviceauth/token') first json at: 'device_auth_id') equals: 'dev-1'.
	form := (self requestsTo: '/oauth/token') first form.
	self assert: (form at: 'grant_type') equals: 'authorization_code'.
	self assert: (form at: 'code') equals: 'code-1'.
	self assert: (form at: 'code_verifier') equals: 'verifier-1'.
	self assert: (form at: 'redirect_uri') equals: server url, '/deviceauth/callback'.
	self assert: account isSignedIn.
	self assert: account email equals: 'ada@example.com'.
	self assert: account loginURL isNil.
	self assert: account loginCode isNil
!
testCancelLogin
	| outcome |
	self reply: '/api/accounts/deviceauth/usercode' with: {HTTPTestServer response: 200 body: '{"device_auth_id":"dev-1","user_code":"ABCD-1234","interval":"0.05"}'}.
	self reply: '/api/accounts/deviceauth/token' with: {HTTPTestServer response: 403 body: '{}'}.
	account startLogin.
	self fork: [outcome := account finishLogin].
	self assert: (self waitFor: [(self requestsTo: '/api/accounts/deviceauth/token') size >= 2]).
	account cancelLogin.
	self assert: (self waitFor: [outcome notNil]).
	self deny: outcome.
	self deny: account isSignedIn
!
testLoginRefused
	self reply: '/api/accounts/deviceauth/usercode' with: {HTTPTestServer response: 429 body: '{"detail":"slow down"}'}.
	self should: [account startLogin] raise: AgentError withExceptionDo: [:e |
		self assert: (e messageText includesSubstring: '429: slow down')]
! !
