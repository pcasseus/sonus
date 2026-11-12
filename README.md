# Sonus

**Your music. Your library. Your story.**

Sonus is a personal, local-first music player for Android, built with Flutter.

It brings together local music playback, a customizable music library, personal listening charts and listening-history insights in one experience.

Sonus does not treat your music as a collection of files. It turns it into a personal music experience built around the artists, albums and songs you actually listen to.

## Features

### Your music library

- Import music from folders on your device.
- Browse your artists in the Artist Roster.
- Explore artist and album profiles with artwork and release editions (for example, standard and deluxe).
- Manage metadata, blacklist songs and look after songs that are no longer available.

### Music playback

- Play your local music with queue management and shuffle.
- Use the mini-player and the full-screen player.
- Control playback from Android's media notification and lock screen.
- Build and play your own playlists.

### Sonus Hot 100

- Personal music charts built from your own listening, for songs and for albums and EPs.
- Weekly and all-time standings, chart movement, peaks and chart history.

### Sonus Moments

- Follow your chart history as music-news-style stories: debuts, new peaks, number ones, milestones, comebacks and chart exits.
- Open any story for the full account, with its chart journey and related releases.

### Listening insights

- See your listening at a glance on Home.
- Explore detailed statistics in Insights and in each song's stats: top artists and songs, listening time and how your favourites change over time.

### Personalization

- Choose from nine visual themes, with artwork-led screens.
- Accessibility options include larger text, high contrast, reduced motion and lower visual effects.

### Optional account and cloud sync

- Sonus works fully offline, with your music staying on your device.
- You can sign in with Google to back your library up to the cloud and sync it.

## Built with

Flutter · Dart · SQLite · Android

## Getting started

```
flutter pub get
flutter run --flavor prod
```

The app has two Android flavors: `prod` is Sonus itself (`com.sonus.sonus_next`), and `qa` is a separate "Sonus QA" install (`com.sonus.sonus_next.qa`) with its own data and no cloud, for testing on a phone beside the real app. Release builds use `tool/build-release.ps1`; QA builds use `tool/build-qa.ps1`.

Every build gets a new versionCode: the whole minutes since 2026-01-01 UTC. Both build scripts reserve it in a build ledger shared by all worktrees on the PC (`%LOCALAPPDATA%\Sonus\build-ledger.csv`, or `-Ledger`), which refuses a code that is not above every earlier one. They also refuse an APK whose package, artwork provider or signing certificate is not the expected one. `tool/build-release.ps1 -Mode debug` builds the debuggable app that phone backups need.


Sonus runs fully without an account. Sign-in and cloud sync are turned off unless the build is given its own account configuration. An example file for that configuration is in `config/`.

## Project status

Sonus is an actively developed personal Android music application. It continues to evolve, with improvements to playback, music library management, listening insights and personalized music experiences.
