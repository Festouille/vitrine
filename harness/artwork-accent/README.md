# Album art accent

Run `harness/artwork-accent/check.sh` on a Mac with Theos and a booted iOS 26+
simulator (or pass its UDID). The harness uses the real accent, player state and
Home gradient hooks with a stand-in player and Home view tree. It asserts that
the accent swaps on an existing button and on new colors, and checks the
gradient stops through red, blue, grayscale, no track and late artwork. It
runs on and off in each look and saves the final states in `build/`.

This doesn't install Spotify or check its private selectors against a new IPA.
