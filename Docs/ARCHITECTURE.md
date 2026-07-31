# iWatch architecture

`AppContainer` wires the application. `LibraryRepository` owns local library mutations and cached TMDb metadata. SwiftData is the local source of truth and CloudKit replicates that data between a person's devices. `SyncEngine` synchronizes the optional Trakt account using an account-scoped durable outbox.

Source ownership is organized by purpose: `App/` for composition, `Domain/` for app contracts and value types, `Data/` for persistence, provider clients, and repositories, `Platform/` for OS-facing services, `Features/` for screen-specific SwiftUI, `UI/` for reusable components, and `Support/` for shared helpers.

Views read local state and request repository actions; they must not call provider clients directly. TMDb is metadata only. Trakt is optional and never required for local tracking.
