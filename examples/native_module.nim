## A native module example: trace libc `open` calls and a per-frame function in the game.
## One hook is on an exported symbol, the other on an offset into a stripped library.

include nemohooks/features

import nemohooks
import nemohooks/backends/native

const game = "libgame.so"

type
  OpenFn = proc (path: cstring, flags: cint): cint {.cdecl, gcsafe.}
  TickFn = proc (self: pointer) {.cdecl, gcsafe.}

  TraceFeature = ref object of Feature
    open: Hook
    tick: Hook

var traceFeature = TraceFeature(name: "trace", gates: true)
var ticks = 0

proc hookOpen(path: cstring, flags: cint): cint {.cdecl.} =
  # Risky by nature: hook anything the logging path itself calls and this recurses forever.
  guard "open":
    if path != nil: logD("open " & fromCString(path))
  let orig = origAs[OpenFn](traceFeature.open)
  if orig != nil: orig(path, flags) else: -1

proc hookTick(self: pointer) {.cdecl.} =
  # Only an example: hooking a game's tick costs frames.
  guard "tick":
    inc ticks
    if ticks mod 1000 == 0: logD("tick #" & $ticks) # a line per frame costs more than the hook
  let orig = origAs[TickFn](traceFeature.tick)
  if orig != nil: orig(self)

traceFeature.open = newNativeHook("libc.so", "open", asPointer(hookOpen))
# A made-up offset. A wrong one still resolves and patches whatever is at that address.
traceFeature.tick = newOffsetHook(game, 0x2f1b40, asPointer(hookTick))

method install(f: TraceFeature): bool =
  # Retried until both halves land.
  if not f.open.install():
    logD("libc open not hooked yet")
    return false
  result = f.tick.install()
  logD("tick hook installed: " & $result & " at " & hex(f.tick.target))

proc Java_com_example_MyModule_nativeInit(env, thiz: pointer) {.exportc, cdecl, dynlib.} =
  useBackend(nativeBackend(game))
  registerFeatures(@[Feature(traceFeature)])
  startRuntimePoll()
