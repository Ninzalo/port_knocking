#!/bin/sh
# Usage: sh change_value.sh FILEPATH KEY VALUE

if [ "$#" -ne 3 ]; then
    echo "Usage: $0 FILEPATH KEY VALUE" >&2
    exit 1
fi

FILEPATH="$1"
KEY="$2"
VALUE="$3"

if [ ! -f "$FILEPATH" ]; then
    echo "Error: File '$FILEPATH' not found." >&2
    exit 1
fi

awk -v key="$KEY" -v value="$VALUE" '
BEGIN {
    FS = "[ \t=]+"
    OFS = " "
    delimiter = " "
    found = 0
    last_match = 0
}

{
    lines[NR] = $0

    # Check for uncommented lines
    if ($0 ~ "^[[:space:]]*" key "([[:space:]=].*|$)") {
        last_match = NR
        found = 1
        delimiter = ($2 == "" && NF >= 2) ? " " : OFS
    }

    # Check for commented lines if not found yet
    if (!found && $0 ~ "^[[:space:]]*#[[:space:]]*" key "([[:space:]=].*|$)") {
        last_match = NR
        delimiter = ($2 == "" && NF >= 2) ? " " : OFS
    }
}

END {
    if (last_match > 0) {
        split(lines[last_match], parts, /[ \t=]/)
        current_delim = (parts[2] ~ /^=/) ? "=" : " "
        lines[last_match] = key current_delim value
    } else {
        lines[NR+1] = key " " value
        NR++
    }

    for (i = 1; i <= NR; i++) {
        print lines[i]
    }
}
' "$FILEPATH" > "$FILEPATH.tmp" && mv "$FILEPATH.tmp" "$FILEPATH"

exit 0
