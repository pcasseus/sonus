"""Reads a COPY of a Sonus database and prints what tool/install-device.ps1
checks, as JSON: schema version, integrity, foreign-key violations and row
counts. The copy is opened read-only and immutable, so it is never changed.

Usage: python -I tool/sonus_db_check.py <copy.db>
"""

import json
import pathlib
import sqlite3
import sys

# Tables whose rows must never be lost across an update.
COUNTED = (
    "songs",
    "artists",
    "albums",
    "album_editions",
    "album_edition_tracks",
    "playlists",
    "playlist_items",
    "playback_sessions",
    "qualified_plays",
    "media_file_bindings",
    "artwork_assets",
    "chart_snapshots",
    "chart_entries",
    "chart_moment_events",
)


def main(path: str) -> None:
    uri = pathlib.Path(path).resolve().as_uri() + "?mode=ro&immutable=1"
    db = sqlite3.connect(uri, uri=True)
    try:
        tables = {
            row[0]
            for row in db.execute("SELECT name FROM sqlite_master WHERE type = 'table'")
        }
        report = {
            "user_version": db.execute("PRAGMA user_version").fetchone()[0],
            "integrity_check": [row[0] for row in db.execute("PRAGMA integrity_check")],
            "foreign_key_violations": len(db.execute("PRAGMA foreign_key_check").fetchall()),
            "counts": {
                table: db.execute(f'SELECT COUNT(*) FROM "{table}"').fetchone()[0]
                for table in COUNTED
                if table in tables
            },
        }
    finally:
        db.close()
    print(json.dumps(report, sort_keys=True))


if __name__ == "__main__":
    if len(sys.argv) != 2:
        sys.exit("usage: sonus_db_check.py <copy.db>")
    main(sys.argv[1])
