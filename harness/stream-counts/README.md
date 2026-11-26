# Stream counts

Build on an Apple silicon Mac with Xcode and Theos, then run on a booted iOS 26 or later simulator:

```sh
./build.sh
mkdir -p ~/evidence
./check.sh <simulator-UDID> ~/evidence
```

The harness compiles the actual Native and Redesigned row hooks, identity lookup, response parser and per-track cache. Its album rows expose the track menu ID; its playlist rows have a Swift fixture with the model's `props.item.url` shape. A stub Spotify data loader verifies the request shape and supplies string, numeric, and missing play counts without contacting Spotify. The four launch scenarios assert that counts appear only with the switch on, a missing count leaves the artist alone, reused rows of the same size restore cached counts, and two rows for the same URI make only one request.
