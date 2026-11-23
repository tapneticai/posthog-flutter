# Visory patches to posthog_flutter 5.58.4

Branch `visory/5.58.4-vis3122` of the tapneticai fork, cut from the upstream tag
`5.58.4`. Visory (tapneticai/visory) depends on it as a git dependency pinned to
a commit, with `path: posthog_flutter`. Every local change is a separate commit
on top of the tag:

```bash
git log --oneline 5.58.4..visory/5.58.4-vis3122
git diff 5.58.4..visory/5.58.4-vis3122 -- posthog_flutter
```

Visory's `PosthogController` checks `postHogFlutterVersion` and
`posthogFlutterLocalPatches` at compile time. A version bump or a switch back
to the hosted package fails its build until the replay surface gate (VIS-2665)
has been re-checked on an Impeller OpenGL ES Android device.

## 1. Path dependency (`pubspec.yaml`)

Removed `resolution: workspace`. Upstream builds the package as a member of its
pub workspace, and pub refuses a workspace member used as a path dependency
outside that workspace.

## 2. No rasterizing after a stop (VIS-3122)

Files: `lib/src/replay/screenshot/screenshot_capturer.dart`,
`lib/src/posthog_widget.dart`, `lib/src/local_patches.dart`.

**Problem.** On Impeller OpenGL ES, a snapshot rasterized after Android destroyed
the render surface crashes the raster thread (SIGSEGV in
`DoRasterizeToImage → MakeImpellerSnapshot`, flutter/flutter#192365). The app
stops replay recording synchronously when the surface goes away
(`ReplaySurfaceGate.kt`, VIS-2665). In 5.58.4, `captureScreenshot()` awaits the
native session state, then `endOfFrame`, and only then calls
`renderObject.toImage()`. It does not check the stop between `endOfFrame` and
`toImage()`, so a capture that started while the surface was alive could
rasterize after the surface was gone. In 5.24.2, `toImage()` ran synchronously
in the post-frame callback, so this window did not exist there.

**Change.**
- `cancel()` now also sets `_stopped`. Only the new `resume()` clears it.
  `_cancelled` alone cannot carry a stop, because every capture clears it when
  it starts. The occlusion placeholder, for example, starts after an awaited
  bridge handshake.
- `_halted` (`_cancelled || _stopped`) is checked right before every
  rasterizing call that follows an await:
  - `renderObject.toImage()`
  - `toByteData()` (already followed a check; now uses `_halted`)
  - each `decodeImageFromPixels()` for revealed platform views
  - the final `picture.toImage()`
  - the occlusion placeholder: a stopped capturer builds none at all, and
    checks before `_resolveCaptureTarget`, so it leaves the pending dedup state
    of a frame that is still being sent untouched
- `PostHogWidgetState._startRecording()` calls `resume()` before restarting the
  change detector.

**Check.** The repo keeps no unit tests for this patch, and the fork
ships without upstream's test suites. Verify it on a device with the VIS-3119
repro: Galaxy A505, replay on, power key right after three onboarding pages,
20 attempts, no crash.

**Drop it when** upstream re-checks cancellation before each rasterizing call
after an await, or when flutter/flutter#192365 is fixed in the Flutter version
in `.fvmrc`. Then go back to the hosted package in Visory's pubspec and remove the
`posthogFlutterLocalPatches` check in `PosthogController`.

## 3. Exact native Android SDK (`android/build.gradle`)

`com.posthog:posthog-android:[3.75.0,4.0.0)` → `strictly '3.77.1'` (strict, so
another module asking for a newer version fails resolution instead of
silently upgrading it). The range let every
build float to the newest 3.x, which changed native replay code without any
change in this repo. 3.77.1 is the newest 3.x and what the range resolved to
when 5.58.4 was adopted. Under a Flutter host (`sdkName == "posthog-flutter"`),
its replay integration takes no screenshots of its own. Its only capture path
is `captureSessionReplaySnapshot`, which the plugin calls for
`captureNativeScreens` only, and the app keeps that off.

**Drop it** together with the fork, or bump it deliberately and
re-check the gate on a device.
