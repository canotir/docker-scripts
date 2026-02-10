#!/bin/bash


#---------------------------------------------
# Usage
#---------------------------------------------
USAGE="
Usage: $(basename "$0") [-h] [-d] [-q] [-v]
  -h    Show this help
  -d    Dry run - detect updates but do NOT restart services
  -q    Quiet execution of docker commands
  -v    Verbose output
"


#---------------------------------------------
# Must run as root (or via sudo) 
#---------------------------------------------
if [[ $EUID -ne 0 ]]; then
    echo -e "\e[31mERROR:\e[0m this script must be run as root (use sudo)." >&2
    exit 1
fi


#---------------------------------------------
# Parse options
#---------------------------------------------
# defaults
DRY_RUN=0
QUIET=0
VERBOSE=0

# get user input
while getopts ":hdqv" opt; do
  case $opt in
    h) echo "$USAGE"; exit 0 ;;
    d) DRY_RUN=1 ;;
    q) QUIET=1 ;;
    v) VERBOSE=1 ;;
    *) echo "$USAGE"; exit 1 ;;
  esac
done


#---------------------------------------------
# Process all active docker services
#---------------------------------------------
# separator for non-quiet and verbose output
SEPARATOR="------------------------------------------------------------------------------------------"

# counter variables
NUM_SCANNED=0
NUM_UPDATED=0
NUM_IGNORED=0
NUM_FAILED=0

# get start time for time tracking
START_TIME=$(date +%s%N)

# cycle through every service, 
while FS=$'\t' read -r SERVICE _ CONFIG; do
    # increment counter
    (( NUM_SCANNED++ ))

    #---------------------------------------------
    # separator for improving readability in non-quiet or verbose mode
    #---------------------------------------------
    if (( ! QUIET || VERBOSE )); then
        echo $SEPARATOR
    fi
    

    #---------------------------------------------
    # Resolve directory and file
    #---------------------------------------------
    COMPOSE_PATH=${CONFIG%%,*}
    COMPOSE_DIR=$(dirname "$COMPOSE_PATH")
    COMPOSE_FILE=$(basename "$COMPOSE_PATH")


    #---------------------------------------------
    # Verbose output
    #---------------------------------------------
    if (( VERBOSE )); then
        echo ""
        echo "service ----> $SERVICE"
        echo "directory --> $COMPOSE_DIR"
    fi


    #---------------------------------------------
    # Verify we can cd to the directory and file exists
    #---------------------------------------------
    if ! cd "$COMPOSE_DIR" 2>/dev/null; then
        # log
        echo -e "$SERVICE: \e[31mdirectory does not exist --> $COMPOSE_DIR\e[0m" 
    
        # verbose output
        if (( VERBOSE )); then
            echo ""
        fi

        # increment counter
        (( NUM_FAILED++ ))

        continue
    fi


    #---------------------------------------------
    # Skip if a .docker-updater-ignore file exists in the root folder
    #---------------------------------------------
    if [[ -f "./.docker-updater-ignore" ]]; then
        # log
        echo -e "$SERVICE: .docker-updater-ignore file present --> skipping this service"
    
        # verbose output
        if (( VERBOSE )); then
            echo ""
        fi

        # increment counter
        (( NUM_IGNORED++ ))

        continue
    fi


    #---------------------------------------------
    # Skip if a Dockerfile exists in the root folder
    #---------------------------------------------
    if [[ -f "./Dockerfile" ]]; then
        # log
        echo "$SERVICE: Dockerfile present --> skipping this service"
    
        # verbose output
        if (( VERBOSE )); then
            echo ""
        fi

        # increment counter
        (( NUM_IGNORED++ ))

        continue
    fi


    #---------------------------------------------
    # Verify docker-compose file exists
    #---------------------------------------------
    if [[ ! -f "$COMPOSE_FILE" ]]; then
        # log
        echo -e "$SERVICE: \e[31mcompose file missing --> $COMPOSE_DIR\e[0m"
    
        # verbose output
        if (( VERBOSE )); then
            echo ""
        fi

        # increment counter
        (( NUM_FAILED++ ))

        continue
    fi


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
    fi
    

    #---------------------------------------------
    # separator for improving readability in non-quiet or verbose mode
    #---------------------------------------------
    if (( ! QUIET || VERBOSE )); then
        echo ""
    fi


    #---------------------------------------------
    # Get and compare digests of images used by inspected service and the images in local storage after pulling
    #---------------------------------------------
    # storage of the names of outdated images
    CHANGED=()

    # output verbose
    if (( VERBOSE )); then
        echo -e "container used by $SERVICE:"
    fi

    # cycle through every container deployed by the inspected service
    while FS=$'\t' read -r CONTAINER _ _ _; do
        # get image ref in repository:tag format used by the inspected container
        IMG_REF=$(docker inspect --format "{{.Config.Image}}" "$CONTAINER" 2>/dev/null)

        # fetch digest of image currently in use by container
        DIGEST_USED=$(docker inspect --format "{{.Image}}" "$CONTAINER" 2>/dev/null)

        # fetch digest of corresponding image in local image registry 
        DIGEST_REGISTRY=$(docker image inspect --format "{{.Id}}" "$IMG_REF" 2>/dev/null)

        # output verbose
        if (( VERBOSE )); then
            echo -e "  - $CONTAINER"
        fi

        # compare digests
        if [[ $DIGEST_USED != $DIGEST_REGISTRY ]]; then
            # image outdated
            CHANGED+=("$IMG_REF")

            # output verbose
            if (( VERBOSE )); then
                echo -e "      status --------------> \e[38;5;208mout-of-date\e[0m"
                echo -e "      image ---------------> $IMG_REF"
                echo    "      digest in use -------> $DIGEST_USED"
                echo    "      digest in registry --> $DIGEST_REGISTRY"
            fi
        else
            # image up-to-date
            # output verbose
            if (( VERBOSE )); then
                echo -e "      status --> \e[32mup-to-date\e[0m"
                echo -e "      image ---> $IMG_REF"
                echo    "      digest --> $DIGEST_USED"
            fi
        fi
    done < <(docker compose images --format table | tail -n +2) # get list of all containers used by inspected service  as table and skip the headline


    #---------------------------------------------
    # separator for improving readability in verbose mode
    #---------------------------------------------
    if (( VERBOSE )); then
        echo ""
    fi


    #---------------------------------------------
    # If any digests differ, recreate services
    #---------------------------------------------
    if (( ${#CHANGED[@]} )); then
        echo -e "$SERVICE: \e[38;5;208mout-of-date --> ${CHANGED[*]}\e[0m"
        
        if (( DRY_RUN )); then
            echo " dry-run..."
        else
            # increment counter
            (( NUM_UPDATED++ ))

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
            fi
        fi
    else
        echo -e "$SERVICE: \e[32mup-to-date\e[0m"
    fi


    #---------------------------------------------
    # separator for improving readability in non-quiet or verbose mode
    #---------------------------------------------
    if (( ! QUIET || VERBOSE )); then
        echo ""
    fi
done < <(docker compose ls --format table | tail -n +2) # get list of all services as table and skip the headline


#---------------------------------------------
# Compute elapsed time
#---------------------------------------------
# get end time for time tracking
END_TIME=$(date +%s%N)

# convert to seconds
ELAPSED_TIME_s=$(awk "BEGIN {printf \"%.3f\", $(( END_TIME - START_TIME ))/1000000000}")


#---------------------------------------------
# Verbose output: statistics
#---------------------------------------------
if (( ! QUIET || VERBOSE )); then
    echo $SEPARATOR
    echo ""
    echo -e "services scanned --> $NUM_SCANNED"
    echo -e "         updated --> \e[32m$NUM_UPDATED\e[0m"
    echo -e "         ignored --> \e[38;5;208m$NUM_IGNORED\e[0m"
    echo -e "         failed ---> \e[31m$NUM_FAILED\e[0m"
    echo ""
    echo "elapsed time --> $ELAPSED_TIME_s seconds"
    echo ""
    echo $SEPARATOR
fi


#---------------------------------------------
# Exit
#---------------------------------------------
exit 0