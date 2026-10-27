# nemohooks

Write Xposed-style hooks in Nim.

It compiles under both Nim 2 and [Nimony](https://github.com/nim-lang/nimony).

## Targets

A **backend** is the one runtime-specific part of a module. Three ship with the library:

| Backend | For |
| --- | --- |
| `nemohooks/backends/mono` | Mono runtimes — Unity's older scripting backend, Xenko, anything hosting `libmonosgen` |
| `nemohooks/backends/il2cpp` | Unity's IL2CPP, which is most Unity games since 2018 |
| `nemohooks/backends/native` | Plain functions in any mapped `.so`, with no managed runtime involved |

[`examples/`](examples) has one compiling module per backend, and they are tested in CI.

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
Desktop on Quest, is built on this and is where the Mono backend gets exercised.

## License

MIT
