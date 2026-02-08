#!/bin/bash


# Usage ---------------------------------------------
USAGE="
Usage: $(basename "$0") [-h]
  -h    Show this help
  -d    Dry run - detect updates but do NOT restart services
"


# Parse options -----------------------------------------
# defaults
DRY_RUN=0

# get user input
while getopts ":hd" opt; do
  case $opt in
    h) echo "$USAGE"; exit 0 ;;
    d) DRY_RUN=1 ;;
    *) echo "$USAGE"; exit 1 ;;
  esac
done


# Must run as root (or via sudo)  ---------------------------------------------
if [[ $EUID -ne 0 ]]; then
    echo "ERROR: this script must be run as root (use sudo)." >&2
    exit 1
fi


# Get list of compose services (table format) ---------------------------------------------
docker compose ls --format table |
tail -n +2 | # <-- skip header
while read -r LINE; do
    # Split line into fields (whitespace separated) ---------------------------------------------
    set -- $LINE
    SERVICE=$1
    CONFIGRAW=$3 # third column = path to compose file


    # Get the first config path ---------------------------------------------
    CONFIG=${CONFIGRAW%%,*}


    # Resolve directory and file ---------------------------------------------
    COMPOSE_PATH="$CONFIG"
    COMPOSE_DIR=$(dirname "$COMPOSE_PATH")
    COMPOSE_FILE=$(basename "$COMPOSE_PATH")


    # Verify we can cd to the directory and file exists ---------------------------------------------
    if ! cd "$COMPOSE_DIR" 2>/dev/null; then
        echo "$SERVICE: cannot cd to $COMPOSE_DIR"
        continue
    fi
    if [[ ! -f "$COMPOSE_FILE" ]]; then
        echo "$SERVICE: compose file missing --> $COMPOSE_PATH"
        continue
    fi


    # Skip if a Dockerfile exists in the root folder ---------------------------------------------
    if [[ -f "./Dockerfile" ]]; then
        echo "$SERVICE: Dockerfile present --> skipping this service"
        continue
    fi


    # Capture current image IDs ---------------------------------------------
    declare -A BEFORE
    docker compose images --format table |
    tail -n +2 |                                # <-- skip header
    while read -r IMG_LINE; do
        set -- $IMG_LINE
        REPO=$2
        TAG=$3
        IMG_REF="${REPO}:${TAG}"
        ID=$(docker image inspect --format "{{.Id}}" "$IMG_REF" 2>/dev/null)
        BEFORE["$IMG_REF"]=$ID
    done


    # Pull latest images for this service ---------------------------------------------
    docker compose pull >/dev/null 2>&1


    # Capture new image IDs ---------------------------------------------
    declare -A AFTER
    docker compose images --format table |
    tail -n +2 | # <-- skip header
    while read -r IMG_LINE; do
        set -- $IMG_LINE
        REPO=$2
        TAG=$3
        IMG_REF="${REPO}:${TAG}"
        ID=$(docker image inspect --format "{{.Id}}" "$IMG_REF" 2>/dev/null)
        AFTER["$IMG_REF"]=$ID
    done


    # Compare IDs - if any differ, recreate service ---------------------------------------------
    CHANGED=()
    for IMG in "${!AFTER[@]}"; do
        if [[ "${BEFORE[$IMG]}" != "${AFTER[$IMG]}" ]]; then
            CHANGED+=("$IMG")
        fi
    done

    if (( ${#CHANGED[@]} )); then
        echo "$SERVICE: out-of-date --> ${CHANGED[*]}"
        
        if (( DRY_RUN )); then
            echo "  dry-run..."
        else
            echo ""
            echo "updating..."

            # stop, remove, and recreate service with the new images
            docker compose stop
            docker compose rm -f
            docker compose up -d --force-recreate

            echo ""
        fi
    else
        echo "$SERVICE: up-to-date"
    fi

    # clean associative arrays for next iteration ---------------------------------------------
    unset BEFORE AFTER
done