Object subclass: #WodifyClient
	instanceVariableNames: 'base http jar versionToken api session'
	classVariableNames: ''
	package: 'Wodify'!

WodifyClient comment: 'I talk to a gym''s Wodify member app (https://<gym>.wodify.com/WodifyClient/) as the app itself does. Wodify has no public member API, so I call the OutSystems "screenservices" its pages call: log in with email and password (Prepare_Login, then Do_Login; then the same again for another of the account''s gyms if the config names one), then GetAllWorkoutData once per day. The apiVersion of each action comes from the app''s current scripts (moduleinfo lists them), so an update of the app does not break me.

The session (cookies, in an HTTPCookieJar, and the user''s ids) lives in memory for as long as I do; when Wodify rejects it I log in again. The password is only ever sent to Wodify. Responses carry the member''s profile (address, phone, emergency contact): I keep none of it.

	client := WodifyClient config: (JSON parse: (File readText: ''~/.config/omarchy/wodify.json'')).
	client responseForDay: (Date year: 2026 month: 11 day: 23)'!

!WodifyClient methodsFor: 'initialization'!
setHost: aHost
	base := 'https://', aHost.
	http := HTTPClient new.
	jar := HTTPCookieJar new.
	api := Dictionary new
! !

!WodifyClient methodsFor: 'accessing'!
url
	"The member app, for the browser."
	^base, '/WodifyClient/'
!
session
	^session
!
close
	http close
! !

!WodifyClient methodsFor: 'requests'!
get: aPath
	| response |
	response := http get: base, aPath headers: (jar add: base, aPath to: self baseHeaders).
	jar receive: response from: base, aPath.
	response isSuccess ifFalse: [^self failure: 'Wodify returned HTTP ', response status printString].
	^response string
!
baseHeaders
	^Dictionary new
		at: 'User-Agent' put: self class userAgent;
		yourself
!
call: aName payload: aDictionary view: aView
	"Call the action aName (Prepare_Login …) with aDictionary's fields; answer its data (a Dictionary)."
	| body url headers response data exception |
	versionToken isNil ifTrue: [self loadVersions].
	body := Dictionary new.
	body at: 'versionInfo' put: (Dictionary new at: 'moduleVersion' put: versionToken; at: 'apiVersion' put: (api at: aName); yourself).
	body at: 'viewName' put: aView.
	aDictionary keysAndValuesDo: [:k :v | body at: k put: v].
	url := base, '/', self class module, '/', (self class actions at: aName) last.
	headers := self baseHeaders.
	headers at: 'Accept' put: 'application/json'.
	headers at: 'X-CSRFToken' put: self csrf.
	jar add: url to: headers.
	response := http request: 'POST' url: url
		headers: (headers at: 'Content-Type' put: 'application/json; charset=UTF-8'; yourself)
		body: (JSON render: body) utf8Encoded do: nil.
	jar receive: response from: url.
	(response status = 401 or: [response status = 403]) ifTrue: [
		^WodifyAuthError new signal: 'session rejected (', response status printString, ')'].
	response isSuccess ifFalse: [^self failure: 'Wodify returned HTTP ', response status printString].
	data := [response json] on: Error do: [:e | ^self failure: 'Wodify sent something that is not JSON'].
	(data isKindOf: Dictionary) ifFalse: [^self failure: 'Wodify sent something unexpected'].
	exception := data at: 'exception' ifAbsent: [nil].
	(self class truthy: exception) ifTrue: [
		| message |
		message := (exception isKindOf: Dictionary)
			ifTrue: [(self class str: ((exception at: 'message' ifAbsent: [nil]) ifNil: [exception at: 'name' ifAbsent: [nil]]))]
			ifFalse: [self class str: exception].
		(#('login' 'session' 'permission' 'not authorized' 'csrf') anySatisfy: [:w | message asLowercase includesSubstring: w])
			ifTrue: [^WodifyAuthError new signal: message].
		^self failure: message].
	^self class dictionary: (data at: 'data' ifAbsent: [nil])
!
loadVersions
	"The module's version and each action's apiVersion, from the app's moduleinfo and scripts."
	| info manifest urls scripts |
	info := [JSON parse: (self get: '/', self class module, '/moduleservices/moduleinfo')] on: JSONError do: [:e | ^self failure: 'Wodify app changed: no moduleinfo'].
	manifest := self class dictionary: ((self class dictionary: info) at: 'manifest' ifAbsent: [nil]).
	versionToken := manifest at: 'versionToken' ifAbsent: [^self failure: 'Wodify app changed: no versionToken'].
	urls := self class dictionary: (manifest at: 'urlVersions' ifAbsent: [nil]).
	scripts := Dictionary new.
	self class actions keysAndValuesDo: [:name :pair |
		| path script version |
		path := urls keys detect: [:u | u beginsWith: '/', self class module, '/scripts/', pair first] ifNone: [
			^self failure: 'Wodify app changed: script ', pair first, ' not found'].
		script := scripts at: path ifAbsentPut: [self get: path, (self class str: (urls at: path))].
		version := self class apiVersionOf: name endpoint: pair last in: script.
		version isNil ifTrue: [^self failure: 'Wodify app changed: ', name, ' not found'].
		api at: name put: version]
!
csrf
	"The CSRF token of the session's nr2 cookie, else OutSystems' fixed anonymous one."
	jar cookies do: [:c |
		(((c at: #name) beginsWith: 'nr2') and: [(c at: #domain) endsWith: 'wodify.com']) ifTrue: [
			| value i stop |
			value := self class percentDecode: (c at: #value).
			i := value indexOfSubCollection: 'crf=' startingAt: 1.
			i > 0 ifTrue: [
				stop := value indexOf: $; startingAt: i.
				stop = 0 ifTrue: [stop := value size + 1].
				stop > (i + 4) ifTrue: [^value copyFrom: i + 4 to: stop - 1]]]].
	^self class anonymousCSRF
!
failure: aString
	^WodifyError new signal: aString
! !

!WodifyClient methodsFor: 'login'!
login: config
	"Log in as config's email and password, at config's gym if it names one; answer the session."
	| prep resp user customer want |
	jar clear.
	session := nil.
	((self class truthy: (config at: 'email' ifAbsent: [nil])) and: [self class truthy: (config at: 'password' ifAbsent: [nil])])
		ifFalse: [^self failure: 'config: email and password are required'].
	prep := self prepareLogin: (self loginRequestUser: (config at: 'email') password: (config at: 'password')).
	resp := self class dictionary: (prep at: 'Response' ifAbsent: [nil]).
	(self class errorOf: resp) ifNotEmpty: [:err | ^self failure: 'login: ', err].
	(self class truthy: (prep at: 'UserNeedsToPerformMFA' ifAbsent: [nil])) ifTrue: [
		^self failure: 'login: your account requires multi-factor authentication'].
	user := self class dictionary: (resp at: 'ResponseGetUserData' ifAbsent: [nil]).
	(self class hasId: (user at: 'UserId' ifAbsent: [nil])) ifFalse: [^self failure: 'login failed (no user returned)'].
	user at: 'ClientIsInactive' put: (self class truthy: (prep at: 'ClientIsInactive' ifAbsent: [nil])).
	customer := resp at: 'Customer' ifAbsent: [''].
	user := self doLogin: user customer: customer.
	"logging in lands on the account's default gym: switch as the app's gym dropdown does"
	want := (self class str: (config at: 'gym' ifAbsent: [''])) trimBoth asLowercase.
	(want notEmpty and: [want ~= (self class str: (user at: 'CustomerId' ifAbsent: [nil]))
		and: [want ~= (self class str: (user at: 'CustomerPublicName' ifAbsent: [''])) asLowercase]]) ifTrue: [
			| pair |
			pair := self switchTo: want named: (config at: 'gym') from: user.
			user := pair first.
			customer := pair last].
	session := Dictionary new.
	#('UserId' 'GlobalUserId' 'CustomerId' 'ActiveLocationId' 'GymProgramId' 'SystemOfMeasureWeight' 'CustomerPublicName')
		do: [:k | session at: k put: (user at: k ifAbsent: [nil])].
	session at: 'Customer' put: customer.
	^session
!
loginRequestUser: email password: password
	^Dictionary new
		at: 'UserName' put: email; at: 'Password' put: password; at: 'IsToLogin' put: true;
		at: 'CustomerId' put: '0'; at: 'UserId' put: '0'; at: 'WhiteLabelAppCustomerId' put: '0';
		at: 'IsOTPSignIn' put: false; at: 'IsSocialSignIn' put: false; at: 'NotCheckSingleUserIsActive' put: false;
		yourself
!
prepareLogin: aRequest
	^self call: 'Prepare_Login' payload: (Dictionary new
		at: 'inputParameters' put: (Dictionary new at: 'Request' put: aRequest; at: 'IsMFAEnabled_Customers' put: false; yourself);
		yourself) view: '*'
!
doLogin: user customer: customer
	"Complete a login; answer the user's data (the prepared user if Do_Login returns none)."
	| done resp data |
	done := self call: 'Do_Login' payload: (Dictionary new
		at: 'inputParameters' put: (Dictionary new
			at: 'ValidatedLogin' put: (Dictionary new at: 'UserData' put: user; at: 'Customer' put: customer; yourself);
			at: 'IsToLogin' put: true; at: 'IsTrustDeviceForMFA' put: false; at: 'TrustDeviceForDays' put: 0;
			at: 'BrowserType' put: 'Chrome'; at: 'DeviceType' put: 'desktop'; at: 'OSType' put: 'linux';
			at: 'IsCordovaDefined' put: false; at: 'SocialLoginUserId' put: ''; at: 'SocialLoginProviderTypeId' put: '0';
			yourself);
		yourself) view: '*'.
	resp := self class dictionary: (done at: 'Response' ifAbsent: [nil]).
	(self class errorOf: resp) ifNotEmpty: [:err | ^self failure: 'login: ', err].
	data := self class dictionary: (resp at: 'ResponseGetUserData' ifAbsent: [nil]).
	^(self class hasId: (data at: 'UserId' ifAbsent: [nil])) ifTrue: [data] ifFalse: [user]
!
switchTo: want named: aName from: user
	"Log in to the account's gym want (its id or a part of its name); answer {user. customer}."
	| gyms accounts match prep resp newUser |
	gyms := self call: 'DataActionGetCustomers' payload: (Dictionary new
		at: 'screenData' put: (Dictionary new
			at: 'variables' put: (Dictionary new
				at: 'GlobalUserId' put: (self class str: (user at: 'GlobalUserId' ifAbsent: [nil]));
				at: 'UsersDefaultCustomerId' put: (self class str: (user at: 'CustomerId' ifAbsent: [nil]));
				at: 'IsChangingCustomer' put: false;
				yourself);
			yourself);
		yourself) view: 'MainScreens.Exercise'.
	accounts := self class list: ((self class dictionary: (gyms at: 'Response' ifAbsent: [nil])) at: 'GymAccount' ifAbsent: [nil]).
	accounts := accounts select: [:a | a isKindOf: Dictionary].
	match := accounts detect: [:a |
			want = (self class str: (a at: 'CustomerId' ifAbsent: [nil]))
				or: [want = (self class str: (a at: 'PublicName' ifAbsent: [''])) asLowercase]]
		ifNone: [accounts detect: [:a | (self class str: (a at: 'PublicName' ifAbsent: [''])) asLowercase includesSubstring: want] ifNone: [nil]].
	match isNil ifTrue: [
		^self failure: 'config: gym ', aName printString, ' not found (your gyms: ',
			((accounts collect: [:a | self class str: (a at: 'PublicName' ifAbsent: [nil])]) inject: '' into: [:s :n | s isEmpty ifTrue: [n] ifFalse: [s, ', ', n]]), ')'].
	prep := self prepareLogin: (Dictionary new
		at: 'UserName' put: ''; at: 'Password' put: ''; at: 'IsToLogin' put: false;
		at: 'CustomerId' put: (self class str: (match at: 'CustomerId')); at: 'UserId' put: (self class str: (match at: 'UserId' ifAbsent: [nil]));
		at: 'WhiteLabelAppCustomerId' put: '0';
		at: 'IsOTPSignIn' put: false; at: 'IsSocialSignIn' put: false; at: 'NotCheckSingleUserIsActive' put: false;
		yourself).
	resp := self class dictionary: (prep at: 'Response' ifAbsent: [nil]).
	(self class errorOf: resp) ifNotEmpty: [:err | ^self failure: 'switching gym: ', err].
	newUser := self class dictionary: (resp at: 'ResponseGetUserData' ifAbsent: [nil]).
	newUser at: 'ClientIsInactive' put: (self class truthy: (prep at: 'ClientIsInactive' ifAbsent: [nil])).
	^Array
		with: (self doLogin: newUser customer: (resp at: 'Customer' ifAbsent: ['']))
		with: (resp at: 'Customer' ifAbsent: [''])
! !

!WodifyClient methodsFor: 'workouts'!
responseForDay: aDate
	"GetAllWorkoutData's Response for aDate (a Dictionary), in the session's gym and program."
	| request data now |
	now := TimeZone local localSecondsAt: Time utcMicroseconds // 1000000.
	request := Dictionary new
		at: 'IsCoachOrAbove' put: false;
		at: 'CustomerId' put: (self class str: (session at: 'CustomerId'));
		at: 'SelectedDate' put: aDate printString;
		at: 'IsRefreshingButtons' put: false;
		at: 'GlobalUserId' put: (self class str: (session at: 'GlobalUserId'));
		at: 'DateTime' put: (self class isoLocal: now);
		at: 'UOMWeightId' put: (([(self class str: (session at: 'SystemOfMeasureWeight')) asInteger] on: Error do: [:e | e return: nil]) ifNil: [0]);
		at: 'IsChangeDate' put: true;
		at: 'IsCoachViewEnabled' put: false;
		at: 'UserId' put: (self class str: (session at: 'UserId'));
		at: 'GymProgramId' put: (self class str: ((session at: 'GymProgramId') ifNil: [0]));
		at: 'ActiveLocationId' put: (self class str: (session at: 'ActiveLocationId'));
		at: 'Customer' put: (session at: 'Customer' ifAbsent: ['']);
		yourself.
	"roles are checked against the hosting screen"
	data := self call: 'DataActionGetAllWorkoutData' payload: (Dictionary new
		at: 'screenData' put: (Dictionary new
			at: 'variables' put: (Dictionary new
				at: 'PriorDateTime' put: '1900-01-01T00:00:00';
				at: 'RequestCache' put: request;
				at: 'In_Request' put: request;
				at: '_in_RequestInDataFetchStatus' put: 1;
				yourself);
			yourself);
		yourself) view: 'MainScreens.Exercise'.
	^(self class truthy: (data at: 'Response' ifAbsent: [nil])) ifTrue: [self class dictionary: (data at: 'Response')] ifFalse: [data]
!
days: dates config: config
	"Each of dates shaped for the card (WodifyDay), logged in first unless I hold a session; logged in again once if Wodify rejected it."
	| fetch |
	fetch := [dates collect: [:d | WodifyDay date: d response: (self responseForDay: d)]].
	session isNil ifTrue: [
		self login: config.
		^fetch value].
	^fetch on: WodifyAuthError do: [:e |
		self login: config.
		e return: fetch value]
! !

!WodifyClient class methodsFor: 'instance creation'!
config: aDictionary
	"A client of the gym aDictionary's host names (<gym>.wodify.com)."
	| host |
	host := self str: (aDictionary at: 'host' ifAbsent: ['']).
	(self isWodifyHost: host) ifFalse: [^WodifyError new signal: 'config: host must look like <gym>.wodify.com'].
	^self new setHost: host
! !

!WodifyClient class methodsFor: 'protocol'!
module
	^'WodifyClient'
!
anonymousCSRF
	"OutSystems' fixed token of an anonymous session."
	^'T6C+9iB49TLra4jEsMeSckDMNhQ='
!
userAgent
	^'Mozilla/5.0 (X11; Linux x86_64) samaltak-wodify'
!
actions
	"Each action's script name prefix and endpoint."
	^Dictionary new
		at: 'Prepare_Login' put: #('WodifyClient.controller__' 'screenservices/WodifyClient/ActionPrepare_Login');
		at: 'Do_Login' put: #('WodifyClient.controller__' 'screenservices/WodifyClient/ActionDo_Login');
		at: 'DataActionGetCustomers' put: #('WodifyClient.Common.DropdownCustomer.mvc__'
			'screenservices/WodifyClient/Common/DropdownCustomer/DataActionGetCustomers');
		at: 'DataActionGetAllWorkoutData' put: #('WodifyClient_DataFetch_WB.WOD_Flow.GetAllWorkoutData_WB.mvc__'
			'screenservices/WodifyClient_DataFetch_WB/WOD_Flow/GetAllWorkoutData_WB/DataActionGetAllWorkoutData');
		yourself
!
apiVersionOf: aName endpoint: anEndpoint in: aScript
	"The apiVersion in a script's call of aName: callDataAction('Name', ['<uuid>', ]'endpoint', '<apiVersion>', ...); nil if there is none."
	| needle tail pos |
	needle := '"', aName, '", '.
	tail := '"', anEndpoint, '", "'.
	pos := 1.
	[(pos := aScript indexOfSubCollection: needle startingAt: pos) > 0] whileTrue: [
		| p |
		p := pos + needle size.
		"data actions carry an id between name and endpoint"
		(self isUUIDIn: aScript at: p + 1) ifTrue: [
			((aScript at: p) = $" and: [(aScript copyFrom: p + 37 to: (p + 39 min: aScript size)) = '", ']) ifTrue: [p := p + 40]].
		(aScript size >= (p + tail size - 1) and: [(aScript copyFrom: p to: p + tail size - 1) = tail]) ifTrue: [
			| start stop |
			start := p + tail size.
			stop := aScript indexOf: $" startingAt: start.
			stop > start ifTrue: [^aScript copyFrom: start to: stop - 1]].
		pos := pos + 1].
	^nil
!
isUUIDIn: aString at: start
	start + 35 > aString size ifTrue: [^false].
	start to: start + 35 do: [:i | ((aString at: i) isDigit or: ['abcdef-' includes: (aString at: i)]) ifFalse: [^false]].
	^true
!
isWodifyHost: aString
	"<gym>.wodify.com, the gym's name lowercase letters, digits and dashes."
	| gym |
	(aString endsWith: '.wodify.com') ifFalse: [^false].
	gym := aString copyFrom: 1 to: aString size - 11.
	^gym notEmpty and: [gym allSatisfy: [:c | (c isLetter and: [c isLowercase]) or: [c isDigit or: [c = $-]]]]
!
errorOf: aResponse
	"The error message of a login response's Error or ErrorAccount, '' if neither has one."
	#('Error' 'ErrorAccount') do: [:key |
		| e |
		e := self dictionary: (aResponse at: key ifAbsent: [nil]).
		((self truthy: (e at: 'HasError' ifAbsent: [nil])) or: [self truthy: (e at: 'ErrorMessage' ifAbsent: [nil])]) ifTrue: [
			^(self truthy: (e at: 'ErrorMessage' ifAbsent: [nil])) ifTrue: [self str: (e at: 'ErrorMessage')] ifFalse: ['unknown error']]].
	^''
! !

!WodifyClient class methodsFor: 'values'!
truthy: anObject
	"As Python and JavaScript test: nil, false, 0, '' and empty collections are false."
	anObject isNil ifTrue: [^false].
	anObject == false ifTrue: [^false].
	anObject isNumber ifTrue: [^anObject ~= 0].
	(anObject isString or: [anObject isKindOf: Collection]) ifTrue: [^anObject notEmpty].
	^true
!
str: anObject
	"Python's str of a JSON value."
	anObject isNil ifTrue: [^'None'].
	anObject isString ifTrue: [^anObject].
	anObject == true ifTrue: [^'True'].
	anObject == false ifTrue: [^'False'].
	^anObject printString
!
hasId: anObject
	"An id other than 0."
	| s |
	s := (self truthy: anObject) ifTrue: [self str: anObject] ifFalse: ['0'].
	^s anySatisfy: [:c | c ~= $0]
!
dictionary: anObject
	^(anObject isKindOf: Dictionary) ifTrue: [anObject] ifFalse: [Dictionary new]
!
list: anObject
	"OutSystems sends lists as {'List': [...]}; either form."
	| value |
	value := (anObject isKindOf: Dictionary) ifTrue: [anObject at: 'List' ifAbsent: [nil]] ifFalse: [anObject].
	^(value isKindOf: Array) ifTrue: [value] ifFalse: [#()]
!
isoLocal: localSeconds
	"YYYY-MM-DDTHH:MM:SS of seconds since 1970 in local time."
	| date s |
	date := Date fromDays: localSeconds // 86400.
	s := localSeconds \\ 86400.
	^date printString, 'T', ((s // 3600) printPaddedWith: $0 to: 2), ':', ((s \\ 3600 // 60) printPaddedWith: $0 to: 2), ':', ((s \\ 60) printPaddedWith: $0 to: 2)
!
percentDecode: aString
	| bytes i |
	(aString includes: $%) ifFalse: [^aString].
	bytes := WriteStream on: (ByteArray new: aString size).
	i := 1.
	[i <= aString size] whileTrue: [
		| c |
		c := aString at: i.
		(c = $% and: [i + 2 <= aString size and: [((aString copyFrom: i + 1 to: i + 2) allSatisfy: [:h | h isDigit or: ['abcdefABCDEF' includes: h]])]])
			ifTrue: [
				bytes nextPut: (Integer readFrom: (aString copyFrom: i + 1 to: i + 2) asUppercase base: 16).
				i := i + 3]
			ifFalse: [
				bytes nextPutAll: (String with: c) utf8Encoded.
				i := i + 1]].
	^bytes contents utf8Decoded
! !
