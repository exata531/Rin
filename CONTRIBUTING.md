# Contributing

Three kinds of thing arrive here, and they take three different doors.

**A module.** The most useful thing you can send. Write it in your own repo,
then open a pull request adding one line to
[`modules/registry.json`](modules/registry.json). The whole path, from writing
one to what the automatic check does with it, is
[docs/modules.md](docs/modules.md); the pull request template walks the same
checklist.

**A fix or a feature for the app, the site, or the checker.** An ordinary pull
request. For anything bigger than an afternoon, open an issue first so nobody
spends a week building something that was never going to merge.

**A bug.** [Open an issue](https://github.com/exata531/Rin/issues/new/choose).
Say what happened, what you expected, and which versions of Rin and macOS you
are on. If a module is misbehaving, use the **Report a module** template
instead; it moves faster, because delisting is reversible and a folder full of
somebody's life is not.

## Building the app

```sh
# Requires Xcode command line tools and xcodegen
git clone https://github.com/exata531/Rin.git
cd Rin
xcodegen generate
xcodebuild -scheme Rin -configuration Release
```

There is nothing else to configure, and no secrets to obtain: a build from
your own machine is the same app as the release.

## Where things live

| Folder | What it holds |
| --- | --- |
| `Sources/` | the app, Swift |
| `Resources/` | the icon and the shell-drawn cards (about, shortcuts, tour, first run) |
| `skeleton/` | the blank brain, copied once into the user's chosen folder on first run |
| `modules/` | the module list, the registry, and a template the right shape |
| `scripts/` | the module checker and build steps |
| `site/` | the website, plain HTML, published by Pages |
| `docs/` | how things work: modules, first run, versioning |

## What will not merge

Anything that gives the app network traffic of its own, stores a credential,
adds an account, or reports anything to anyone. The
[Privacy section of the README](README.md#privacy) is a promise, and a pull
request that breaks it gets closed regardless of what it buys. The same goes
for taking colour into the tab bar's idle states (colour is spent on alerts
only) and for motion that ignores Reduce Motion.

## Changelog

User-visible changes get a line in [`CHANGELOG.md`](CHANGELOG.md) under
Unreleased, in words that say which thing changed. "Bug fixes and stability
improvements" tells a user nothing and does not go in.
