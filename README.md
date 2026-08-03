# fishtank

Ambient [MilkDrop](https://www.geisswerks.com/milkdrop/) visualizer for macOS. A small
always-on-top window renders classic Winamp-era visuals that react to whatever audio
the machine is playing, captured with Core Audio process taps — no virtual audio
device or routing setup required.

Rendering is done by [libprojectM](https://github.com/projectM-visualizer/projectm).
Requires macOS 14.4+.

## Status

Early development, not yet usable.

- [x] libprojectM built from source and linked
- [x] App skeleton (menu bar only, no Dock icon)
- [ ] Rendering
- [ ] System audio capture
- [ ] Floating window behaviour
- [ ] Bundled presets
- [ ] Signed release

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
