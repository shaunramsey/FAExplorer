#!/bin/bash

# Define the target file name
OUTPUT_FILE="status.md"

# Format the date and time strings
CURRENT_DATE=$(date "+%Y-%m-%d")
CURRENT_TIME=$(date "+%H:%M:%S")

flutter build web --release --base-href=/FAExplorer/build/web/
echo "# Status of Finite Automata Designer"  > "$OUTPUT_FILE"
echo "* Generated on: **$CURRENT_DATE** at **$CURRENT_TIME**" >> "$OUTPUT_FILE"


FILE="counter.txt"

# Read number (defaults to 0 if file is empty or missing)
NUM=$(cat "$FILE" 2>/dev/null || echo 0)

# Increment by 1
NEW_NUM=$((NUM + 1))

# Write back to file
echo "$NEW_NUM" > "$FILE"
echo "* Build number **$NEW_NUM**" >> "$OUTPUT_FILE"
echo "# [Go Back](README.md)"  >> "$OUTPUT_FILE"
echo "Output successfully written to $OUTPUT_FILE"