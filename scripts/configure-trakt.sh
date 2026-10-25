#!/bin/sh
# Runs after Copy Bundle Resources. Never prints credential values.
set -eu

bundle="${TARGET_BUILD_DIR:?}/${UNLOCALIZED_RESOURCES_FOLDER_PATH:?}"
info="${TARGET_BUILD_DIR}/${INFOPLIST_PATH:?}"
secrets="$bundle/Secrets.plist"
plistbuddy=/usr/libexec/PlistBuddy

fail() { echo "error: Trakt configuration: $1" >&2; exit 1; }
read_key() {
    if [ -f "$1" ]; then
        "$plistbuddy" -c "Print :$2" "$1" 2>/dev/null || true
    fi
}
valid_value() {
    case "$1" in
        ''|*[![:space:]]*) ;;
        *) return 1 ;;
    esac
    case "$1" in
        ''|*replace-with-*|*YOUR_*|*your-*|*'$('*|*'${'*) return 1 ;;
    esac
}

# Environment variables are a private CI input. Write only into the build
# product, leaving the developer's local Secrets.plist untouched.
for key in TRAKT_CLIENT_ID TRAKT_CLIENT_SECRET TRAKT_REDIRECT_URI; do
    case "$key" in
        TRAKT_CLIENT_ID) value="${TRAKT_CLIENT_ID:-}" ;;
        TRAKT_CLIENT_SECRET) value="${TRAKT_CLIENT_SECRET:-}" ;;
        TRAKT_REDIRECT_URI) value="${TRAKT_REDIRECT_URI:-}" ;;
    esac
    if [ -n "$value" ]; then
        if [ ! -f "$secrets" ]; then
            /usr/bin/plutil -create xml "$secrets"
        fi
        /usr/bin/plutil -replace "$key" -string "$value" "$secrets"
        # AppConfig prefers Info.plist. Prevent a stale value from masking CI.
        /usr/bin/plutil -replace "$key" -string "$value" "$info"
    fi
done

# Debug remains usable without an optional Trakt integration.
if [ "${CONFIGURATION:-}" != Release ] && [ "${ACTION:-}" != install ]; then
    exit 0
fi

for key in TRAKT_CLIENT_ID TRAKT_CLIENT_SECRET TRAKT_REDIRECT_URI; do
    value="$(read_key "$info" "$key")"
    if ! valid_value "$value"; then
        # An invalid nonempty Info value would mask the bundled fallback.
        if [ -n "$value" ]; then
            fail "$key in Info.plist is blank, unresolved, or a placeholder."
        fi
        value="$(read_key "$secrets" "$key")"
    fi
    if [ "$key" = TRAKT_REDIRECT_URI ] && [ -z "$value" ]; then
        value="${PRODUCT_BUNDLE_IDENTIFIER:?}://oauth/callback"
    fi
    valid_value "$value" || fail "$key is missing or a placeholder. Supply private build environment variables or a local iWatch/Secrets.plist."
    if [ "$key" = TRAKT_REDIRECT_URI ]; then
        case "$value" in
            com.tyler.iWatch://oauth/callback|com.tyler.iwatch://oauth/callback) ;;
            *) fail "TRAKT_REDIRECT_URI must use a registered app callback: com.tyler.iWatch://oauth/callback. Match it exactly in the Trakt application settings." ;;
        esac
    fi
done
echo "Trakt release configuration validated."
