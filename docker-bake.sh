#!/bin/bash


#---------------------------------------------
# Usage
#---------------------------------------------
USAGE="
Usage: $(basename "$0") [-h] [-d DIR] [-r REPO] [-t TAG]
  -h       Show this help
  -d DIR   Directory containing Dockerfile & compose (default: current dir)
  -r REPO  Docker repository name (default: basename of DIR)
  -t TAG   Image tag (default: YY.MM.DD)
"


#---------------------------------------------
# Default tag 
#---------------------------------------------
TAG=$(date +"%y.%m.%d")


#---------------------------------------------
# Parse options 
#---------------------------------------------
while getopts ":hd:r:t:" opt; do
  case $opt in
    h) echo "$USAGE"; exit 0 ;;
    d) TARGET_DIR=$OPTARG ;;
    r) REPO=$OPTARG ;;
    t) TAG=$OPTARG ;;
    *) echo "$USAGE"; exit 1 ;;
  esac
done


#---------------------------------------------
# Determine working directory 
#---------------------------------------------
TARGET_DIR=${TARGET_DIR:-$(pwd)}


#---------------------------------------------
# Set repository name if not supplied 
#---------------------------------------------
if [[ -z $REPO ]]; then
  REPO=$(basename "$TARGET_DIR")
  echo "docker repository not defined, using: $REPO"
else
  echo "docker repository is user-defined: $REPO"
fi


#---------------------------------------------
# Move there 
#---------------------------------------------
if ! cd "$TARGET_DIR"; then
  echo "ERROR: cannot cd to $TARGET_DIR"
  exit 1
fi


#---------------------------------------------
# Verify required files 
#---------------------------------------------
if [[ ! -f ./Dockerfile ]]; then
  echo "ERROR: Dockerfile not found in $TARGET_DIR"
  exit 1
fi
echo "found Dockerfile"

if [[ ! -f ./docker-compose.yml ]]; then
  echo "ERROR: docker-compose.yml not found in $TARGET_DIR"
  exit 1
fi
echo "found docker-compose.yml"


#---------------------------------------------
# Ensure script is run as root or via sudo 
#---------------------------------------------
if [[ $EUID -ne 0 ]]; then
    echo "ERROR: this script must be run as root (use sudo)." >&2
    exit 1
fi


#---------------------------------------------
# Build images 
#---------------------------------------------
docker buildx build --no-cache -t "$REPO:$TAG" .
docker buildx build            -t "$REPO:latest" .


#---------------------------------------------
# Restart containers 
#---------------------------------------------
docker compose stop
docker compose rm -f
docker compose up -d --force-recreate


#---------------------------------------------
# Exit 
#---------------------------------------------
exit 0