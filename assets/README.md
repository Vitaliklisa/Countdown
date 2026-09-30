# Assets

This folder is intentionally near-empty: Data Dawn draws everything it needs
from code — the clock wordmark, the countdown tiles, the confetti and the Google
glyph are all `CustomPainter`s and Material icons, so there are no raster
assets to ship and nothing to keep in sync across screen densities.

Generated app icons and splash screens belong here too, but they are produced
by `flutter_launcher_icons` / `flutter_native_splash` and written straight into
`android/` and `ios/`, so they do not live in this folder.

If you do add an image later, drop it here and list it under `assets:` in
`pubspec.yaml` (the folder itself is already declared).