## Raw interop; see nemohooks.nim for why these two features are on.
when defined(nimony):
  {.feature: "lenientnils".}
  {.feature: "assumeSync".}

  ## Nimony has no Atomic[T] of its own; ours lives in compat.
  import compat

  ## quit is auto-imported from system in Nim 2 but lives in syncio under Nimony.
  import std/syncio

import std/[atomics, strutils]
import log, mono

proc dobbyHook(target, replace: pointer, orig: ptr pointer): cint
  {.importc: "DobbyHook", header: "dobby.h", gcsafe.}

type
  Hook* = ref object
    ## One managed method redirected through a trampoline. `owner` is the assembly-qualified
    ## class name, `sym` the method name and `argc` its parameter count - the triple
    ## mono_class_get_method_from_name needs. `orig` receives the trampoline back to the
    ## original body, which a replacement reaches through `origAs`.
    owner*: string
    sym*: string
    argc*: int
    replacement*: pointer
    orig*: pointer
    installed*: bool

  Feature* = ref object of RootObj
    ## A group of hooks installed together. Subclass it, override `install`, and hand it to
    ## `registerFeatures`.
    ##
    ## `once` gives up after the first attempt instead of retrying; `blocking` stops the rest of
    ## the registry when this one fails, for a feature later ones depend on; `gates` makes setup
    ## count as complete only once this one is done.
    name*: string
    once*: bool
    blocking*: bool
    gates*: bool
    done*: bool

  VoidFn* = proc(self: pointer) {.cdecl, gcsafe.}
    ## A parameterless instance method, which is the shape most .ctor hooks need.

proc newHook*(owner, sym: string, argc: int, replacement: pointer): Hook =
  Hook(owner: owner, sym: sym, argc: argc, replacement: replacement)

proc origAs*[T](h: Hook): T =
  asProc[T](h.orig)

proc installAt*(h: Hook, target: pointer): bool {.discardable.} =
  if h.installed: return true
  if target == nil or h.replacement == nil: return false
  if dobbyHook(target, h.replacement, addr h.orig) != 0: return false
  h.installed = true
  true

proc install*(h: Hook, cls: MonoClass): bool {.discardable.} =
  h.installAt(methodAddr(cls, h.sym, h.argc))

proc shortName(qualified: string): string =
  let bare = qualified.split(',')[0]
  let dot = bare.rfind('.')
  if dot < 0: bare else: bare[dot + 1 .. ^1]

proc install*(h: Hook): bool {.discardable.} =
  let cls = getClass(h.owner)
  if cls == nil:
    logE(shortName(h.owner) & " class not found")
    return false
  h.install(cls)

method install*(f: Feature): bool {.base.} =
  when defined(nimony):
    quit "Feature.install is abstract"
  else:
    raise newException(Defect, "Feature.install is abstract")

var
  gSetup*: Atomic[bool]
    ## Set once every gating feature has installed. Hooks on the target's hot paths read it to
    ## stop driving setup retries.

template guard*(what: string, body: untyped) =
  ## Wraps the part of a replacement that may raise. A hook body runs on a thread the target's
  ## runtime owns, so an escaping exception unwinds through managed frames and takes the process
  ## with it; the call through to `orig` belongs outside this.
  when defined(nimony):
    try:
      body
    except:
      logE("hook " & what & " raised")
  else:
    try:
      body
    except CatchableError as e:
      logE("hook " & what & " raised: " & e.msg)
    except Defect as e:
      logE("hook " & what & " defect: " & e.msg)

proc findInherited*(c: MonoClass, name: string, depth = 4): pointer =
  ## The address of a parameterless method, walking up from `c`.
  methodAddrInherited(c, name, 0, depth)
