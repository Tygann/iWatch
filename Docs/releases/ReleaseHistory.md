# Release history

This file records builds uploaded to App Store Connect. The source commit in the newest entry is the exclusive comparison boundary for the next build: review meaningful product changes after that commit, excluding release-history-only commits, and do not repeat previously published notes.

## Version 1.0 (Build 32)

- Upload date: 2026-10-26 (Xcode Cloud build in progress; upload not yet confirmed)
- Channel: TestFlight
- Source commit: `0fd51967fda4ba4f30093456e8142b3fcc042b92`
- Build number and in-progress status supplied by Tyler. Notes compare against the latest logged release, build 29; builds 30 and 31 have no recorded published boundary.

### What to Test

What's new:
- Fixed Trakt sync reporting an unconfirmed upload after marking movies or episodes watched.
- Improved confirmation of previously uploaded watched entries without sending them again.
- Updated the app icon and About artwork.

Please test:
- Mark one episode watched, then mark several episodes together, and confirm Trakt sync completes without an unconfirmed-upload warning.
- If watched changes were pending before this update, use Sync Now and confirm they clear without duplicate plays on Trakt.
- Mark a movie watched and confirm it appears once in both iWatch and Trakt history.
- Check the app icon and Settings > About artwork in light and dark appearance.

## Version 1.0 (Build 29)

- Uploaded: 2026-10-26
- Channel: TestFlight / App Store preparation (not submitted)
- Source commit: `6b8370a41bde543b637326f0123c7cb781ca3bcf`
- Uploaded through Xcode Cloud after enabling Associated Domains on the registered App ID. Build 28 failed distribution export and was not uploaded. Build 29 processed as Ready to Submit and replaced build 27 in the saved version 1.0 listing. What to Test was saved. No App Review submission was made.

### What to Test

What's new:
- Improved Trakt sign-in with a secure return to iWatch.
- Catalog information and artwork now expire and refresh while keeping your Watchlist and watched history intact.

Please test:
- Connect Trakt, cancel and retry sign-in, then disconnect and reconnect.
- Confirm your existing Watchlist and watched history remain intact after updating.
- Open previously viewed titles online and offline and check that details and artwork refresh when available.

## Version 1.0 (Build 27)

- Uploaded: 2026-10-25
- Channel: TestFlight / App Store preparation (not submitted)
- Source commit: `3e3e6cc0354228d815bb719275b9dfab67593c63`
- Selected for version 1.0 after Xcode Cloud archive/upload and TestFlight processing succeeded. This build adds Trakt attribution; it does not contain the subsequent local HTTPS/PKCE migration.

### What to Test

What's new:
- About now includes Trakt attribution alongside TMDB, privacy, and support information.

Please test:
- Open Settings > About and confirm both provider notices are readable in light and dark appearance.
- Increase text size and confirm all attribution and support links remain reachable.

## Version 1.0 (Build 26)

- Uploaded: 2026-10-25
- Channel: TestFlight / App Store preparation (not submitted)
- Source commit: `f31797924797e382f135dab7b153e587dc328dbc`
- Xcode Cloud archived and uploaded this commit automatically. Build 26 processed successfully and replaced build 25 in the version 1.0 listing. Mac validation subsequently passed 96 unit tests, Simulator builds, and five focused Settings/About UI checks.

### What to Test

What's new:
- About now includes TMDB attribution and direct links to the privacy policy and support.

Please test:
- Open Settings > About in light and dark appearance and confirm the logo and attribution are readable.
- Increase your device text size and confirm you can scroll to every About link.
- Open Privacy Policy and Support and confirm the correct pages load.

## Version 1 (Build 24)

- Uploaded: 2026-10-25
- Channel: TestFlight
- Source commit: `67fff5b417894cd36200a06abdc4847a262f08f3`

### What to Test

What's new:
- Library screens now refresh when changes arrive through iCloud, with upload and download status available in Settings > iCloud Sync.
- Improved Trakt sync reliability across devices and interrupted connections, including safer retries for watched history.
- Movie, show, and episode details refresh in the background while keeping cached information available.

Please test:
- Change your Watchlist or watched history on one device and confirm the changes appear on another device using the same iCloud account.
- With Trakt connected, add or remove watched entries, then use Sync Now and confirm your history matches without duplicate plays.
- Make library changes while offline, reconnect, and confirm pending changes sync correctly.
- Revisit movie, show, and episode details and check that cached information appears promptly and updates when needed.

## Version 1 (Build 19)

- Uploaded: 2026-10-24
- Channel: TestFlight
- Source commit: `b2f6f3605ac8792a5ad2df7c478d2cc8d032023f`

### What to Test

What's new:
- Fixed missing shows in Continue Watching after library imports, with next-episode progress filling in as your library loads.
- Refined the app icon in dark appearance.

Please test:
- After importing your Trakt library, open Shows and confirm in-progress shows appear in Continue Watching with the correct next episode.
- Mark an episode watched and confirm Continue Watching advances correctly, including after relaunching.
- With a large library, check that Shows remains responsive while episode progress loads.

## Version 1 (Build 10)

- Uploaded: 2026-08-19
- Channel: TestFlight
- Source commit: `74992746b51a82ae69ec0d55b9bee5937c55e2c7`

### What to Test

What's new:
- Get notified when movies and episodes in your library become available to watch.
- Sort movies and enjoy smoother season, episode, search, and action interactions.

Please test:
- Enable release notifications and confirm the settings are clear and behave as expected.
- Try each movie sorting option and confirm the selected order remains after relaunching.
- Continue a show episode and confirm its artwork, season selection, and watched actions behave as expected.

## Version 1 (Build 8)

- Uploaded: 2026-08-07
- Channel: TestFlight
- Source commit: `60182e2d017f9c6f88bcf802323c64540ef75e2c`

### What to Test

What's new:
- Discover trending movies and shows, browse streaming providers, and refine results with improved filters.
- Open cast and crew profiles to explore biographies, known-for titles, and complete filmographies.
- Use the redesigned Settings screen to choose a start page, manage sync and storage, share iWatch, or leave a rating.

Please test:
- Browse trending titles and a streaming provider, then switch between movie and show filters.
- Open cast or crew members from a movie, show, or episode and explore their profiles and filmographies.
- Change the app appearance and start page, then confirm those preferences persist after relaunching.
- Review Trakt and Storage & Data settings and confirm existing sync and maintenance controls remain easy to find.

## Version 1 (Build 7)

- Uploaded: 2026-08-06
- Channel: TestFlight
- Source commit: `f72c3383013249c1708727cc2cc7b93dbc7ef9ea`

### What to Test

Welcome to the first iWatch TestFlight build!

What's new:
- Build your personal movie and TV library with Watchlist, Continue Watching, and viewing history.
- Search and discover titles, then explore cast and crew, trailers, ratings, and where to watch.
- Keep your library available across devices with iCloud, with optional Trakt import and sync.

Please test:
- Search for a movie or show, add it to your Watchlist, and update its watched or watching status.
- Open movie, show, season, and episode details and check that artwork, information, and actions behave as expected.
- If you use multiple devices, confirm that library changes appear on each device through iCloud.
- If you use Trakt, connect your account and verify that importing and syncing preserve your Watchlist and watched history.
