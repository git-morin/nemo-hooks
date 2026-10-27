## An IL2CPP module example: read a field off the player every time it takes damage.

include nemohooks/features

import std/strutils
import nemohooks
import nemohooks/backends/il2cpp

const player = "MyGame.Player, Assembly-CSharp"

type
  TakeDamageFn = proc (self: pointer, amount: float32) {.cdecl, gcsafe.}

  DamageFeature = ref object of Feature
    takeDamage: Hook
    healthOffset: int

var damageFeature = DamageFeature(name: "damage", gates: true, healthOffset: -1)

proc hookTakeDamage(self: pointer, amount: float32) {.cdecl.} =
  guard "TakeDamage": # the log line allocates, and an exception out of a hook kills the process
    let hp = readF32At(self, damageFeature.healthOffset) # no managed call per hit
    logD("took " & $amount & " at " & $hp & " hp")
  let orig = origAs[TakeDamageFn](damageFeature.takeDamage)
  if orig != nil: orig(self, amount)

damageFeature.takeDamage = newHook(player, "TakeDamage", 1, asPointer(hookTakeDamage))

method install(f: DamageFeature): bool =
  let cls = getClass(player)
  if cls == nil:
    logD("Player not resolved yet") # a missing class means the wrong assembly name
    return false
  f.healthOffset = fieldOffset(cls, "health")
  if f.healthOffset < 0:
    logD("no health field: " & fieldNames(cls).join(", ")) # the layout moved
    return false
  result = f.takeDamage.install(cls)
  logD("TakeDamage hook installed: " & $result & ", health at +" & $f.healthOffset)

proc Java_com_example_MyModule_nativeInit(env, thiz: pointer) {.exportc, cdecl, dynlib.} =
  useBackend(il2cppBackend())
  registerFeatures(@[Feature(damageFeature)])
  startRuntimePoll()
