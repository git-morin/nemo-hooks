# nemohooks

Write Xposed-style hooks for Mono runtimes in Nim.

An Xposed (or Zygisk) module gets a shared object loaded into the target process. If the target
is a Mono app — Unity, Xenko, anything hosting `libmonosgen` — the interesting surface is
managed code, and reaching it means finding the runtime that is already mapped, resolving its
entry points, and redirecting managed methods through trampolines. This library is that
plumbing, so a module can be just its hooks.

It compiles under both Nim 2 and [Nimony](https://github.com/nim-lang/nimony).

## What it gives you

| Module | |
| --- | --- |
| `nemohooks/runtime` | Finds the live runtime, resolves it, drives your features |
| `nemohooks/hook` | `Hook` and `Feature`: one redirected method, and a group installed together |
| `nemohooks/mono` | Classes, methods, fields, strings, GC handles, boxed values |
| `nemohooks/elfsyms` | Symbol lookup in a mapped image, without `dlopen` |
| `nemohooks/log` | `logI` / `logE` to logcat, and `hex` for addresses |
| `nemohooks/compat` | The places Nim 2 and Nimony disagree |

`import nemohooks` re-exports all of them.

## Writing a module

A feature is a group of hooks that install together. Subclass `Feature`, build the `Hook`s with
the method's class, name and parameter count, and override `install`:

```nim
import nemohooks

type
  SetBoolFn = proc(self: pointer, v: bool) {.cdecl, gcsafe.}

  MuteFeature = ref object of Feature
    setMuted: Hook

const AUDIO = "MyGame.Audio.Settings, MyGame"

var muteFeature = MuteFeature(name: "mute")

proc hookSetMuted(self: pointer, v: bool) {.cdecl.} =
  let orig = origAs[SetBoolFn](muteFeature.setMuted)
  if orig != nil: orig(self, true)

muteFeature.setMuted = newHook(AUDIO, "set_Muted", 1, asPointer(hookSetMuted))

method install(f: MuteFeature): bool =
  let cls = getClass(AUDIO)
  if cls == nil: return false
  f.setMuted.install(cls)
```

Then register it and start the poll from your JNI entry point:

```nim
registerFeatures(@[Feature(muteFeature)])

proc Java_com_example_MyModule_nativeInit(env, thiz: pointer)
    {.exportc, cdecl, dynlib.} =
  startRuntimePoll()
```

`startRuntimePoll` returns immediately. Injection happens long before the target's runtime
exists, so the poll waits for an initialised `libmonosgen` to appear in `/proc/self/maps`,
resolves it, and installs hooks on five Mono entry points. Those get `doSetup` called on a
thread the runtime owns, which is the only place a managed class can be resolved — so your
`install` runs as soon as the domain is up, and retries until it succeeds.

### Writing a replacement

A replacement runs on a thread the target's runtime owns. An exception escaping it unwinds
through managed frames and takes the process down, so wrap anything that can raise in `guard`
and keep the call through to the original outside it:

```nim
proc hookSetText(tb: pointer, s: MonoString) {.cdecl.} =
  var value = s
  guard "set_Text":
    let t = translate(s)
    if t != nil: value = t
  let orig = origAs[SetTextFn](textFeature.setText)
  if orig != nil: orig(tb, value)
```

Use `asPointer` and `asProc` rather than `cast` to move between addresses and proc types:
Nimony refuses the direct cast, and these compile under both.

### Feature flags

| | |
| --- | --- |
| `once` | Give up after the first attempt instead of retrying |
| `blocking` | Stop the rest of the registry when this one fails |
| `gates` | Setup counts as complete only once this one is done |

Registration order is installation order, which matters when one feature resolves classes or
fields a later one reads.

## Requirements

- **Dobby** linked into your module; `hook` imports `DobbyHook` from `dobby.h`.
- **Android**, arm64. `log` writes to logcat and `elfsyms` reads `/proc/self/maps`.
- A target whose Mono runtime is mapped under `libmonosgen-2.0.so`, or
  `setMonoSoname` before `startRuntimePoll`.

Set the logcat tag with `-d:nemohooksLogTag=YourTag`; it defaults to `nemohooks`.

## Releases

Tags are plain `vX.Y.Z` on `main`, which is what a nimble or pnak `requires` range resolves
against, and the tagged commit's `.nimble` always declares the same version. The bump is
derived from the gitmoji on the commits since the last tag: `:boom:` major,
`:sparkles:`/`:globe_with_meridians:` minor, anything else patch. A push that touches only docs
or CI does not cut a release.

To pin unreleased work, point at a commit instead:

```nim
requires "https://github.com/git-morin/nemo-hooks#<sha>"
```

## Dogfood

[vdextra](https://github.com/git-morin/com.gitmorin.vdextra), an Xposed module for Virtual
Desktop on Quest, is built on this and is where the API gets exercised.

## License

MIT
