# Queue helpers

Run from the repository root on macOS with Xcode, a booted iOS 26+ simulator and Theos:

```sh
harness/queue-helpers/build.sh
app=com.vitrine.queuehelpers
xcrun simctl install booted harness/queue-helpers/build/QueueHelpers.app

# Native, switches on
xcrun simctl launch --terminate-running-process --console booted "$app" --on \
  -spotifyglass.queue.tapToQueue YES -spotifyglass.queue.reshuffle YES \
  -spotifyglass.queue.duration YES

# Redesigned, switches on
xcrun simctl launch --terminate-running-process --console booted "$app" --on \
  -spotifyglass.redesign YES -spotifyglass.queue.tapToQueue YES \
  -spotifyglass.queue.reshuffle YES -spotifyglass.redesign.queue.duration YES

# Default-off regression
xcrun simctl launch --terminate-running-process --console booted "$app"
```

Use the simulator UDID instead of `booted` if more than one is running. Each launch sends
UIKit taps to the song rows, a More button and (when enabled) Reshuffle. It prints
`15/15 passed` and leaves the final state on screen. To capture it, use
`xcrun simctl io booted screenshot ~/queue-helpers.png`.

The harness compiles the production hooks, duration formatter and reshuffle flag registration.
Spotify's row views, playback and queue backend are mocked, including the reshuffle action
behind the flag. It checks the two supported row shapes, unsupported rows and menu taps;
duration updates and incomplete metadata; and the flag on/off. It does not verify
Spotify's own runtime conditions for showing its Reshuffle button.
