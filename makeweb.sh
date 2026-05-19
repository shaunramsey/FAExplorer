#!/bin/bash

# Define the target file name
OUTPUT_FILE="Status.md"
VERSION_FILE="Version.md"

# Format the date and time strings
CURRENT_DATE=$(date "+%Y-%m-%d")
CURRENT_TIME=$(date "+%H:%M:%S")


echo "# Status of Finite Automata Designer"  > "$OUTPUT_FILE"
echo "* Generated on: **$CURRENT_DATE** at **$CURRENT_TIME**" >> "$OUTPUT_FILE"

echo "# Build Status of Finite Automata Designer"  > "$VERSION_FILE"
echo "* Generated on: **$CURRENT_DATE** at **$CURRENT_TIME**" >> "$VERSION_FILE"

FILE="counter.txt"

# Read number (defaults to 0 if file is empty or missing)
NUM=$(cat "$FILE" 2>/dev/null || echo 0)

# Increment by 1
NEW_NUM=$((NUM + 1))

# Write back to file
echo "$NEW_NUM" > "$FILE"

echo "* Build number **$NEW_NUM**" >> "$OUTPUT_FILE"
echo "* [Go Back](README.md) - go to the Readme"  >> "$OUTPUT_FILE"
echo "* [Latest Build](build/web/index.html) - go to the last build"  >> "$OUTPUT_FILE"

echo "* Build number **$NEW_NUM**" >> "$VERSION_FILE"
echo "* [Go Back](README.md) - go to the Readme"  >> "$VERSION_FILE"


if [[ "$OSTYPE" == "msys" || "$OSTYPE" == "cygwin" ]]; then
    MSYS_NO_PATHCONV=1 flutter build web --release --base-href /FAExplorer/build/web/
else 
    flutter build web --release --base-href=/FAExplorer/build/web/
fi

echo "Output successfully written to $OUTPUT_FILE and $VERSION_FILE"