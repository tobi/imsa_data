#!/usr/bin/env python3
# /// script
# requires-python = ">=3.10"
# dependencies = [
#     "sqlmesh[duckdb]>=0.100.0",
# ]
# ///
"""
CLI scripts for IMSA SQLMesh pipeline.

Usage:
    uv run scripts.py update    # Build database and export CSVs
    uv run scripts.py plan      # Preview changes (interactive)
    uv run scripts.py apply     # Apply changes (non-interactive)
    uv run scripts.py audit     # Run data quality audits
    uv run scripts.py ui        # Launch web UI
    uv run scripts.py dag       # Show model DAG
    uv run scripts.py test      # Run SQLMesh tests
    uv run scripts.py export    # Export tables to CSV
    uv run scripts.py shell     # Open DuckDB shell
"""

import os
import subprocess
import sys
from pathlib import Path

PROJECT_DIR = Path(__file__).parent
OUTPUT_DIR = PROJECT_DIR / "output"


def run_sqlmesh(*args: str) -> int:
    """Run sqlmesh command with given arguments."""
    os.chdir(PROJECT_DIR)
    cmd = ["sqlmesh", *args]
    result = subprocess.run(cmd)
    return result.returncode


def update() -> None:
    """Build the database using SQLMesh and export CSVs."""
    OUTPUT_DIR.mkdir(exist_ok=True)

    print("Running SQLMesh plan --auto-apply...")
    code = run_sqlmesh("plan", "--auto-apply", "--no-prompts")
    if code != 0:
        sys.exit(code)

    print("\nExporting tables to CSV...")
    export_csv()

    print("\nDatabase updated successfully!")
    print(f"  {OUTPUT_DIR}/imsa.duckdb")
    print(f"  {OUTPUT_DIR}/drivers.csv")
    print(f"  {OUTPUT_DIR}/events.csv")
    print(f"  {OUTPUT_DIR}/laps.csv")
    print(f"  {OUTPUT_DIR}/seasons.csv")


def plan() -> None:
    """Preview changes without applying (SQLMesh plan)."""
    sys.exit(run_sqlmesh("plan"))


def apply() -> None:
    """Apply pending changes (SQLMesh plan --auto-apply)."""
    sys.exit(run_sqlmesh("plan", "--auto-apply", "--no-prompts"))


def audit() -> None:
    """Run data quality audits."""
    sys.exit(run_sqlmesh("audit"))


def ui() -> None:
    """Launch SQLMesh web UI."""
    sys.exit(run_sqlmesh("ui"))


def dag() -> None:
    """Show model dependency DAG."""
    sys.exit(run_sqlmesh("dag"))


def test() -> None:
    """Run SQLMesh tests."""
    sys.exit(run_sqlmesh("test"))


def export_csv() -> None:
    """Export tables to CSV files."""
    import duckdb

    OUTPUT_DIR.mkdir(exist_ok=True)
    db_path = OUTPUT_DIR / "imsa.duckdb"

    conn = duckdb.connect(str(db_path))

    exports = [
        ("marts.drivers", "drivers.csv"),
        ("marts.events", "events.csv"),
        ("marts.laps", "laps.csv"),
        ("marts.seasons", "seasons.csv"),
    ]

    for table, filename in exports:
        try:
            output_path = OUTPUT_DIR / filename
            conn.execute(f"COPY {table} TO '{output_path}' (HEADER, DELIMITER ',')")
            print(f"  Exported {table} -> {filename}")
        except Exception as e:
            print(f"  Warning: Could not export {table}: {e}")

    conn.close()


def shell() -> None:
    """Open DuckDB interactive shell."""
    db_path = OUTPUT_DIR / "imsa.duckdb"
    if not db_path.exists():
        print(f"Database not found at {db_path}")
        print("Run 'uv run update' first to build the database.")
        sys.exit(1)

    os.execvp("duckdb", ["duckdb", str(db_path)])


COMMANDS = {
    "update": update,
    "plan": plan,
    "apply": apply,
    "audit": audit,
    "ui": ui,
    "dag": dag,
    "test": test,
    "export": export_csv,
    "shell": shell,
}


def main():
    if len(sys.argv) < 2 or sys.argv[1] in ("-h", "--help", "help"):
        print(__doc__)
        print("Available commands:", ", ".join(COMMANDS.keys()))
        sys.exit(0)

    cmd = sys.argv[1]
    if cmd not in COMMANDS:
        print(f"Unknown command: {cmd}")
        print("Available commands:", ", ".join(COMMANDS.keys()))
        sys.exit(1)

    COMMANDS[cmd]()


if __name__ == "__main__":
    main()
