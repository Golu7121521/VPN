# MUSIFY

Flutter music app (Riverpod + GoRouter + just_audio). Uses mock data and public sample audio,
and is structured so a real backend can replace `lib/data/repositories.dart`.

Only `lib/`, `pubspec.yaml` and the workflow are stored here. The Android project is generated
by `.github/workflows/build.yml` on every run, which also builds the APK.

Push to `main` -> GitHub Actions -> download `musify-apk` from the run's Artifacts.
