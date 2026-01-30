#!/bin/bash
# Data loader for Elo rating history
# Outputs CSV to stdout for Observable Framework time-series visualization
#
# Columns: driver,session_date,event,series_code,class,elo,delta,laps,cumulative_laps,license

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$SCRIPT_DIR/../../.."

# Run the Elo calculation script
cd "$PROJECT_ROOT"
nix-shell -p ruby --run "ruby compute_elo.rb --output-history --no-current -m 0"
