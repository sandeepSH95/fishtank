# fishtank

A fish tank for your desk, except it plays [MilkDrop](https://www.geisswerks.com/milkdrop/)
visuals. A small always-on-top window of classic Winamp-era graphics that reacts to
whatever audio your Mac is playing — Spotify, YouTube, anything — captured with Core
Audio process taps, no virtual audio device or routing setup required.

It's meant to sit on your desktop like a piece of furniture: drag it into a corner,
let it run, forget about it. It sleeps when the music stops.

Rendering is done by [libprojectM](https://github.com/projectM-visualizer/projectm).
Requires macOS 14.4+.

## Building

Requires Xcode, CMake, and [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```sh
git clone --recurse-submodules <repo>
./scripts/build-libprojectm.sh
xcodegen generate
xcodebuild -project Fishtank.xcodeproj -scheme Fishtank build
```

## Credits and licensing

See [CREDITS.md](CREDITS.md) and [THIRD-PARTY-NOTICES.md](THIRD-PARTY-NOTICES.md).
libprojectM is LGPL-2.1 and linked dynamically; licence texts are in
[licenses/](licenses/).
