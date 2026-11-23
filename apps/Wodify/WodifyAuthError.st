WodifyError subclass: #WodifyAuthError
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'Wodify'!

WodifyAuthError comment: 'I am Wodify rejecting the session (HTTP 401 or 403, or an exception about the login, the session, permissions or the CSRF token): the client logs in again.'!
