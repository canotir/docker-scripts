#!/bin/bash

# help
USAGE="
Usage: $(basename $0) [-h] -d argument [-r argument] [-t argument]
  -h: help
  -d: directory path to docker files (relative to /server/docker)
  -r: name of docker repository
  -t: user defined docker image tag
"


############
# Variables
############
# root directory of docker files
ROOTDIR="/server/docker"

# default docker image tag
TAG=$(date +"%y.%m.%d")


############
# get user provided options
############
while getopts ':hd:r:t:' OPTION; do
  case "$OPTION" in
    h) # echo help
      echo -e "$USAGE"
      exit 0
      ;;
    d) # read external config file
      SUBDIR=$OPTARG
      ;;
    r) # read external config file
      REPO=$OPTARG
      ;;
    t) # read external config file
      TAG=$OPTARG
      ;;
    ?)
      echo -e "$USAGE"
      exit 1
      ;;
  esac
done

# set REPO name
if [ -n "$REPO" ]
then
    # info
    echo "docker repository is user-defined: $REPO"
else
    # SUBDIR does not exist and is set to SUBDIR
    REPO=$SUBDIR

    # info
    echo "docker repository is not defined, set to: $REPO"
fi


############
# Change to Repository
############
# assemble full path
FULLDIR="$ROOTDIR/$SUBDIR"

# change to folder
cd "$FULLDIR"

# check for dockerfile
if [ -f "./Dockerfile" ]
then # file exists
    echo "found dockerfile"
else # file does not exist
    echo "ERROR: no dockerfile found in repository at: $FULLDIR"
    exit 1
fi

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
# build new docker image
docker buildx build --no-cache -t "$REPO:$TAG" .
docker buildx build            -t "$REPO:latest" .

# stop and remove currently running docker container
docker compose stop
docker compose rm -f

# recreate docker container
docker compose up -d --force-recreate


############
# Exit Code
############
exit 0