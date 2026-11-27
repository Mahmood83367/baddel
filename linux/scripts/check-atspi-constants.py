#!/usr/bin/env python3
"""Checks the AT-SPI enum values used in Native.cs against the installed header."""
import re
import sys

HEADER = "/usr/include/at-spi-2.0/atspi/atspi-constants.h"
EXPECTED = {
    "AtspiStateType": {"ATSPI_STATE_ACTIVE": 1, "ATSPI_STATE_EDITABLE": 7, "ATSPI_STATE_ENABLED": 8, "ATSPI_STATE_FOCUSED": 12},
    "AtspiRole": {"ATSPI_ROLE_PASSWORD_TEXT": 40},
    "AtspiCoordType": {"ATSPI_COORD_TYPE_SCREEN": 0},
}

source = re.sub(r"/\*.*?\*/", "", open(HEADER, encoding="utf-8").read(), flags=re.S)
failed = False
for enum, wanted in EXPECTED.items():
    match = re.search(r"typedef\s+enum\s*\{([^}]*)\}\s*" + enum + r"\s*;", source)
    if not match:
        print(f"FAIL {enum}: not found in header")
        failed = True
        continue
    value = -1
    values = {}
    for item in match.group(1).split(","):
        item = item.strip()
        if not item:
            continue
        name, _, explicit = item.partition("=")
        value = int(explicit.strip(), 0) if explicit.strip() else value + 1
        values[name.strip()] = value
    for name, number in wanted.items():
        ok = values.get(name) == number
        failed |= not ok
        print(f"{'PASS' if ok else 'FAIL'} {name} = {values.get(name)} (code uses {number})")
sys.exit(1 if failed else 0)
