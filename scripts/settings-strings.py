#!/usr/bin/env python3
"""List statically visible Mod Settings strings and audit the embedded tables.

Dynamic values, custom UIKit controls and strings passed via variables are not
fully discoverable. Use SGL on custom UI literals so they are included here.
"""
import argparse
import json
import re
from pathlib import Path


SOURCES = Path(__file__).resolve().parents[1] / "tweak/Sources"
QUOTED = r'"(?:\\.|[^"\\])*"'
LITERAL = rf'@{QUOTED}'
LITERALS = re.compile(rf'{LITERAL}(?:\s*@?{QUOTED})*')
TOKENS = re.compile(rf'@?{QUOTED}|//[^\n]*|/\*[\s\S]*?\*/|[^\s]')
CALL = re.compile(
    r'\b(SGL|SGOfferRestart|SGPickColor|SGNote|SGFillCell|SGSection(?:Header|Footer)?|SGNotedSection|'
    r'SG(?:Action|Warning|Page|Stat|StatAction|Switch|Option|Unstable|Flag|Kill|Hide|Shown|Choice|Slider|Segment|Menu|Link)Row|'
    r'pageRow|presetRow|lookSlider|SGSourcesPageMake|SGRLyricsSettingsPage)\s*\('
)
PROPERTIES = re.compile(
    r'\b(?:SGRestartNote|SGRedesignedUIInfo|SGFakePremiumWarning|title|placeholder|info|choiceFooter|'
    r'accessibilityLabel|format)\s*=\s*(' + LITERALS.pattern + ')'
    r'|\b(?:initWithTitle|intro|footer|alertControllerWithTitle|actionWithTitle|message):\s*('
    + LITERALS.pattern + ')'
)
UNCHANGED = {
    "Apple Intelligence", "Apple Music", "AutoMix", "DJ", "Español", "Français",
    "OK", "Premium", "SongDNA", "SponsorBlock", "Spotify", "Türkçe", "Vitrine",
}
FORMATS = re.compile(r'%(?:\d+\$)?[-+#0]*(?:\d+|\*)?(?:\.(?:\d+|\*))?(?:ll|l|z)?[@difuXsx%]')


def literal(match):
    return "".join(json.loads(part) for part in re.findall(QUOTED, match))


def arguments(source, start):
    levels, parts, begin = [")"], [], start
    closer = {"(": ")", "[": "]", "{": "}"}
    for token in TOKENS.finditer(source, start):
        value = token.group()
        if value in closer:
            levels.append(closer[value])
        elif value == levels[-1]:
            levels.pop()
            if not levels:
                return parts + [source[begin:token.start()].strip()]
        elif value == "," and len(levels) == 1:
            parts.append(source[begin:token.start()].strip())
            begin = token.end()
    return []


def call_literals(name, args):
    if name in {"SGL", "SGOfferRestart", "SGNote"}:
        return LITERALS.findall(args[0])
    if name == "SGSectionHeader":
        return LITERALS.findall(args[1])
    if name in {"SGFillCell", "SGSectionFooter"}:
        positions = (1, 2) if name == "SGFillCell" else (1,)
    elif name == "SGNotedSection":
        positions = (0, 2)
    elif name in {"SGFlagRow", "SGKillRow", "SGPageRow", "SGStatRow", "SGSection", "pageRow", "SGPickColor", "SGNote"}:
        positions = (0,)
    elif name == "SGUnstableRow":
        positions = (0, 1, 3)
    else:
        positions = (0, 1)
    strings = [args[i] for i in positions if i < len(args) and LITERALS.fullmatch(args[i])]
    if name in {"SGChoiceRow", "SGSegmentRow", "SGMenuRow"}:
        index = 3 if name == "SGChoiceRow" else 2 if name == "SGSegmentRow" else 1
        if index < len(args) and args[index].startswith("@["):
            strings.extend(LITERALS.findall(args[index]))
    return strings


def extract(path):
    source = path.read_text()
    source = "".join(
        " " if token.group().startswith(("//", "/*")) else token.group()
        for token in re.finditer(rf'@?{QUOTED}|//[^\n]*|/\*[\s\S]*?\*/|.', source, re.DOTALL)
    )
    candidates = [next(filter(None, pair)) for pair in PROPERTIES.findall(source)]
    for match in CALL.finditer(source):
        args = arguments(source, match.end())
        if args:
            candidates.extend(call_literals(match[1], args))
    return {text for candidate in candidates if (text := literal(candidate)).strip() and text not in UNCHANGED}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--list", action="store_true", help="list extracted English strings as JSON")
    parser.add_argument("--missing", action="store_true", help="list missing strings by language")
    args = parser.parse_args()
    strings = set()
    for path in SOURCES.rglob("*"):
        if path.suffix in {".m", ".x"} and not path.name.startswith("SGStrings_"):
            strings.update(extract(path))
    if args.list:
        print(json.dumps(sorted(strings), ensure_ascii=False, indent=2))

    invalid = False
    for language in ("fr", "es", "tr"):
        path = SOURCES / f"Settings/SGStrings_{language}.m"
        entries = re.findall(rf'({LITERAL})\s*:\s*({LITERAL})', path.read_text())
        translations = {}
        for key, value in entries:
            english, translated = literal(key), literal(value)
            if english in translations or not translated or FORMATS.findall(english) != FORMATS.findall(translated):
                print(f"{language}: invalid or duplicate translation: {english!r}")
                invalid = True
            translations[english] = translated
        missing = strings - translations.keys()
        print(f"{language}: {len(strings) - len(missing)}/{len(strings)} extracted strings translated, "
              f"{len(missing)} missing ({len(translations)} table entries)")
        if args.missing:
            print(json.dumps(sorted(missing), ensure_ascii=False, indent=2))
    return int(invalid)


if __name__ == "__main__":
    raise SystemExit(main())
