/// The local patches this vendored copy carries, listed in PATCHES.md. The host
/// app checks it at compile time, so swapping in an unpatched posthog_flutter
/// fails the build instead of silently dropping a crash fix.
const posthogFlutterLocalPatches = 'VIS-3122';
