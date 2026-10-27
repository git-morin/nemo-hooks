## Finds the target's live Mono runtime, resolves its entry points, and drives the registered
## features until every gating one has installed.
##
## A module built on this library calls `registerFeatures` once at load and `startRuntimePoll`
## from its JNI init. Everything else here is the machinery those two set in motion: the poll
## thread that waits for the runtime to come up, and hooks on five Mono entry points that get
## another setup attempt onto a thread the runtime owns, since a managed class cannot be
## resolved from the poll thread before the domain exists.
##
## Raw interop; see nemohooks.nim for why these two features are on.
when defined(nimony):
  {.feature: "lenientnils".}
  {.feature: "assumeSync".}

import std/[atomics, os]
import log, elfsyms, mono, hook, compat

const defaultMonoSoname* = "libmonosgen-2.0.so"

type GetPtrFn = proc(): pointer {.cdecl, gcsafe.}

var
  gSoname = defaultMonoSoname
  gMono: ElfSyms
  gAttached: Atomic[bool]
  gPollStarted: Atomic[bool]
  gPollThread: PollThread
  gFeatures: seq[Feature]
  gInSetup: Atomic[bool]

proc monoSym*(name: cstring): pointer {.cdecl.} =
  ## A `SymResolver` over the attached image, for hooking entry points the library does not
  ## resolve itself.
  if not gMono.ok: default(pointer) else: gMono.sym(name)

proc monoSyms*(): ElfSyms = gMono

proc setMonoSoname*(soname: string) =
  ## Overrides the runtime library to look for. Call before `startRuntimePoll`; a target
  ## embedding Mono under another name (libmono-native, libcoreclr) needs it.
  gSoname = soname

proc registerFeatures*(fs: seq[Feature]) =
  ## Adds features to the setup registry, in the order they will be installed. Order is
  ## load-bearing when one feature resolves classes or fields a later one reads.
  for f in fs: gFeatures.add f

proc registerFeature*(f: Feature) =
  gFeatures.add f

proc setupComplete(): bool =
  for f in gFeatures:
    if f.gates and not f.done: return false
  true

proc doSetupImpl() =
  if corlib() == nil: return
  for f in gFeatures:
    if f.done: continue
    let ok = f.install()
    if ok or f.once: f.done = true
    if not ok and f.blocking: return
  if setupComplete():
    gSetup.store(true)
    logI("setup done")

proc doSetup*() =
  ## Installs every feature not yet done. Safe to call from any number of hook bodies at once:
  ## the first one in does the work and the rest return immediately.
  if gSetup.load(): return
  var expected = false
  if not gInSetup.compareExchange(expected, true): return
  doSetupImpl()
  gInSetup.store(false)

type
  LdstrFn = proc(a0, a1, a2, a3: pointer): MonoString {.cdecl, gcsafe.}
  ObjNewFn = proc(d: MonoDomain, k: MonoClass): MonoObject {.cdecl, gcsafe.}
  JitInitFn = proc(name: cstring): MonoDomain {.cdecl, gcsafe.}
  JitExecFn = proc(d: MonoDomain, asmv: pointer, argc: cint,
                   argv: pointer): cint {.cdecl, gcsafe.}
  RunMainFn = proc(asmv: pointer, argc: cint, argv: pointer): cint {.cdecl, gcsafe.}

var
  hLdstr = newHook("", "mono_ldstr_checked", 0, nil)
  hObjNew = newHook("", "mono_object_new", 0, nil)
  hJitInit = newHook("", "mono_jit_init", 0, nil)
  hJitExec = newHook("", "mono_jit_exec", 0, nil)
  hRunMain = newHook("", "mono_runtime_run_main", 0, nil)

var
  ldstrCalls = 0
  objNewCalls = 0

proc hookLdstr(a0, a1, a2, a3: pointer): MonoString {.cdecl.} =
  guard "ldstr":
    if a0 != nil: setDomain(a0)
    inc ldstrCalls
    if ldstrCalls <= 5 or ldstrCalls mod 500 == 0: logI("ldstr call #" & $ldstrCalls)
    if not gSetup.load() and ldstrCalls mod 20 == 2: doSetup()
  let orig = origAs[LdstrFn](hLdstr)
  if orig != nil: orig(a0, a1, a2, a3) else: nil

proc hookObjNew(d: MonoDomain, k: MonoClass): MonoObject {.cdecl.} =
  guard "object_new":
    if d != nil: setDomain(d)
    inc objNewCalls
    if objNewCalls <= 5 or objNewCalls mod 2000 == 0:
      logI("object_new call #" & $objNewCalls)
    if not gSetup.load() and objNewCalls mod 50 == 7: doSetup()
  let orig = origAs[ObjNewFn](hObjNew)
  if orig != nil: orig(d, k) else: nil

proc hookJitInit(name: cstring): MonoDomain {.cdecl.} =
  logI("jit_init('" & (if name == nil: "?" else: fromCString(name)) & "') called")
  let orig = origAs[JitInitFn](hJitInit)
  result = if orig != nil: orig(name) else: nil
  if result != nil: setDomain(result)
  if not gSetup.load(): doSetup()

proc hookJitExec(d: MonoDomain, asmv: pointer, argc: cint, argv: pointer): cint {.cdecl.} =
  logI("jit_exec called")
  if d != nil: setDomain(d)
  if not gSetup.load(): doSetup()
  let orig = origAs[JitExecFn](hJitExec)
  if orig != nil: orig(d, asmv, argc, argv) else: -1

proc hookRunMain(asmv: pointer, argc: cint, argv: pointer): cint {.cdecl.} =
  logI("run_main called")
  if pGetRootDomain != nil: setDomain(pGetRootDomain())
  if not gSetup.load(): doSetup()
  let orig = origAs[RunMainFn](hRunMain)
  if orig != nil: orig(asmv, argc, argv) else: -1

hLdstr.replacement = asPointer(hookLdstr)
hObjNew.replacement = asPointer(hookObjNew)
hJitInit.replacement = asPointer(hookJitInit)
hJitExec.replacement = asPointer(hookJitExec)
hRunMain.replacement = asPointer(hookRunMain)

## Each hook is installed on its own line rather than looped over an array literal: gathering
## these ref fields into one crashes nimony 0.6.3 (finalir.nim: `n.stmtKind in {StmtsS, ScopeS}`).
proc installOne(h: Hook, sym: SymResolver) =
  var name = h.sym
  h.installAt(sym(name.toCString))

proc installTriggerHooks*(sym: SymResolver) =
  var ldstrSym = hLdstr.sym
  let ldstr = sym(ldstrSym.toCString)
  if ldstr == nil:
    logE("mono_ldstr_checked not found")
    return
  if not hLdstr.installAt(ldstr):
    logE("ldstr hook failed")
  installOne(hJitExec, sym)
  installOne(hJitInit, sym)
  installOne(hRunMain, sym)
  var objNewSym = hObjNew.sym
  if not hObjNew.installAt(sym(objNewSym.toCString)):
    logE("object_new hook failed")
  logI("mono hooked")

proc callPtrFn(s: ElfSyms, name: cstring): pointer =
  let fn = asProc[GetPtrFn](s.sym(name))
  if fn == nil: default(pointer) else: fn()

proc runtimeIsUp(s: ElfSyms): bool {.gcsafe.} =
  ## Either accessor answering non-nil means mono_init has run in this image. A copy mapped but
  ## never initialised returns nil from both.
  callPtrFn(s, "mono_get_corlib") != nil or callPtrFn(s, "mono_get_root_domain") != nil

proc attachRuntime*(): bool {.discardable.} =
  ## Attaches to the live runtime if it is up, resolving its entry points and installing the
  ## trigger hooks on the first success. Answers false while no initialised image is mapped.
  if gAttached.load(): return true
  if not gMono.ok:
    let s = findLiveImage(gSoname, runtimeIsUp)
    if not s.ok: return false
    gMono = s
    logI(gSoname & " attached: live runtime at base=" & hex(cast[pointer](s.bias)) &
         " (corlib=" & hex(callPtrFn(s, "mono_get_corlib")) &
         " root_domain=" & hex(callPtrFn(s, "mono_get_root_domain")) &
         ", " & $residentInstances(gSoname).len & " resident instance(s), " &
         $s.count & " syms)")
  var expected = false
  if not gAttached.compareExchange(expected, true): return true
  resolveMono(monoSym)
  installTriggerHooks(monoSym)
  true

proc attachNow*(tries = 20, delayMs = 100): bool {.discardable.} =
  ## Attaches and runs setup on the calling thread, for an injection point that already runs
  ## inside the target late enough for the runtime to be up.
  for _ in 0 ..< tries:
    if attachRuntime():
      doSetup()
      return true
    sleep(delayMs)
  false

proc pollBody() =
  sleep(2000)
  var i = 0
  while not attachRuntime():
    if i > 0 and i mod 300 == 0:
      logI("still waiting for a live " & gSoname & " runtime (" & $(i div 5 + 2) & "s elapsed)")
    sleep(200)
    inc i
  i = 0
  while not gSetup.load():
    doSetup()
    if gSetup.load(): break
    if i > 0 and i mod 25 == 0: logI("background doSetup retry #" & $i)
    sleep(500)
    inc i

## The poll runs on its own thread and reaches the globals the setup path resolves. Nim 2 needs
## that promise spelled out; Nimony's effect system is opt-in and has no `gcsafe` to cast, so
## only the call is gated rather than the loop above.
proc pollLoop() =
  when defined(nimony):
    pollBody()
  else:
    {.cast(gcsafe).}:
      pollBody()

## The thread entry point. Nim 2 wants `{.thread.}`, which Nimony does not have, so only the
## signature is gated and the body above is shared.
when defined(nimony):
  proc pollEntry(arg: pointer) {.nimcall.} = pollLoop()
else:
  proc pollEntry(arg: pointer) {.thread, nimcall.} = pollLoop()

proc startRuntimePoll*() =
  ## Starts the background poll, at most once per process. Call this from the JNI init: the
  ## injection runs long before the target's runtime exists, so there is nothing to attach to
  ## yet and the calling thread must not block.
  var expected = false
  if not gPollStarted.compareExchange(expected, true): return
  startThread(gPollThread, pollEntry)
