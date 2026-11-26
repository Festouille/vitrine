# Hide podcasts

Run on a booted iOS 26 or later simulator on Apple silicon:

```sh
harness/hide-podcasts/test.sh <simulator-udid> [screenshot-directory]
```

The harness runs both production Logos hook files with the real launch-mode and
preference readers on mock Spotify cells. It checks the off and on states in
each look, zero-height sizing and removal from interaction/accessibility,
reusing each filtered cell for music, keeping an audiobook and ordinary music,
and hiding the Native Home podcast chip. It saves one screenshot of each case.
It does not test Spotify's server feeds or the Redesigned Home menu.
