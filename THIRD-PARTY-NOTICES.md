# Third-Party Notices

Licence texts are in `licenses/`. Acknowledgements are in `CREDITS.md`.

## libprojectM (LGPL-2.1)

<https://github.com/projectM-visualizer/projectm>, vendored as a git submodule at
`vendor/projectm` and built from source.

- Linked dynamically; the dylibs are embedded in the app bundle as separate,
  replaceable files.
- Licence text shipped verbatim: `licenses/libprojectM-LGPL-2.1.txt`.
- The library is not modified.

Statically included in the libprojectM dylib:

| Component | Licence |
|---|---|
| projectm-eval (projectM team) | MIT — `licenses/projectm-eval-MIT.txt` |
| hlslparser (Unknown Worlds Entertainment) | MIT — `licenses/hlslparser-MIT.txt` |
| GLM (G-Truc Creation) | MIT per upstream `copying.txt`; the vendored subset ships no licence file |
| SOIL2 (Martín Lucas Golini / Jonathan Dummer) | Public domain |

## AudioCap (BSD 2-Clause)

<https://github.com/insidegui/AudioCap>, © 2024 Guilherme Rambo. The process-tap and
aggregate-device setup is adapted from it. The copyright notice is retained in adapted
source files, and the licence is reproduced in `licenses/AudioCap-BSD-2-Clause.txt`
and in the app's credits. AudioCap's private-TCC-API path (`ENABLE_TCC_SPI`) is not
used.

## Presets

During development the app bundles a test preset from the libprojectM repository
(`presets/tests/211-wave.milk`), covered by the LGPL-2.1 notice above.

`.milk` presets are community works from the Winamp era, generally shared without
explicit licence terms. The app ships a small curated set, credits authors by name in
the UI, and supports a user preset folder as the primary way to add more. Takedown
requests from preset authors will be honoured.

## Reference-only projects

No code from these is included:

- frontend-sdl-cpp — **GPL-3.0; studied for API usage patterns only, code must not be
  copied from it.**
- ProjectMilkSyphon (Vidvox), Butterchurn (MIT), Webamp (MIT) — prior art.

When third-party code, assets, or presets are added, this file, `CREDITS.md`, and
`licenses/` are updated in the same change.
