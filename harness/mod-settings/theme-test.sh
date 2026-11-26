#!/bin/sh
set -eu

device=${1:?pass a booted simulator UDID}
out=${2:?pass a directory for screenshots and logs}
app=com.vitrine.modsettingsharness
bundle="$(dirname "$0")/build/ModSettingsHarness.app"
mkdir -p "$out"

sim() {
    command="$1"
    shift
    xcrun simctl "$command" "$device" "$@"
}
run() {
    log="$1"
    shift
    xcrun simctl launch --terminate-running-process --console "$device" "$app" "$@" > "$log" 2>&1 &
}
expect() {
    pattern="$1"
    for attempt in $(seq 1 100); do
        if grep -Fq "$pattern" "$log"; then return; fi
        if grep -Eq 'Assertion failure|uncaught exception' "$log"; then break; fi
        sleep 0.15
    done
    printf 'Missing assertion: %s\n' "$pattern" >&2
    cat "$log" >&2
    exit 1
}
cleanup() {
    sim terminate "$app" >/dev/null 2>&1 || true
    sim ui appearance "$initial" >/dev/null 2>&1 || true
}

initial=$(sim ui appearance)
trap cleanup EXIT
sim install "$bundle"

for look in legacy redesigned; do
    sim ui appearance light
    set --
    if [ "$look" = redesigned ]; then set -- redesign; fi
    run "$out/$look-live.log" "$@" theme=dark pick=Appearance theme-off \
        toggle=0.0 theme=light pause pause theme=dark pause pause \
        theme-menu=Light theme=light back theme=light pick=Player theme=dark
    expect 'experiment is off'
    expect 'theme passed: Appearance light'
    sim io screenshot "$out/$look-appearance-light.png"
    sim ui appearance dark
    expect 'theme passed: Appearance dark'
    sim io screenshot "$out/$look-appearance-dark.png"
    expect 'theme passed: Vitrine light'
    expect 'theme passed: Player dark'

    run "$out/$look-relaunch.log" keep theme=light pick=Appearance theme=light \
        theme-menu=Dark theme=dark theme-menu=System toggle=0.0 theme-off theme=dark back theme=dark
    expect 'theme passed: Appearance light'
    expect 'experiment is off'
    expect 'theme passed: Vitrine dark'
done

sim ui appearance light
run "$out/restart-contrast.log" -spotifyglass.accent 0 -spotifyglass.redesign.accent 0 \
    restart-pending restart-contrast=dark pick=Appearance toggle=0.0 back restart-contrast=light restart-pending
expect 'restart contrast passed: light'

echo 'Appearance themes passed in both looks'
