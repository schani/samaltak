TestCase subclass: #HTTPCookieJarTest
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'Tests-Net'!

HTTPCookieJarTest comment: 'Tests HTTPCookieJar: Set-Cookie headers kept apart in a response, domains, paths, Secure, expiry and replacing cookies.'!

!HTTPCookieJarTest methodsFor: 'support'!
response: setCookies
	^HTTPResponse new setStatus: 200 fields: (setCookies collect: [:v | 'set-cookie' -> v]), (Array with: 'content-type' -> 'text/html')
! !

!HTTPCookieJarTest methodsFor: 'tests'!
testResponseKeepsEachSetCookie
	| r |
	r := self response: #('a=1; Expires=Wed, 21 Oct 2099 07:28:00 GMT' 'b=2').
	self assert: (r allAt: 'Set-Cookie') equals: #('a=1; Expires=Wed, 21 Oct 2099 07:28:00 GMT' 'b=2').
	self assert: (r headerAt: 'Content-Type') equals: 'text/html'.
	self assert: (r headerAt: 'set-cookie') equals: 'a=1; Expires=Wed, 21 Oct 2099 07:28:00 GMT, b=2'
!
testDomainsAndPaths
	| jar |
	jar := HTTPCookieJar new.
	jar receive: (self response: #('host=1' 'wide=2; Domain=.example.com; Path=/' 'deep=3; Path=/app' 'other=4; Domain=evil.com'))
		from: 'https://www.example.com/app/login'.
	self assert: (jar headerFor: 'https://www.example.com/app/x') equals: 'host=1; deep=3; wide=2'.
	self assert: (jar headerFor: 'https://www.example.com/') equals: 'wide=2'.
	"host-only cookies stay with their host"
	self assert: (jar headerFor: 'https://api.example.com/app/x') equals: 'wide=2'.
	self assert: (jar headerFor: 'https://other.org/') isNil.
	self assert: (jar valueOf: 'other') isNil.
	"the default path is the request's directory"
	self assert: ((jar cookies detect: [:c | (c at: #name) = 'host']) at: #path) equals: '/app'
!
testSecureExpiryAndReplacing
	| jar |
	jar := HTTPCookieJar new.
	jar receive: (self response: #('s=1; Secure' 'old=1; Expires=Thu, 01 Jan 1970 00:00:01 GMT' 'm=1; Max-Age=3600'))
		from: 'https://example.com/'.
	self assert: (jar headerFor: 'https://example.com/') equals: 's=1; m=1'.
	self assert: (jar headerFor: 'http://example.com/') equals: 'm=1'.
	jar receive: (self response: #('m=2')) from: 'https://example.com/'.
	self assert: (jar valueOf: 'm') equals: '2'.
	jar receive: (self response: #('m=gone; Max-Age=0')) from: 'https://example.com/'.
	self assert: (jar valueOf: 'm') isNil.
	self assert: (HTTPCookieJar parseHTTPDate: 'Wed, 21 Oct 2015 07:28:00 GMT') equals: 1445412480.
	self assert: (HTTPCookieJar parseHTTPDate: 'Wednesday, 21-Oct-15 07:28:00 GMT') equals: 1445412480.
	self assert: (HTTPCookieJar parseHTTPDate: 'soon') isNil
! !
