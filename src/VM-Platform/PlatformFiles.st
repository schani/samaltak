VMPlatformModule subclass: #PlatformFiles
	instanceVariableNames: 'table'
	classVariableNames: 'K_FILE'
	package: 'VM-Platform'!

PlatformFiles comment: 'Files (raw file descriptors, unbuffered; handles of kind K_FILE, i = the descriptor), directories, FIFOs, child processes.'!

!PlatformFiles class methodsFor: 'declaring'!
declarations
	^#((table 'pf_table[1]'))
!
initialize
	K_FILE := 1
! !

!PlatformFiles methodsFor: 'private'!
failOS: what
	common failOS: what path: self null code: posixIO errno
!
failOS: what path: path
	common failOS: what path: path code: posixIO errno
!
fdOf: f
	"The descriptor of file handle f, -1 (and the error set) if it is none."
	<function>
	| o |
	o := common table: table at: f kind: K_FILE.
	o isNull ifTrue: [
		common setError: 'bad file handle %d' with: f.
		^-1].
	^o i asInt32
!
openFlags: mode
	^mode caseOf: {
		[PF_FILE_READ] -> [posixIO O_RDONLY].
		[PF_FILE_READ_WRITE] -> [posixIO O_RDWR bitOr: posixIO O_CREAT].
		[PF_FILE_APPEND] -> [(posixIO O_WRONLY bitOr: posixIO O_APPEND) bitOr: posixIO O_CREAT]}
		otherwise: [(posixIO O_RDWR bitOr: posixIO O_CREAT) bitOr: posixIO O_TRUNC]
! !

!PlatformFiles methodsFor: 'files'!
open: path mode: mode
	"mode: PF_FILE_READ, PF_FILE_READ_WRITE, PF_FILE_APPEND, PF_FILE_CREATE_TRUNCATE or PF_FILE_CREATE_PRIVATE (as PF_FILE_CREATE_TRUNCATE, but a file it creates only its owner may read and write: secrets)."
	<export>
	| fd h |
	platform init.
	(mode < 0 or: [mode > 4]) ifTrue: [
		common setError: 'bad file mode %d' with: mode.
		^0].
	fd := posixIO open: path flags: ((self openFlags: mode) bitOr: posixIO O_CLOEXEC) mode: (mode = PF_FILE_CREATE_PRIVATE ifTrue: [8r600] ifFalse: [8r644]).
	fd < 0 ifTrue: [
		self failOS: 'open' path: path.
		^0].
	h := common table: table add: K_FILE pointer: self null.
	(table v + h) i: fd.
	^h
!
close: f
	<export>
	| fd |
	fd := self fdOf: f.
	fd < 0 ifTrue: [^false].
	common table: table remove: f.
	(posixIO close: fd) = 0 ifTrue: [^true].
	self failOS: 'close'.
	^false
!
read: f into: buf count: n
	"< 0 on error."
	<var: #buf type: 'void *'>
	<export>
	| fd r |
	fd := self fdOf: f.
	fd < 0 ifTrue: [^-1].
	[r := posixIO read: fd into: buf count: n.
	 r < 0 and: [posixIO errno = posixIO EINTR]] whileTrue.
	r < 0 ifTrue: [self failOS: 'read'].
	^r
!
write: f bytes: buf count: n
	"< 0 on error."
	<var: #buf type: 'const void *'>
	<export>
	<var: #done type: 'size_t'>
	| fd p done r |
	fd := self fdOf: f.
	fd < 0 ifTrue: [^-1].
	p := self cCoerce: buf to: 'uint8_t *'.
	done := 0.
	[done < n] whileTrue: [
		r := posixIO write: fd bytes: p + done count: n - done.
		r < 0
			ifTrue: [
				posixIO errno ~= posixIO EINTR ifTrue: [
					self failOS: 'write'.
					^-1]]
			ifFalse: [done := done + r asUInt64]].
	^done asInt64
!
size: f
	<export>
	| fd st |
	fd := self fdOf: f.
	st := self local: 'struct stat'.
	fd < 0 ifTrue: [^-1].
	(posixIO fstat: fd into: st) ~= 0 ifTrue: [
		self failOS: 'fstat'.
		^-1].
	^st st_size
!
position: f
	<export>
	| fd r |
	fd := self fdOf: f.
	fd < 0 ifTrue: [^-1].
	r := posixIO lseek: fd offset: 0 whence: posixIO SEEK_CUR.
	r < 0 ifTrue: [self failOS: 'lseek'].
	^r
!
seek: f to: pos
	<export>
	| fd |
	fd := self fdOf: f.
	fd < 0 ifTrue: [^false].
	(posixIO lseek: fd offset: pos whence: posixIO SEEK_SET) >= 0 ifTrue: [^true].
	self failOS: 'lseek'.
	^false
!
flush: f
	"Writes are unbuffered, so flush only pushes regular files to disk."
	<export>
	| fd st |
	fd := self fdOf: f.
	st := self local: 'struct stat'.
	fd < 0 ifTrue: [^false].
	((posixIO fstat: fd into: st) = 0 and: [(posixIO S_ISREG: st st_mode) and: [(posixIO fsync: fd) ~= 0]]) ifTrue: [
		self failOS: 'fsync'.
		^false].
	^true
!
handleCount
	<export>
	^common table: table count: -1
! !

!PlatformFiles methodsFor: 'paths'!
delete: path
	<export>
	(posixIO unlink: path) = 0 ifTrue: [^true].
	((posixIO errno = posixIO EISDIR or: [posixIO errno = posixIO EPERM]) and: [(posixIO rmdir: path) = 0]) ifTrue: [^true].
	self failOS: 'delete' path: path.
	^false
!
rename: from to: to
	<export>
	(posixIO rename: from to: to) = 0 ifTrue: [^true].
	self failOS: 'rename' path: from.
	^false
!
stat: path into: s
	"A missing path is no error: s exists is false."
	<export>
	| st |
	st := self local: 'struct stat'.
	libc memset: s value: 0 size: (self sizeof: 'pf_stat').
	(posixIO stat: path into: st) ~= 0 ifTrue: [
		(posixIO errno = posixIO ENOENT or: [posixIO errno = posixIO ENOTDIR]) ifTrue: [^true].
		self failOS: 'stat' path: path.
		^false].
	s exists: true.
	s isDir: (posixIO S_ISDIR: st st_mode).
	s fileSize: st st_size.
	s mtimeUs: (st st_mtim tv_sec * 1000000) + (st st_mtim tv_nsec quo: 1000).
	^true
!
dirEntries: path count: n
	"A malloc'd array of n malloc'd names."
	<export>
	<var: #cap type: 'int'>
	| d cap v ok e nv s |
	d := posixIO opendir: path.
	d isNull ifTrue: [
		self failOS: 'opendir' path: path.
		^self null].
	cap := 64.
	v := self cCoerce: (libc malloc: (self sizeof: 'char *') * cap asUInt64) to: 'char **'.
	n value: 0.
	ok := v notNull.
	[ok and: [(e := posixIO readdir: d) notNull]] whileTrue: [
		((libc strcmp: e d_name with: '.') = 0 or: [(libc strcmp: e d_name with: '..') = 0]) ifFalse: [
			n value = cap ifTrue: [
				cap := cap * 2.
				nv := self cCoerce: (libc realloc: v size: (self sizeof: 'char *') * cap asUInt64) to: 'char **'.
				ok := nv notNull.
				ok ifTrue: [v := nv]].
			ok ifTrue: [
				s := libc strdup: e d_name.
				ok := s notNull.
				ok ifTrue: [
					v at: n value put: s.
					n value: n value + 1]]]].
	posixIO closedir: d.
	ok ifFalse: [
		[v notNull and: [n value > 0]] whileTrue: [
			n value: n value - 1.
			libc free: (v at: n value)].
		libc free: v.
		common setError: 'out of memory'.
		^self null].
	^v
!
dirCreate: path
	<export>
	(posixIO mkdir: path mode: 8r755) = 0 ifTrue: [^true].
	self failOS: 'mkdir' path: path.
	^false
!
cwd
	"malloc'd."
	<export>
	| p |
	p := posixIO getcwd: self null size: 0.
	p isNull ifTrue: [self failOS: 'getcwd'].
	^p
!
mkfifo: path
	<export>
	(posixIO mkfifo: path mode: 8r644) = 0 ifTrue: [^true].
	self failOS: 'mkfifo' path: path.
	^false
! !

!PlatformFiles methodsFor: 'processes'!
spawn: argv
	"argv first is looked up in PATH; stdio is inherited. The pid, < 0 on error."
	<returns: 'int64_t'>
	<export>
	| pid r |
	pid := self local: 'pid_t'.
	platform init.
	r := posixProcesses spawnp: pid file: (argv at: 0) fileActions: self null attributes: self null argv: argv envp: host environment.
	r ~= 0 ifTrue: [
		common failOS: 'posix_spawnp' path: (argv at: 0) code: r.
		^-1].
	^pid value
!
exec: argv
	"Replace the VM's process by argv first (looked up in PATH): same pid, standard streams; every other descriptor closes. Returns only on failure."
	<export>
	| maxFd flags |
	libc fflush: libc stdout.
	libc fflush: libc stderr.
	maxFd := posixProcesses getdtablesize.
	maxFd > 65536 ifTrue: [maxFd := 65536].
	3 to: maxFd - 1 do: [:fd |
		flags := posixIO fcntl: fd command: posixIO F_GETFD.
		flags >= 0 ifTrue: [posixIO fcntl: fd command: posixIO F_SETFD value: (flags bitOr: posixIO FD_CLOEXEC)]].
	posixProcesses execvp: (argv at: 0) argv: argv.
	self failOS: 'execvp' path: (argv at: 0)
!
processWait: pid block: block status: status done: done
	"status: the exit code, or 128 + the signal number."
	<export>
	| st r |
	st := self local: 'int'.
	[r := posixProcesses waitpid: pid asInt32 status: st options: (block ifTrue: [0] ifFalse: [posixProcesses WNOHANG]).
	 r < 0 and: [posixIO errno = posixIO EINTR]] whileTrue.
	r < 0 ifTrue: [
		self failOS: 'waitpid'.
		^false].
	done value: r ~= 0.
	done value ifTrue: [
		status value: ((posixProcesses WIFEXITED: st value)
			ifTrue: [posixProcesses WEXITSTATUS: st value]
			ifFalse: [128 + (posixProcesses WTERMSIG: st value)])].
	^true
! !

VMStruct subclass: #PfStat
	instanceVariableNames: ''
	classVariableNames: ''
	package: 'VM-Platform'!

PfStat comment: 'What platform_files_stat answers.'!

!PfStat class methodsFor: 'declaring'!
fields
	^#((exists bool) (isDir bool) (fileSize int64_t) (mtimeUs int64_t))
! !

