!Application methodsFor: '*UI-Agent'!
agentContext
	"What the Agent opened from my right-click menu binds: me (self), my window (its content is my card or view) and my world; and what the model should know about running in an application. Subclasses bind more (super agentContext bind: #service to: service; yourself)."
	^AgentContext new
		label: self title;
		receiver: self;
		bind: #window to: window;
		bind: #content to: (window isNil ifFalse: [window content]);
		bind: #world to: world;
		notes: self agentNotes;
		yourself
!
agentNotes
	"For the model: where it is and how to change what the user sees."
	| directory |
	directory := Compiler packageDirectoryOf: self class packageName.
	^'This is the application ', self class name, ' (package ', self class packageName,
		(directory isNil ifTrue: [''] ifFalse: [', source ', directory]),
		'), a window of the Linux desktop''s window manager, running in a process of its own on the runtime image: the system and the widgets, no development tools and no desktop World. The agent''s own window is another host window of this process. window content is the View the user sees; code that touches it runs in the window''s Process: window do: [...] (window sync: [...] answers a value); after a change, window content invalidate, and self fitToContent when its height may have changed. Methods compiled into the application''s classes change it at once; SourceFiler writes them to its source directory.'
! !
