# Entry points; the real work is in scripts/. Pass IPA through the environment so it stays one path.
export VITRINE_IPA := $(value IPA)

define with-ipa
	ipa="$$VITRINE_IPA"; \
	if [ -z "$$ipa" ]; then \
		for candidate in ipa/*.ipa; do \
			if [ -f "$$candidate" ]; then ipa="$$candidate"; break; fi; \
		done; \
	fi; \
	if [ -z "$$ipa" ]; then \
		echo 'no IPA: put a file in ipa/ or pass IPA=path/to/file.ipa' >&2; exit 1; \
	fi; \
	case "$$ipa" in -*) ipa="./$$ipa";; esac; \
	$(1) "$$ipa" $(2)
endef

# What goes on the phone is the mod alone. FLEX is the inspector `make trees` reads the screens
# through, so it rides along only when it is asked for: make install FLEX=1. (A make target cannot
# take --flex; make would read that as an option of its own.)
FLEX ?= 0
FLEX_ARG := $(if $(filter 0,$(FLEX)),--no-flex,)

# A local install is renamed and re-iconed so it is told apart from the released app on the home
# screen.
DEV_NAME ?= spoti.dev
DEV_ICON ?= docs/icon.png

.PHONY: build release install quick trees session log flags
build:    ## FLEX + glass IPA into out/
	$(call with-ipa,./scripts/pipeline.sh)
release:  ## glass only, no FLEX
	$(call with-ipa,./scripts/pipeline.sh,--no-flex)
install:  ## build, sign with your certificate, push to the phone on USB (FLEX=1 to take FLEX too)
	$(call with-ipa,./scripts/pipeline.sh,--install $(FLEX_ARG) --name "$(DEV_NAME)" --icon "$(DEV_ICON)" -o out/spoti.dev.ipa)
quick:    ## a tweak-only change into the app the last build made: rebuild, sign, install in seconds
	./scripts/quick.sh
trees:    ## record per-screen view trees into trees/ (needs a FLEX build on the phone)
	./scripts/record-trees.py
session:  ## record clean trees screen by screen into trees/clean/, Enter per snapshot, n for the next screen (SCREENS="playlist artist" for some)
	./scripts/record-session.py $(SCREENS)
log:     ## stream the tweak's log lines from the phone
	./scripts/dump-log.sh
flags:    ## regenerate tweak/Sources/Shared/Flags/SGFlagList.m, Spotify's remote-config flags, from the IPA
	$(call with-ipa,./scripts/extract-flags.py)
