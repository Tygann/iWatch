# Development log

## 2026-07-31

- Established repository safety, agent workflow, and the local-first/account-scoped Trakt sync contract.
- Reorganized Settings around user-facing preferences and progressively disclosed Trakt, storage, diagnostic, and reset workflows; added durable Apple-platform design guidance.
- Added reset-generation protection, Trakt account-boundary cleanup, and CloudKit export confirmation so library resets and account changes remain safe across reinstalls and offline devices.
- Fixed current Trakt account identification, made large imports use indexed history merges and visible page/item progress, separated Trakt and CloudKit status, and made movie/show metadata enrichment progressive instead of blocking library screens.
