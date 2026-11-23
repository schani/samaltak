Column subclass: #AgentLoginCard
	instanceVariableNames: 'signInButton urlLabel codeRow codeLabel messageLabel urlCopyButton'
	classVariableNames: ''
	package: 'UI-Agent'!

AgentLoginCard comment: 'I am what an AgentWindow shows instead of its transcript while signed out: a "Sign in with ChatGPT" button, then the device login''s URL and code (large, with a Copy button), and a line of news (waiting, why the last attempt failed). The window runs the login; I only show its state.'!

!AgentLoginCard methodsFor: 'initialization'!
initialize
	super initialize.
	signInButton := Button label: 'Sign in with ChatGPT'.
	signInButton name: 'sign-in'; beDefault.
	urlLabel := Label text: '' font: #ui.
	urlLabel name: 'url'.
	urlCopyButton := Button label: 'Copy URL'.
	urlCopyButton name: 'copy-url'; sizeToContent.
	codeLabel := Label text: '' font: (Font faceNamed: 'JetBrainsMono-Bold' size: 28).
	codeLabel name: 'code'.
	codeRow := Row with: (Array
		with: (codeLabel sizeToContent; yourself)
		with: ((Button label: 'Copy' action: [self clipboardText: codeLabel text]) name: 'copy'; sizeToContent; yourself)
		with: Widget new).
	codeRow spacing: 14; fixed: 44; padding: (0 @ 10 corner: 0 @ 10).
	messageLabel := Label text: '' font: #uiItalic.
	messageLabel name: 'message'; color: #ink3.
	self addAll: (Array
		with: ((Label text: 'The agent needs your ChatGPT account.' font: #uiBold) fixed: 28; yourself)
		with: ((Row with: (Array with: (signInButton sizeToContent; yourself) with: Widget new)) fixed: 30; padding: (0 @ 4 corner: 0 @ 4); yourself)
		with: ((Row with: (Array with: (urlLabel sizeToContent; yourself) with: urlCopyButton with: Widget new)) spacing: 14; fixed: 30; yourself)
		with: codeRow
		with: (messageLabel fixed: 24; yourself)
		with: Widget new).
	self padding: (self gutter @ 30 corner: 20 @ 20).
	self showButton: nil
!
gutter
	^62
! !

!AgentLoginCard methodsFor: 'accessing'!
signInButton
	^signInButton
!
code
	^codeLabel text
!
message
	^messageLabel text
! !

!AgentLoginCard methodsFor: 'showing'!
showMessage: aString
	signInButton owner visible: false.
	messageLabel text: aString
!
showURL: aURL code: aCode
	urlLabel text: 'Open ', aURL, ' and enter this code:'.
	urlCopyButton action: [self clipboardText: aURL].
	urlLabel owner visible: true.
	codeLabel text: aCode.
	codeRow visible: true; layout.
	messageLabel text: 'Waiting for you to approve the sign-in…'
!
showButton: aStringOrNil
	"Signed out: the button, and why the last attempt failed."
	signInButton owner visible: true.
	urlLabel owner visible: false.
	codeRow visible: false.
	messageLabel text: (aStringOrNil ifNil: [''])
! !

!AgentLoginCard methodsFor: 'remote control'!
remoteRole
	^#group
!
remoteIsTransparent
	^false
! !
