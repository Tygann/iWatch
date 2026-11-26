# iWatch accounts

The dedicated [iWatch Supabase project](https://supabase.com/dashboard/project/twqthjimkyohvybjhmir) holds optional iWatch profiles. SwiftData and CloudKit continue to handle the personal library, and Trakt uses its own authorization.

## Activate Apple sign-in

1. Enable Sign in with Apple for the `com.tyler.iWatch` App ID in [Apple Developer](https://developer.apple.com/account/resources/identifiers/list). Refresh the provisioning profiles used to sign iWatch.
2. Enable Apple in [iWatch Auth providers](https://supabase.com/dashboard/project/twqthjimkyohvybjhmir/auth/providers) with `com.tyler.iWatch` as the client ID. Disable email and any other unused providers. The app uses the native ID-token flow. [Supabase setup instructions](https://supabase.com/docs/guides/auth/social-sign-in/auth-apple)
3. Create or select a Sign in with Apple signing key that covers the iWatch App ID. Set `APPLE_TEAM_ID`, `APPLE_KEY_ID`, and `APPLE_PRIVATE_KEY` in [iWatch Edge Function secrets](https://supabase.com/dashboard/project/twqthjimkyohvybjhmir/functions/secrets). Use the complete PKCS#8 PEM, including the header and footer, for `APPLE_PRIVATE_KEY`. The deletion function exchanges a fresh authorization code and revokes Apple access before deleting the Supabase user. [Apple token revocation guide](https://developer.apple.com/documentation/technotes/tn3194-handling-account-deletions-and-revoking-tokens-for-sign-in-with-apple)
4. Set `SUPABASE_URL` and `SUPABASE_PUBLISHABLE_KEY` in the local app configuration using `iWatch/Secrets.example.plist` as the template. For Xcode Cloud, add both variables to the workflow environment before starting the archive. The build phase copies them into the signed app bundle. The Guest experience remains available when the app has no account configuration.

## Verify before distributing

On a signed device, create a disposable iWatch account from Settings and save a display name. Sign out and back in, then sign in on a second device with the same Apple Account and check the display name. Delete the disposable account from iWatch. Verify that its profile is removed, the app returns to Guest, and the local watchlist and history remain available.
