#!/bin/bash


#---------------------------------------------
# Usage
#---------------------------------------------
USAGE="
Usage: $(basename "$0") [-h] [-d] [-q]
  -h    Show this help
  -d    Dry run - detect updates but do NOT restart services
  -q    Quiet execution of docker commands
"


#---------------------------------------------
# Parse options
#---------------------------------------------
# defaults
DRY_RUN=0
QUIET=0

# get user input
while getopts ":hdq" opt; do
  case $opt in
    h) echo "$USAGE"; exit 0 ;;
    d) DRY_RUN=1 ;;
    q) QUIET=1 ;;
    *) echo "$USAGE"; exit 1 ;;
  esac
done


#---------------------------------------------
# Must run as root (or via sudo) 
#---------------------------------------------
if [[ $EUID -ne 0 ]]; then
    echo "ERROR: this script must be run as root (use sudo)." >&2
    exit 1
fi


#---------------------------------------------
# Get list of compose services (table format)
#---------------------------------------------
docker compose ls --format table |
tail -n +2 | # <-- skip header
while read -r LINE; do
    #---------------------------------------------
    # separator for improving readability in non-quiet mode
    #---------------------------------------------
    if (( ! QUIET )); then
        echo "---------------------------------------------"
    fi


    #---------------------------------------------
    # Split line into fields (whitespace separated)
    #---------------------------------------------
    set -- $LINE

    # separate out information
    SERVICE=$1
    CONFIGRAW=$3 # third column = path to compose file


    #---------------------------------------------
    # Get the first config path
    #---------------------------------------------
    CONFIG=${CONFIGRAW%%,*}


    #---------------------------------------------
    # Resolve directory and file
    #---------------------------------------------
    COMPOSE_PATH="$CONFIG"
    COMPOSE_DIR=$(dirname "$COMPOSE_PATH")
    COMPOSE_FILE=$(basename "$COMPOSE_PATH")


    #---------------------------------------------
    # Verify we can cd to the directory and file exists
    #---------------------------------------------
    if ! cd "$COMPOSE_DIR" 2>/dev/null; then
        echo -e "$SERVICE: \e[31mdirectory does not exist --> $COMPOSE_DIR\e[0m"   
        continue
    fi


    #---------------------------------------------
    # Skip if a .docker-updater-ignore file exists in the root folder
    #---------------------------------------------
    if [[ -f "./.docker-updater-ignore" ]]; then
        echo "$SERVICE: .docker-updater-ignore file present --> skipping this service"
        continue
    fi


    #---------------------------------------------
    # Skip if a Dockerfile exists in the root folder
    #---------------------------------------------
    if [[ -f "./Dockerfile" ]]; then
        echo "$SERVICE: Dockerfile present --> skipping this service"
        continue
    fi


    #---------------------------------------------
    # Verify docker-compose file exists
    #---------------------------------------------
    if [[ ! -f "$COMPOSE_FILE" ]]; then
        echo -e "$SERVICE: \e[31mcompose file missing --> $COMPOSE_DIR\e[0m"
        continue
    fi

    #---------------------------------------------
    # Capture current image digests
    #---------------------------------------------
    declare -A BEFORE

    # get list of images used by the inspected service
    docker compose images --format table |
    tail -n +2 | # <-- skip header line
    while read -r IMG_LINE; do
        set -- $IMG_LINE

        # separate out information
        CONTAINER=$1
        REPO=$2
        TAG=$3
        IMG_REF="${REPO}:${TAG}"

        # fetch digest of image used by inspected container
        DIGEST=$(docker inspect --format "{{.Image}}" "$CONTAINER" 2>/dev/null)
        
        # store digest
        BEFORE["$IMG_REF"]=$DIGEST
    done


    #---------------------------------------------
    # Pull latest images for this service
    #---------------------------------------------
    if (( QUIET )); then
        # quiet mode
        docker compose pull >/dev/null 2>&1
    else
        # non-quiet mode
        echo ""
        docker compose pull
        echo ""
    fi


    #---------------------------------------------
    # Capture new image digests
    #---------------------------------------------
    declare -A AFTER

    # get list of images used by the inspected service
    docker compose images --format table |
    tail -n +2 | # <-- skip header line
    while read -r IMG_LINE; do
        set -- $IMG_LINE

        # separate out information
        CONTAINER=$1
        REPO=$2
        TAG=$3
        IMG_REF="${REPO}:${TAG}"

        # fetch digest of image in the local image registry corresponding to the same repo:tag used by the inspected container
        DIGEST=$(docker inspect --format "{{.Id}}" "$IMG_REF" 2>/dev/null)

        # store digest
        AFTER["$IMG_REF"]=$DIGEST
    done


    #---------------------------------------------
    # Compare digests before and after
    #---------------------------------------------
    CHANGED=()
    for IMG in "${!AFTER[@]}"; do
        if [[ "${BEFORE[$IMG]}" != "${AFTER[$IMG]}" ]]; then
            CHANGED+=("$IMG")
        fi
    done


    #---------------------------------------------
    # If any digests differ, recreate services
    #---------------------------------------------
    if (( ${#CHANGED[@]} )); then
        echo -e "$SERVICE: \e[38;5;208mout-of-date\e[0m --> ${CHANGED[*]}"
        
        if (( DRY_RUN )); then
            echo " dry-run..."
        else
            # stop, remove, and recreate service with the new images
            if (( QUIET )); then
                # quiet mode
                docker compose stop                     >/dev/null 2>&1
                docker compose rm   -f                  >/dev/null 2>&1
                docker compose up   -d --force-recreate >/dev/null 2>&1
            else
                # non-quiet mode
                echo ""
                docker compose stop
                docker compose rm   -f
                docker compose up   -d --force-recreate
                echo ""
            fi
        fi
    else
        echo -e "$SERVICE: \e[32mup-to-date\e[0m"
    fi

    #---------------------------------------------
    # separator for improving readability in non-quiet mode
    #---------------------------------------------
    if (( ! QUIET )); then
        echo ""
    fi


    #---------------------------------------------
    # clean associative arrays for next iteration
    #---------------------------------------------
    unset BEFORE AFTER
done


#---------------------------------------------
# separator for improving readability in non-quiet mode
#---------------------------------------------
if (( ! QUIET )); then
    echo "---------------------------------------------"
fi


#---------------------------------------------
# Exit
#---------------------------------------------
exit 0