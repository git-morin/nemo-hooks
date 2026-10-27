## Raw interop; see nemohooks.nim for why these two features are on.
when defined(nimony):
  {.feature: "lenientnils".}
  {.feature: "assumeSync".}

import std/strutils
import compat

const
  ## Typed: Nimony will not implicitly narrow an untyped integer literal to the cint the
  ## logging entry point declares.
  ANDROID_LOG_INFO*: cint = 4
  ANDROID_LOG_ERROR*: cint = 6

  ## A const rather than a settable global, so logging stays usable from the `gcsafe` callbacks
  ## Dobby and the ready probe run on.
  logTag* {.strdefine: "nemohooksLogTag".} = "nemohooks"

proc androidLogWrite(prio: cint, tag: cstring, text: cstring): cint
  {.importc: "__android_log_write", header: "<android/log.h>", discardable, gcsafe.}

## Both strings are copied into mutable locals that outlive the call: a Nimony string carries no
## terminating zero and has to be asked for one, so there is no shareable `const cstring` here.
proc emit(prio: cint, msg: string) =
  var tag = logTag
  var m = msg
  androidLogWrite(prio, tag.toCString, m.toCString)

proc logI*(msg: string) = emit(ANDROID_LOG_INFO, msg)

proc logE*(msg: string) = emit(ANDROID_LOG_ERROR, msg)

proc hex*(p: pointer): string =
  ## Addresses are what most of these logs carry, and `toHex` alone pads to 16 digits.
  let v = cast[uint64](p)
  if v == 0: "0x0"
  else: "0x" & toLowerAscii(toHex(cast[int64](v), 16)).strip(
    trailing = false, chars = {'0'})
