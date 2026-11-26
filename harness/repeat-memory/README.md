# Repeat memory harness

This app compiles the production player-state and repeat-memory hooks with Spotify's player
and Now Playing platform mocked under their runtime class names. It checks commands and
acknowledgements without requiring a Spotify account.

```sh
bash harness/repeat-memory/build.sh
xcrun simctl install <UDID> harness/repeat-memory/build/RepeatMemory.app
xcrun simctl launch --terminate-running-process --console <UDID> com.vitrine.repeatmemoryqa seed
# After REPEAT 4/4 passed, relaunch from another terminal:
xcrun simctl launch --terminate-running-process --console <UDID> com.vitrine.repeatmemoryqa replay
# REPEAT 5/5 passed
```

`seed` starts with the preference absent, enables it, and saves an acknowledged Repeat One
choice. `replay` checks cold launch, next track, buffering, and restarting the same track
after a ready state that has no track. Results stay visible in the app.
