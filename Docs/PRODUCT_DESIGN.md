# Product design

iWatch should feel at home on the current version of iOS. User-facing work follows Apple’s current Human Interface Guidelines, established iOS behavior, and modern SwiftUI conventions.

## Principles

- Start with the person’s task. Make primary content and actions obvious, and reveal secondary or technical detail progressively.
- Prefer system components, materials, symbols, navigation, controls, and feedback. Use custom UI when it adds clear product value without weakening familiar behavior.
- Write direct, human-facing copy. Avoid exposing storage, networking, queue, or provider implementation terminology outside diagnostic screens.
- Preserve user control. Communicate the scope and outcome of actions, distinguish reversible from irreversible changes, and confirm uncommon destructive actions.
- Treat accessibility as part of the design. Support Dynamic Type, VoiceOver, sufficient contrast, comfortable touch targets, Reduce Motion, and system appearance settings.
- Keep loading, empty, offline, error, and success states useful and nonintrusive. Reserve alerts for critical or immediately actionable interruptions.

## SwiftUI implementation

- Use native controls and the narrowest appropriate state ownership.
- Keep views focused and compose larger screens from feature-local subviews.
- Use semantic styles such as `primary`, `secondary`, and system colors instead of hard-coded appearance values.
- Prefer navigation for substantial secondary tasks and sheets for focused modal work.
- Include deterministic previews for primary and important secondary states when practical.

## Review checklist

- Compare the result with the current Apple Human Interface Guidelines for the affected pattern.
- Verify standard and accessibility Dynamic Type sizes on Simulator.
- Check VoiceOver labels, values, traits, reading order, and action names.
- Check light and dark appearance, loading and error states, and destructive-action confirmation.
- Confirm user-facing copy describes outcomes rather than implementation details.
