CLibrary subclass: #PosixIO
	instanceVariableNames: 'errno'
	classVariableNames: ''
	package: 'VM-Platform'!

PosixIO comment: 'The file, directory, pipe and poll calls of the platform layer, with errno, strerror and the string functions they need. Files and directories are simulated with the image''s file primitives (macOS values for the flags and errno codes); pipes and poll are not.'!

!PosixIO class methodsFor: 'declaring'!
headers
	"struct stat's modification time is st_mtim (POSIX.1-2008); macOS calls it st_mtimespec."
	^#('<fcntl.h>' '<unistd.h>' '<sys/stat.h>' '<dirent.h>' '<errno.h>' '<string.h>' '<poll.h>' '<signal.h>'
		'#ifdef __APPLE__' '#define st_mtim st_mtimespec' '#endif' '"c4_platform_files.h"')
!
typedefs
	^#((mode_t uint16_t) (DIR opaque) (nfds_t uint32_t) (sig_t 'void (*)(int)'))
! !

!PosixIO methodsFor: 'simulation'!
notSimulated
	^self error: 'not simulated'
!
fail: code
	errno := code.
	^-1
!
fileModeFor: flags
	"The image's file mode (0 read, 1 read/write, 2 append, 3 create/truncate) of open flags."
	(flags bitAnd: self O_TRUNC) ~= 0 ifTrue: [^3].
	(flags bitAnd: self O_APPEND) ~= 0 ifTrue: [^2].
	(flags bitAnd: 3) = self O_RDWR ifTrue: [^1].
	^0
!
charPointerTo: anAddress
	^self memory pointerTo: (CTypeRegistry default at: 'char') at: anAddress
! !

!PosixIO methodsFor: 'files'!
open: path flags: flags mode: mode
	<c: 'int open(const char *path, int flags, ...)'>
	^(File primOpen: (self memory stringAt: path) mode: (self fileModeFor: flags)) ifNil: [self fail: self ENOENT]
!
c4OpenRegular: path flags: flags mode: mode
	<c: 'int c4_platform_open_regular(const char *path, int flags, uint16_t mode)'>
	^self notSimulated
!
close: fd
	<c: 'int close(int fd)'>
	^(File primClose: fd) isNil ifTrue: [self fail: self EIO] ifFalse: [0]
!
read: fd into: buf count: n
	<c: 'ssize_t read(int fd, void *buf, size_t n)'>
	| bytes r |
	bytes := ByteArray new: n.
	r := File primRead: fd into: bytes startingAt: 1 count: n.
	r isNil ifTrue: [^self fail: self EIO].
	self memory bytesAt: (self memory addressOf: buf) put: (bytes first: r).
	^r
!
write: fd bytes: buf count: n
	<c: 'ssize_t write(int fd, const void *buf, size_t n)'>
	^(File primWrite: fd from: (self memory bytesAt: (self memory addressOf: buf) count: n) startingAt: 1 count: n)
		ifNil: [self fail: self EIO]
!
lseek: fd offset: offset whence: whence
	"SEEK_SET, or SEEK_CUR by 0 (the position)."
	<c: 'off_t lseek(int fd, off_t offset, int whence)'>
	whence = self SEEK_SET ifTrue: [^(File primSeek: fd to: offset) isNil ifTrue: [self fail: self EIO] ifFalse: [offset]].
	^(File primPosition: fd) ifNil: [self fail: self EIO]
!
fstat: fd into: st
	<c: 'int fstat(int fd, struct stat *st)'>
	| size |
	size := File primSize: fd.
	size isNil ifTrue: [^self fail: self EIO].
	st st_mode: 16r8000.
	st st_size: size.
	^0
!
stat: path into: st
	<c: 'int stat(const char *path, struct stat *st)'>
	| s |
	s := File primStat: (self memory stringAt: path).
	(s at: 1) ifFalse: [^self fail: self ENOENT].
	st st_mode: ((s at: 2) ifTrue: [16r4000] ifFalse: [16r8000]).
	st st_size: (s at: 3).
	st st_mtim tv_sec: (s at: 4) // 1000000.
	st st_mtim tv_nsec: (s at: 4) \\ 1000000 * 1000.
	^0
!
S_ISDIR: m
	<c: 'bool S_ISDIR(mode_t m)'>
	^(m bitAnd: 16rF000) = 16r4000
!
S_ISREG: m
	<c: 'bool S_ISREG(mode_t m)'>
	^(m bitAnd: 16rF000) = 16r8000
!
fsync: fd
	<c: 'int fsync(int fd)'>
	^(File primFlush: fd) isNil ifTrue: [self fail: self EIO] ifFalse: [0]
!
unlink: path
	<c: 'int unlink(const char *path)'>
	^(File primDelete: (self memory stringAt: path)) isNil ifTrue: [self fail: self ENOENT] ifFalse: [0]
!
rmdir: path
	<c: 'int rmdir(const char *path)'>
	^self unlink: path
!
rename: from to: to
	<c: 'int rename(const char *from, const char *to)'>
	^(File primRename: (self memory stringAt: from) to: (self memory stringAt: to)) isNil ifTrue: [self fail: self ENOENT] ifFalse: [0]
!
mkdir: path mode: mode
	<c: 'int mkdir(const char *path, mode_t mode)'>
	^(File primDirCreate: (self memory stringAt: path)) isNil ifTrue: [self fail: self ENOENT] ifFalse: [0]
!
mkfifo: path mode: mode
	<c: 'int mkfifo(const char *path, mode_t mode)'>
	^self notSimulated
!
access: path mode: mode
	<c: 'int access(const char *path, int mode)'>
	^(File primStat: (self memory stringAt: path)) first ifTrue: [0] ifFalse: [self fail: self ENOENT]
!
getcwd: buf size: size
	"Only getcwd(NULL, 0), which mallocs."
	<c: 'char *getcwd(char *buf, size_t size)'>
	^self charPointerTo: (self memory newCString: File primCwd)
!
opendir: path
	<c: 'DIR *opendir(const char *path)'>
	| entries |
	entries := File primDirEntries: (self memory stringAt: path).
	entries isNil ifTrue: [self fail: self ENOENT. ^CPointer null].
	^self memory pointerTo: (CTypeRegistry default at: 'DIR') at: (self memory registerObject: (ReadStream on: entries , #('.' '..')))
!
readdir: d
	<c: 'struct dirent *readdir(DIR *d)'>
	| stream type entry |
	stream := self memory objectAt: (self memory addressOf: d).
	stream atEnd ifTrue: [^CPointer null].
	type := CTypeRegistry default at: 'struct dirent'.
	entry := type load: self memory at: (self memory allocate: type size).
	self memory bytesAt: (self memory addressOf: entry d_name) put: stream next utf8Encoded , #[0].
	^entry
!
closedir: d
	<c: 'int closedir(DIR *d)'>
	self memory forgetObject: (self memory objectAt: (self memory addressOf: d)).
	^0
!
O_RDONLY
	<cMacro: 'int O_RDONLY'>
	^0
!
O_WRONLY
	<cMacro: 'int O_WRONLY'>
	^1
!
O_RDWR
	<cMacro: 'int O_RDWR'>
	^2
!
O_NONBLOCK
	<cMacro: 'int O_NONBLOCK'>
	^4
!
O_APPEND
	<cMacro: 'int O_APPEND'>
	^8
!
O_CREAT
	<cMacro: 'int O_CREAT'>
	^16r200
!
O_TRUNC
	<cMacro: 'int O_TRUNC'>
	^16r400
!
O_CLOEXEC
	<cMacro: 'int O_CLOEXEC'>
	^16r1000000
!
SEEK_SET
	<cMacro: 'int SEEK_SET'>
	^0
!
SEEK_CUR
	<cMacro: 'int SEEK_CUR'>
	^1
!
X_OK
	<cMacro: 'int X_OK'>
	^1
! !

!PosixIO methodsFor: 'descriptors'!
pipe: fds
	<c: 'int pipe(int *fds)'>
	^self notSimulated
!
fcntl: fd command: cmd
	<c: 'int fcntl(int fd, int cmd, ...)'>
	^0
!
fcntl: fd command: cmd value: value
	<c: 'int fcntl(int fd, int cmd, ...)'>
	^0
!
poll: fds count: nfds timeout: timeout
	<c: 'int poll(struct pollfd *fds, nfds_t nfds, int timeout)'>
	^self notSimulated
!
signal: sig handler: handler
	<c: 'sig_t signal(int sig, sig_t handler)'>
	^FunctionPointer null
!
F_GETFL
	<cMacro: 'int F_GETFL'>
	^3
!
F_SETFL
	<cMacro: 'int F_SETFL'>
	^4
!
F_SETFD
	<cMacro: 'int F_SETFD'>
	^2
!
F_GETFD
	<cMacro: 'int F_GETFD'>
	^1
!
FD_CLOEXEC
	<cMacro: 'int FD_CLOEXEC'>
	^1
!
POLLIN
	<cMacro: 'int16_t POLLIN'>
	^1
!
POLLOUT
	<cMacro: 'int16_t POLLOUT'>
	^4
!
POLLERR
	<cMacro: 'int16_t POLLERR'>
	^8
!
POLLHUP
	<cMacro: 'int16_t POLLHUP'>
	^16
!
SIGPIPE
	<cMacro: 'int SIGPIPE'>
	^13
!
SIG_IGN
	<cMacro: 'sig_t SIG_IGN'>
	^FunctionPointer null
! !

!PosixIO methodsFor: 'errors'!
errno
	<cMacro: 'int errno'>
	^errno ifNil: [0]
!
strerror: code
	<c: 'char *strerror(int code)'>
	^self charPointerTo: (self memory cStringFor: (code caseOf: {
		[self EPERM] -> ['Operation not permitted'].
		[self ENOENT] -> ['No such file or directory'].
		[self EIO] -> ['Input/output error'].
		[self ENOTDIR] -> ['Not a directory'].
		[self EISDIR] -> ['Is a directory']} otherwise: ['Unknown error: ' , code printString]))
!
EPERM
	<cMacro: 'int EPERM'>
	^1
!
ENOENT
	<cMacro: 'int ENOENT'>
	^2
!
EINTR
	<cMacro: 'int EINTR'>
	^4
!
EIO
	<cMacro: 'int EIO'>
	^5
!
ENOTDIR
	<cMacro: 'int ENOTDIR'>
	^20
!
EISDIR
	<cMacro: 'int EISDIR'>
	^21
!
EAGAIN
	<cMacro: 'int EAGAIN'>
	^35
!
EWOULDBLOCK
	<cMacro: 'int EWOULDBLOCK'>
	^35
!
ECONNABORTED
	<cMacro: 'int ECONNABORTED'>
	^53
!
EINPROGRESS
	<cMacro: 'int EINPROGRESS'>
	^36
! !

!PosixIO methodsFor: 'strings'!
strchr: s char: c
	<c: 'char *strchr(const char *s, int c)'>
	| a b |
	a := self memory addressOf: s.
	[b := self memory uint8At: a.
	 b = c ifTrue: [^self charPointerTo: a].
	 b = 0] whileFalse: [a := a + 1].
	^CPointer null
!
strncmp: s1 with: s2 size: n
	<c: 'int strncmp(const char *s1, const char *s2, size_t n)'>
	| a b x y |
	a := self memory addressOf: s1.
	b := self memory addressOf: s2.
	0 to: n - 1 do: [:i |
		x := self memory uint8At: a + i.
		y := self memory uint8At: b + i.
		(x ~= y or: [x = 0]) ifTrue: [^x - y]].
	^0
! !

ExternStruct subclass: #Stat
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'VM-Platform'!

!Stat class methodsFor: 'declaring'!
cName
	^'struct stat'
!
fields
	^#((st_mode mode_t) (st_size off_t) (st_mtim 'struct timespec'))
! !

ExternStruct subclass: #Dirent
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'VM-Platform'!

!Dirent class methodsFor: 'declaring'!
cName
	^'struct dirent'
!
fields
	^#((d_name 'char[1024]'))
! !

ExternStruct subclass: #PollFd
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'VM-Platform'!

!PollFd class methodsFor: 'declaring'!
cName
	^'struct pollfd'
!
fields
	^#((fd int) (events int16_t) (revents int16_t))
! !
