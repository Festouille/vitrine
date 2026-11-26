# Default playlist simulator harness

Build with `./build.sh`, then install `build/DefaultPlaylistHarness.app` on a booted iOS simulator. Launch arguments select the scenario:

| Arguments | Expected result |
| --- | --- |
| `settings` | The Player settings switch defaults off and the picker row is hidden. |
| `toggle` | Turning the real switch on stores the setting but waits for a restart. |
| `-spotifyglass.defaultPlaylist YES enabled settings` | The switch is on and the picker row is visible. |
| `-spotifyglass.defaultPlaylist YES enabled picker` | The real settings row opens the picker fixture; Road Trip is selected. |
| `-spotifyglass.defaultPlaylist YES enabled` | The real settings row opens the picker fixture, then a fixture + saves only to Road Trip. |
| `-spotifyglass.redesign YES -spotifyglass.defaultPlaylist YES enabled` | The same scenario in the Redesigned look. |
| No arguments | The fixture + keeps saving to Liked Songs. |

Run each using `xcrun simctl launch --terminate-running-process --console <UDID> com.vitrine.defaultplaylistharness <arguments>`.
Take a screenshot with `xcrun simctl io <UDID> screenshot <path>`.

The harness runs Vitrine's real settings section and launch-time flag registration. Spotify's picker and save are fixtures; this does not make a Spotify account or playlist write.
