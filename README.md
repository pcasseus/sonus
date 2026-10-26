# sonus_next

Sonus is a personal music library and player for Android, with listening
charts, Moments and optional Google sign-in with cloud sync.

## Account settings

Sign-in and cloud sync need three client values, compiled into the app with
`--dart-define-from-file`:

| Key | Value |
|---|---|
| `SUPABASE_URL` | The Supabase project URL |
| `SUPABASE_PUBLISHABLE_KEY` | The project's **publishable** key (never a secret or service-role key) |
| `GOOGLE_WEB_CLIENT_ID` | The Google **Web** OAuth client ID, which Supabase's Google provider also uses |

Copy `config/sonus.dev.example.json` to `config/sonus.dev.json` (git-ignored)
and fill them in. Without them, Sonus works fully but sign-in is off.

## Running and building

- Develop: `tool/run-dev.ps1` (or the VS Code launch configuration).
- Release APK: `tool/build-release.ps1`. It refuses to build without the
  account settings, prints the APK's SHA-256, and never prints the values.
  Do not use a bare `flutter build apk --release`: that build has no sign-in.
- Do not run `flutter test` while a release build is running; it rewrites
  the generated plugin registrant and breaks the build.

## Google sign-in on Android

Android sign-in works only for an app whose package name
(`com.sonus.sonus_next`) and signing-key SHA-1 fingerprint are registered as
an **Android** OAuth client in the same Google Cloud project as the Web
client ID. Each signing key (debug, and later production) needs its own
registration.
