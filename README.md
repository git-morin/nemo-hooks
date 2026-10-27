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

`dev` and `main` are the only branches. Every push to `dev` publishes a `vX.Y.Z-dev.N`
prerelease and prunes the one before it; merging to `main` cuts the stable `vX.Y.Z`.

The bump comes from the gitmoji on the commits since the last stable tag: `:boom:` major,
`:sparkles:`/`:globe_with_meridians:` minor, anything else patch. A push touching only docs or
CI does not burn a dev version, and `main` always publishes.

A stable tag's `.nimble` declares the same version, which is what a nimble or pnak `requires`
range resolves against. Prereleases are not range material - pin one by tag, or a commit:

```nim
requires "https://github.com/git-morin/nemo-hooks#<sha>"
```

## Dogfood

[vdextra](https://github.com/git-morin/com.gitmorin.vdextra), an Xposed module for Virtual
Desktop on Quest, is built on this and is where the Mono backend gets exercised.

## License

MIT
