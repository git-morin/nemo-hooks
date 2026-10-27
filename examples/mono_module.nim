## A Mono module example: mute a game by replacing the setter on its audio settings class.

include nemohooks/features

import nemohooks
import nemohooks/backends/mono

const audio = "MyGame.Audio.Settings, MyGame"

type
  SetBoolFn = proc (self: pointer, v: bool) {.cdecl, gcsafe.}

  MuteFeature = ref object of Feature
    setMuted: Hook

var muteFeature = MuteFeature(name: "mute", gates: true)

proc hookSetMuted(self: pointer, v: bool) {.cdecl.} =
  guard "set_Muted": # the log line allocates, and an exception out of a hook kills the process
    logD("set_Muted(" & $v & ") -> true")
  let orig = origAs[SetBoolFn](muteFeature.setMuted)
  if orig != nil: orig(self, true)

muteFeature.setMuted = newHook(audio, "set_Muted", 1, asPointer(hookSetMuted))

method install(f: MuteFeature): bool =
  let cls = getClass(audio)
  if cls == nil:
    logD("Settings not resolved yet") # retried from a runtime thread, so debug and not info
    return false
  result = f.setMuted.install(cls)
  logD("set_Muted hook installed: " & $result)

proc Java_com_example_MyModule_nativeInit(env, thiz: pointer) {.exportc, cdecl, dynlib.} =
  useBackend(monoBackend())
  registerFeatures(@[Feature(muteFeature)])
  startRuntimePoll()
