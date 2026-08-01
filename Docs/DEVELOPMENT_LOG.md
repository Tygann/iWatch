# Development log

## 2026-08-01

- Replaced SDWebImage with a native actor-isolated artwork pipeline using HTTP disk caching, in-flight request deduplication, bounded decoded-image memory, and off-main ImageIO downsampling sized for each SwiftUI surface.
- Made decoded-memory hits synchronous so tab recreation does not flash placeholders, and separated poster, episode-still, backdrop, and profile URL sizing to match each TMDb artwork category.
- Reduced library navigation churn with predicate-backed SwiftData reads, revision-keyed movie/show presentation snapshots, precomputed Shows sections, batched enrichment refreshes, and snapshot reuse when opening Continue Watching.
- Added focused artwork and presentation-snapshot tests; verified all `iWatchTests`, Debug simulator navigation through Shows and Continue Watching, and a Release simulator build.

## 2026-07-31

- Established repository safety, agent workflow, and the local-first/account-scoped Trakt sync contract.
- Reorganized Settings around user-facing preferences and progressively disclosed Trakt, storage, diagnostic, and reset workflows; added durable Apple-platform design guidance.
- Added reset-generation protection, Trakt account-boundary cleanup, and CloudKit export confirmation so library resets and account changes remain safe across reinstalls and offline devices.
- Fixed current Trakt account identification, made large imports use indexed history merges and visible page/item progress, separated Trakt and CloudKit status, and made movie/show metadata enrichment progressive instead of blocking library screens.
- Separated durable iWatch Following from Trakt's temporary Watchlist semantics, restored active history-only shows from Trakt progress, and clarified the Movies "To Watch" filter and sync diagnostics terminology.
