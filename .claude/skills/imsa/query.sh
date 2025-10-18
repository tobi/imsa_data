#!/bin/sh

# Default output format
FORMAT="-markdown"

# Check for --csv flag
if [ "$1" = "--csv" ]; then
    FORMAT="-csv"
    shift  # Remove --csv from arguments
fi

# Check for --remote flag
if [ "$1" = "--remote" ]; then
    REMOTE="--remote"
    shift  # Remove --remote from arguments
fi

# Check if query parameter is provided
if [ -z "$1" ]; then
    echo "Error: SQL query required" >&2
    echo "Usage: $0 [--csv] \"SELECT ... FROM laps ...\"" >&2
    echo "  --csv  Use CSV output (default: markdown)" >&2
    exit 1
fi

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Build path to database relative to script location
DB_PATH="$SCRIPT_DIR/../../../output/imsa.duckdb"

# Check if database exists
if [ "$REMOTE" != "--remote" ] && [ ! -f "$DB_PATH" ]; then
    echo "Error: Database not found at $DB_PATH use --remote" >&2
    echo "Usage: $0 [--csv] [--remote] \"SELECT ... FROM laps ...\"" >&2
    echo "  --csv  Use CSV output (default: markdown)" >&2
    echo "  --remote  Use remote database" >&2
    exit 1
fi

if [ "$REMOTE" = "--remote" ]; then
    exec duckdb "hf://datasets/tobil/imsa/imsa.duckdb" $FORMAT -c "$@"
else
    exec duckdb "$DB_PATH" $FORMAT -c "$@"
fi

# Execute query
duckdb "$DB_PATH" $FORMAT -c "$@"
