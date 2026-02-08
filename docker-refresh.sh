#!/bin/bash

# help
USAGE="
Usage: $(basename $0) [-h] -d argument
  -h: help
  -d: directory path to docker files (relative to /server/docker)
"


############
# Variables
############
# root directory of docker files
ROOTDIR="/server/docker"


############
# get user provided options
############
while getopts ':hd:' OPTION; do
  case "$OPTION" in
    h) # echo help
      echo -e "$USAGE"
      exit 0
      ;;
    d) # read external config file
      SUBDIR=$OPTARG
      ;;
    ?)
      echo -e "$USAGE"
      exit 1
      ;;
  esac
done


############
# Change to Repository
############
# assemble full path
FULLDIR="$ROOTDIR/$SUBDIR"

# change to folder
cd "$FULLDIR"

# check for docker-compose
if [ -f "./docker-compose.yml" ]
then # file exists
    echo "found docker-compose.yml"
else # file does not exist
    echo "ERROR: no docker-compose.yml file found in repository at: $FULLDIR"
    exit 1
fi


############
# Execute Docker Commands
############
# stop and remove currently running docker container
docker compose stop
docker compose rm -f

# pull docker image
docker compose pull

# recreate docker container
docker compose up -d --force-recreate


############
# Exit Code
############
exit 0
