#!/bin/bash


#---------------------------------------------
# Usage
#---------------------------------------------
USAGE="
Usage: $(basename "$0") [-h] [-d] [-c] [-D] [-v] [-p] [-P]
  -h    Show this help
  -d    Dry run - detect updates but do NOT restart services, do NOT prune images.
  -c    Disable colored terminal output in verbose and non-quiet docker mode (except for outputs of docker).
  -D    Show terminal output of docker.
  -v    Verbose output.
  -p    Prune DANGLING images after service updates.
  -P    Prune ALL unused images after service updates.
"


#---------------------------------------------
# Parse options
#---------------------------------------------
# defaults
DRY_RUN=0
QUIET_DOCKER=1
VERBOSE=0
PRUNE_IMAGES=0
OPT_PRUNE_ALL=()
COLOR_ENABLE=1

# options
OPTARGS="hdcDvpP"

# get user input
while getopts $OPTARGS opt; do
  case $opt in
    h) echo "$USAGE"; exit 0 ;;                 # print help and exit
    d) DRY_RUN=1 ;;                             # set dry-run mode enabled
    c) COLOR_ENABLE=0 ;;                        # disable color
    D) QUIET_DOCKER=0 ;;                        # set non-quiet docker mode enabled
    v) VERBOSE=1 ;;                             # set verbose output enabled
    p) PRUNE_IMAGES=1 ;;                        # set prune dangling images enabled
    P) PRUNE_IMAGES=1; OPT_PRUNE_ALL=(-a) ;;    # set prune all unused images enabled
    ?) echo "$USAGE"; exit 1 ;;                 # unavailable option selected, print help and exit
  esac
done


#---------------------------------------------
# Handle stray input
#---------------------------------------------
# Strips away all parsed options, leaving only leftover arguments.
# After option parsing, any remaining tokens are non-option arguments.
shift $((OPTIND - 1))

# detect non-option arguments, print error, and exit
if (( $# > 0 )); then
    # display error message
    echo "ERROR: Unexpected argument(s): $*"

    # display help
    echo "$USAGE"

    exit 3
fi


#---------------------------------------------
# Must run as root (or via sudo) 
#---------------------------------------------
if [[ $EUID -ne 0 ]]; then
    echo "ERROR: this script must be run as root (use sudo)."
    exit 1
fi


#---------------------------------------------
# Terminal output elements
#---------------------------------------------
# separator for non-quiet and verbose output --> length can be specified!
SEPARATOR="$(printf '%*s' "90" '' | tr ' ' '-')"

# color
if (( COLOR_ENABLE )); then
    # color enabled mode
    COLOR_DEFAULT="\e[0m"
    COLOR_SUCCESS="\e[32m"
    COLOR_NOTE="\e[33m"
    COLOR_ERROR="\e[31m"
else
    # color disenabled mode
    COLOR_DEFAULT=""
    COLOR_SUCCESS=""
    COLOR_NOTE=""
    COLOR_ERROR=""
fi


#---------------------------------------------
# Functions
#---------------------------------------------
# docker: base command
FN_DOCKER=(docker)

# docker: get services and container
FN_GET_SERVICES=(${FN_DOCKER[@]} compose ls --format table)
FN_GET_SERVICE_CONTAINER=(${FN_DOCKER[@]} compose images --format table)

# docker: compose stop, remove, up, pull
FN_DOCKER_SERVICE_STOP=(${FN_DOCKER[@]} compose stop)
FN_DOCKER_SERVICE_RM=(${FN_DOCKER[@]} compose rm -f)
FN_DOCKER_SERVICE_UP=(${FN_DOCKER[@]} compose up -d --force-recreate)
FN_DOCKER_PULL=(${FN_DOCKER[@]} compose pull)

# docker: get image reference and digests
FN_GET_IMG_REF=(${FN_DOCKER[@]} inspect --format "{{.Config.Image}}")
FN_GET_DIGEST_USED=(${FN_DOCKER[@]} inspect --format "{{.Image}}")
FN_GET_DIGEST_REGISTRY=(${FN_DOCKER[@]} image inspect --format "{{.Id}}")

# docker: prune unused images
FN_PRUNE_IMAGES=(${FN_DOCKER[@]} image prune -f ${OPT_PRUNE_ALL[@]})

# skip and fetch lines
FN_DROP_HEADER=(tail -n +2)
FN_DROP_FOOTER=(head -n -1)
FN_FETCH_FOOTER=(tail -n 1)

# count lines
FN_COUNT_LINES=(wc -l)


#---------------------------------------------
# Files
#---------------------------------------------
# docker
DOCKER_FILE="Dockerfile"
IGNORE_FILE=".docker-updater-ignore"

# sinkhole file for command outputs
SINKHOLE="/dev/null"


#---------------------------------------------
# Process all active docker services
#---------------------------------------------
# counter variables: services
NUM_SERVICES_SCANNED=0
NUM_SERVICES_UPDATED=0
NUM_SERVICES_IGNORED=0
NUM_SERVICES_FAILED=0

# counter variables: container
NUM_CONTAINER_SCANNED=0
NUM_CONTAINER_UPDATED=0

# get start time for time tracking
START_TIME=$(date +%s%N)

# cycle through every service
while FS=$'\t' read -r SERVICE _ CONFIG; do
    # increment counter
    (( NUM_SERVICES_SCANNED++ ))

    # separator for improving readability in non-quiet or verbose mode
    if (( ! QUIET_DOCKER || VERBOSE )); then
        echo ""
        echo $SEPARATOR
    fi
    

    #---------------------------------------------
    # Resolve directory and file
    #---------------------------------------------
    # The CONFIG variable may contain several filepaths to compose files used by the inspected service.
    # The filepaths are separated by a comma.
    # The first file should always be the main docker-compose file, the other files may be docker-compose-override files.
    # However, this needs to be verified...
    # For now, I just separate out the first entry and hope that my preliminary observations are correct :)
    COMPOSE_PATH=${CONFIG%%,*}

    # separate directory and filename
    COMPOSE_DIR=$(dirname "$COMPOSE_PATH")
    COMPOSE_FILE=$(basename "$COMPOSE_PATH")


    #---------------------------------------------
    # Verbose output: information on currently inspected service
    #---------------------------------------------
    if (( ! QUIET_DOCKER || VERBOSE )); then
        echo ""
        echo "Service: $SERVICE"
        echo "Directory: $COMPOSE_DIR"
    fi


    #---------------------------------------------
    # Verify we can cd to the directory and file exists
    #---------------------------------------------
    if ! cd "$COMPOSE_DIR" &>$SINKHOLE; then
        # output
        if (( ! QUIET_DOCKER || VERBOSE )); then
            echo ""
            echo -e "${COLOR_ERROR}ERROR:${COLOR_DEFAULT} Directory non-existent."
        else
            echo "$SERVICE: Directory non-existent ($COMPOSE_DIR)"
        fi

        # increment counter
        (( NUM_SERVICES_FAILED++ ))

        continue
    fi


    #---------------------------------------------
    # Skip if an ignore file exists in the root folder
    #---------------------------------------------
    if [[ -f "./$IGNORE_FILE" ]]; then
        # output
        if (( ! QUIET_DOCKER || VERBOSE )); then
            echo ""
            echo -e "${COLOR_NOTE}Skipping:${COLOR_DEFAULT} $IGNORE_FILE file present."
        else
            echo "$SERVICE: Skipping service ($IGNORE_FILE file present)."
        fi

        # increment counter
        (( NUM_SERVICES_IGNORED++ ))

        continue
    fi


    #---------------------------------------------
    # Skip if a Dockerfile exists in the root folder
    #---------------------------------------------
    if [[ -f "./$DOCKER_FILE" ]]; then
        # output
        if (( ! QUIET_DOCKER || VERBOSE )); then
            echo ""
            echo -e "${COLOR_NOTE}Skipping:${COLOR_DEFAULT} $DOCKER_FILE present."
        else
            echo "$SERVICE: Skipping service ($DOCKER_FILE present)."
        fi

        # increment counter
        (( NUM_SERVICES_IGNORED++ ))

        continue
    fi


    #---------------------------------------------
    # Verify docker-compose file exists
    #---------------------------------------------
    if [[ ! -f "$COMPOSE_FILE" ]]; then
        # output
        if (( ! QUIET_DOCKER || VERBOSE )); then
            echo ""
            echo -e "${COLOR_ERROR}ERROR:${COLOR_DEFAULT} $COMPOSE_FILE missing."
        else
            echo "$SERVICE: $COMPOSE_FILE missing."
        fi

        # increment counter
        (( NUM_SERVICES_FAILED++ ))

        continue
    fi


    #---------------------------------------------
    # Pull latest images for this service
    #---------------------------------------------
    if (( QUIET_DOCKER )); then
        # pull images quietly
        ${FN_DOCKER_PULL[@]} &>$SINKHOLE
    else
        # log
        echo ""
        echo "Pulling images..."

        # pull images
        ${FN_DOCKER_PULL[@]}
    fi


    #---------------------------------------------
    # Get and compare digests of images used by inspected service and the images in local storage after pulling
    #---------------------------------------------
    # variables
    CHANGED=()          # storage of the names of outdated images
    CONTAINER_LIST=""   # list of all containers used by inspected service

    # output verbose
    if (( VERBOSE )); then
        echo ""
        echo -e "Container status:"
    fi

    # cycle through every container deployed by the inspected service
    while FS=$'\t' read -r CONTAINER _ _ _; do
        # add name of current inspected container to list
        if [[ -z $CONTAINER_LIST ]]; then
            CONTAINER_LIST=$CONTAINER
        else
            CONTAINER_LIST="$CONTAINER_LIST, $CONTAINER"
        fi

        # increment counter
        (( NUM_CONTAINER_SCANNED++ ))


        #---------------------------------------------
        # Get digests of used and pulled images
        #---------------------------------------------
        # get image ref in repository:tag format used by the inspected container
        IMG_REF=$(${FN_GET_IMG_REF[@]} "$CONTAINER" 2>$SINKHOLE)

        # fetch digest of image currently in use by container
        DIGEST_USED=$(${FN_GET_DIGEST_USED[@]} "$CONTAINER" 2>$SINKHOLE)

        # fetch digest of corresponding image in local image registry 
        DIGEST_REGISTRY=$(${FN_GET_DIGEST_REGISTRY[@]} "$IMG_REF" 2>$SINKHOLE)


        #---------------------------------------------
        # compare digests
        #---------------------------------------------
        if [[ $DIGEST_USED != $DIGEST_REGISTRY ]]; then
            # digests not identical --> image outdated
            # store name of outdated image in list
            CHANGED+=("$IMG_REF")

            # increment counter
            (( NUM_CONTAINER_UPDATED++ ))

            # output verbose
            if (( VERBOSE )); then
                echo -e "- $CONTAINER: ${COLOR_NOTE}out-of-date${COLOR_DEFAULT}"
                echo -e "  - Image: $IMG_REF"
                echo    "  - Digest OLD: $DIGEST_USED"
                echo    "           NEW: $DIGEST_REGISTRY"
            fi
        else
            # digests identical --> image up-to-date
            # output verbose
            if (( VERBOSE )); then
                echo -e "- $CONTAINER: ${COLOR_SUCCESS}up-to-date${COLOR_DEFAULT}"
                echo -e "  - Image: $IMG_REF"
                echo    "  - Digest: $DIGEST_USED"
            fi
        fi
    done < <(${FN_GET_SERVICE_CONTAINER[@]} | ${FN_DROP_HEADER[@]}) # get list of all containers used by inspected service  as table and skip the headline

    # separator for improving readability in verbose mode
    if (( ! QUIET_DOCKER || VERBOSE )); then
        echo ""
    fi


    #---------------------------------------------
    # If any digests differ, recreate services
    #---------------------------------------------
    if (( ${#CHANGED[@]} )); then
        # increment counter
        (( NUM_SERVICES_UPDATED++ ))


        #---------------------------------------------
        # in verbose mode: output status before rebuild
        #---------------------------------------------
        if (( VERBOSE )); then
            echo -e "${COLOR_NOTE}Image(s) out-of-date, rebuilding service...${COLOR_DEFAULT}"
            echo ""
        fi
        
        #---------------------------------------------
        # perform docker compose rebuild steps
        #---------------------------------------------
        if (( ! DRY_RUN )); then
            #---------------------------------------------
            # stop, remove, and recreate service with the new images
            #---------------------------------------------
            if (( QUIET_DOCKER )); then
                # quiet mode
                ${FN_DOCKER_SERVICE_STOP[@]} &>$SINKHOLE
                ${FN_DOCKER_SERVICE_RM[@]}   &>$SINKHOLE
                ${FN_DOCKER_SERVICE_UP[@]}   &>$SINKHOLE
            else
                # non-quiet mode
                echo "Going to stop $CONTAINER_LIST"
                ${FN_DOCKER_SERVICE_STOP[@]}

                echo ""
                ${FN_DOCKER_SERVICE_RM[@]}

                echo ""
                echo "Going to restart $CONTAINER_LIST"
                ${FN_DOCKER_SERVICE_UP[@]}
            fi

            #---------------------------------------------
            # output service update status information: after rebuild
            #---------------------------------------------
            if (( ! QUIET_DOCKER || VERBOSE )); then
                echo ""
                echo -e "${COLOR_SUCCESS}Image(s) updated, service rebuilt.${COLOR_DEFAULT}"
            else
                echo "$SERVICE: Image(s) updated (${CHANGED[*]}), service rebuilt."
            fi
        else
            #---------------------------------------------
            # output service update status information: dry-run
            #---------------------------------------------
            if (( ! QUIET_DOCKER || VERBOSE )); then
                echo -e "${COLOR_SUCCESS}No rebuilding performed (dry-run).${COLOR_DEFAULT}"
            else
                echo "$SERVICE: No rebuilding performed (dry-run)."
            fi
        fi
    else
        # output service update status information: up-to-date
        if (( ! QUIET_DOCKER || VERBOSE )); then
            echo -e "Service status: ${COLOR_SUCCESS}up-to-date${COLOR_DEFAULT}"
        else
            echo "$SERVICE: up-to-date"
        fi
    fi
done < <(${FN_GET_SERVICES[@]} | ${FN_DROP_HEADER[@]}) # get list of all services as table and skip the headline


#---------------------------------------------
# Show statistics
#---------------------------------------------
# get number of digits
DIGITS=${#NUM_CONTAINER_SCANNED}

# print
if (( ! QUIET_DOCKER || VERBOSE )); then
    # non-quiet docker or verbose modes
    printf "\n%s\n\n" "$SEPARATOR"
    printf "Services  scanned: %${DIGITS}s\n" "$NUM_SERVICES_SCANNED"
    printf "          updated: ${COLOR_SUCCESS}%${DIGITS}s${COLOR_DEFAULT}\n" "$NUM_SERVICES_UPDATED"
    printf "          ignored: ${COLOR_NOTE}%${DIGITS}s${COLOR_DEFAULT}\n" "$NUM_SERVICES_IGNORED"
    printf "          failed:  ${COLOR_ERROR}%${DIGITS}s${COLOR_DEFAULT}\n" "$NUM_SERVICES_FAILED"
    printf "Container scanned: %${DIGITS}s\n" "$NUM_CONTAINER_SCANNED"
    printf "          updated: ${COLOR_SUCCESS}%${DIGITS}s${COLOR_DEFAULT}\n" "$NUM_CONTAINER_UPDATED"
else
    # quiet docker and non-verbose mode
    printf "\n"
    printf "Services  scanned: %${DIGITS}s\n" "$NUM_SERVICES_SCANNED"
    printf "          updated: %${DIGITS}s\n" "$NUM_SERVICES_UPDATED"
    printf "          ignored: %${DIGITS}s\n" "$NUM_SERVICES_IGNORED"
    printf "          failed:  %${DIGITS}s\n" "$NUM_SERVICES_FAILED"
    printf "Container scanned: %${DIGITS}s\n" "$NUM_CONTAINER_SCANNED"
    printf "          updated: %${DIGITS}s\n" "$NUM_CONTAINER_UPDATED"
fi


#---------------------------------------------
# Prune images
#---------------------------------------------
if (( PRUNE_IMAGES )); then
    # verbose or non-quiet docker output
    if (( ! QUIET_DOCKER || VERBOSE )); then
        echo ""
        echo $SEPARATOR
        echo ""
        echo "Pruning unused images..."
    fi


    #---------------------------------------------
    # Perform pruning
    #---------------------------------------------
    if (( ! DRY_RUN )); then
        #---------------------------------------------
        # Execute pruning command (quiet) and catch the terminal output
        #---------------------------------------------
        OUTPUT=$(${FN_PRUNE_IMAGES[@]} 2>$SINKHOLE)


        #---------------------------------------------
        # Split output
        #---------------------------------------------
        # drop header and last line --> returns only list of deleted images
        LIST_DELETED_IMAGES=$(printf '%s\n' "$OUTPUT" | ${FN_DROP_HEADER[@]} | ${FN_DROP_FOOTER[@]})

        # get last line of output --> reclaimed space
        RECLAIMED_SPACE=$(printf '%s\n' "$OUTPUT" | ${FN_FETCH_FOOTER[@]}) 

        # count number of deleted images (count lines in LIST_DELETED_IMAGES, subtract 1 --> first line is plain text)
        NUM_DELETED_IMAGES=$(printf '%s\n' "$LIST_DELETED_IMAGES" | ${FN_COUNT_LINES[@]})
    else
        # dummy output in dry-run mode
        LIST_DELETED_IMAGES="dry-run, no images deleted."
        RECLAIMED_SPACE="Total reclaimed space: 0.0MB (dry-run)"
        NUM_DELETED_IMAGES="0 (dry-run)"
    fi


    #---------------------------------------------
    # Output results of pruning to terminal
    #---------------------------------------------
    if (( ! QUIET_DOCKER || VERBOSE )); then
        #---------------------------------------------
        # Non-quiet docker or verbose mode
        #---------------------------------------------
        # check if images have been deleted --> LIST_DELETED_IMAGES is empty if not
        if [[ -n $LIST_DELETED_IMAGES ]]; then
            # docker output: list of deleted images --> show only in non-quiet docker mode
            if (( ! QUIET_DOCKER )); then
                echo "$LIST_DELETED_IMAGES"
            fi

            # number of deleted images --> show only in verbose mode
            if (( VERBOSE )); then
                echo ""
                echo -e "Deleted images: ${COLOR_SUCCESS}$NUM_DELETED_IMAGES${COLOR_DEFAULT}" 
            fi

            # output reclaimed space --> show in both modes
            echo ""
            echo -e "${COLOR_SUCCESS}$RECLAIMED_SPACE${COLOR_DEFAULT}"
        else
            # output if empty pruning output from docker --> no images have been deleted
            echo ""
            echo -e "${COLOR_SUCCESS}No unused images found.${COLOR_DEFAULT}"
        fi
    else
        #---------------------------------------------
        # Quiet-docker and non-verbose mode
        #---------------------------------------------
        # space
        echo ""

        # print result
        if [[ -n $LIST_DELETED_IMAGES ]]; then
            # output if non-empty pruning output from docker --> images have been deleted
            echo "Deleted images: $NUM_DELETED_IMAGES"
            echo "$RECLAIMED_SPACE"
        else
            # output if empty pruning output from docker --> no images have been deleted
            echo "No unused images found."
        fi
    fi
fi


#---------------------------------------------
# Elapsed time
#---------------------------------------------
# get end time for time tracking
END_TIME=$(date +%s%N)

# convert to seconds
ELAPSED_TIME_s=$(awk "BEGIN {printf \"%.3f\", $(( END_TIME - START_TIME ))/1000000000}")

# output in verbose mode
if (( VERBOSE )); then
    # separator
    echo ""
    echo $SEPARATOR
    echo ""
    echo "Elapsed time: $ELAPSED_TIME_s seconds"
fi


#---------------------------------------------
# Exit
#---------------------------------------------
# final separator in non-quiet docker or verbose mode
if (( ! QUIET_DOCKER || VERBOSE )); then
    echo ""
    echo $SEPARATOR
    echo ""
fi

# exit successfully
exit 0