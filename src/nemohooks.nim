## nemohooks - Xposed/Zygisk-style hooks for Mono runtimes, written in Nim.
##
## A module built on this library is a shared object loaded into a target process. It finds the
## target's already-mapped Mono runtime, resolves the entry points it needs out of that image,
## and redirects managed methods through Dobby trampolines. `runtime` drives all of it: call
## `registerFeatures` with the `Feature`s to install, then `startRuntimePoll` from the JNI
## entry point.
##
## Every module here opts into two Nimony features, which is worth stating once rather than in
## each file:
##
## - `lenientnils`, because this is raw interop - Mono object pointers, Dobby trampolines, ELF
##   symbol tables - where nil is a normal value rather than an error, and Nimony makes every
##   `ptr` not-nil by default. The stdlib modules ported from Nim do the same.
## - `assumeSync`, because the resolved entry points are globals written once while the target's
##   runtime comes up and only read afterwards, which Nimony's thread-safety analysis cannot
##   see. Its own ioring backends opt out the same way.
##
## The Android log tag defaults to "nemohooks"; set `-d:nemohooksLogTag=YourTag` to change it.

import nemohooks/[compat, log, elfsyms, mono, hook, runtime]
export compat, log, elfsyms, mono, hook, runtime
