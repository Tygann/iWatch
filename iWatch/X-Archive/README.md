# iWatch Starter (SwiftUI + SwiftData + CloudKit + TMDB)

This is a starter source tree for an iOS app named **iWatch**.
Use it by creating a new Xcode iOS App project called `iWatch` (SwiftUI + SwiftData),
then drop these files into the project and enable iCloud/CloudKit.

## Steps

1) In Xcode 26: File → New → Project → iOS App
   - **Product Name**: iWatch
   - **Interface**: SwiftUI
   - **Storage**: SwiftData (checked)

2) Signing & Capabilities → add **iCloud**:
   - Services: **CloudKit**
   - (Use the default container)

3) Add `Config/Secrets.example.plist` to the app target as `Secrets.plist` and insert your TMDB API key.

4) Replace the auto-generated App files with the ones in `iWatch/App`, then add the rest of the folders.

5) Build & Run. The Discover tab loads TMDB trending (Movies + TV). Tap a poster to add it to Watchlist.

## Notes
- Local-first persistence uses SwiftData and syncs via CloudKit automatically for the user’s Apple ID.
- Trakt integration is stubbed (see `Features/Auth/TraktAuthManager.swift`). You can add OAuth when ready.
