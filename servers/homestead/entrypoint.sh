#!/usr/bin/env bash
set -e

# Copy server files to data volume (preserves world data on restarts)
cp -rn /app/* /data/ 2>/dev/null || cp -r /app/* /data/

cd /data
exec ./start.sh
