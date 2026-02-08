#!/bin/bash


# Usage -------------------------------------------------
USAGE="
Usage: $(basename "$0") [-h] [-d DIR]
  -h       Show this help
  -d DIR   Directory containing docker files (default: current dir)
"


# Parse options -----------------------------------------
while getopts ":hd:" opt; do
  case $opt in
    h) echo "$USAGE"; exit 0 ;;
    d) TARGET_DIR=$OPTARG ;;
    *) echo "$USAGE"; exit 1 ;;
  esac
done


# Determine working directory ---------------------------
TARGET_DIR=${TARGET_DIR:-$(pwd)}


# Move there ---------------------------------------------
if ! cd "$TARGET_DIR"; then
  echo "ERROR: cannot cd to $TARGET_DIR"
  exit 1
fi


# Verify compose file ------------------------------------
if [[ ! -f ./docker-compose.yml ]]; then
  echo "ERROR: docker-compose.yml not found in $TARGET_DIR"
  exit 1
fi
echo "found docker-compose.yml"


# Ensure script is run as root or via sudo -------------------------------------------
if [[ $EUID -ne 0 ]]; then
    echo "ERROR: this script must be run as root (use sudo)." >&2
    exit 1
fi


# Refresh containers -------------------------------------
docker compose pull
docker compose stop
docker compose rm -f
docker compose up -d --force-recreate


# Exit -------------------------------------
exit 0