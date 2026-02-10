# Docker Helper Scripts


A collection of utilities to manage Docker projects locally.


## Repository Structure
```
/root
 ├─ docker-refresh.sh   # Stop, remove, pull and restart containers
 ├─ docker-bake.sh      # Build images, tag them, and restart containers
 ├─ docker-updater.sh   # Update currently active docker services
 └─ README.md           # Documentation
```


## Usage

### docker-refresh.sh

Pulls the latest images for the current Compose project, stops and removes the running containers, and brings the stack back up with ``docker compose up -d --force-recreate``.
An optional ``-d DIR`` flag selects the target directory.

```shell
# Run in the current folder
sudo ./docker-refresh.sh

# Or specify a folder
sudo ./docker-refresh.sh -d /path/to/project
```


### docker-bake.sh

This script automates rebuilding and redeploying a Docker Compose service.
It lets you specify a target directory, repository name, and image tag (defaulting to the current date).
The script operates on the current directory by default.
After validating that a ``Dockerfile`` and ``docker-compose.yml`` exist and that the script is run as root, it builds a new image (both a dated tag and a latest tag) with ``docker buildx``.
Finally, it stops the existing containers, removes them, and brings the stack back up with the freshly built images using ``docker compose up -d --force-recreate``.

```shell
# Build using the current folder name as repository, tag = today's date
sudo ./docker-bake.sh

# Custom directory, repository, or tag
sudo ./docker-bake.sh -d /path/to/project -r myrepo -t v1.2.3
```

Builds Docker images, tags them, and restarts the compose stack.


### docker-updater.sh

This script scans all Docker Compose services on the host, checks each service's current image digests, pulls the latest images, and automatically restarts any services whose images have been updated.
It supports a dry-run mode to report out-of-date services without restarting, and a quiet mode to suppress command output.
The presence of a ``.docker-updater-ignore`` file in a service's directory tells the script to skip that service during update checks.

```shell
# Normal mode - update services that have newer images
sudo ./docker-updater.sh

# Dry-run mode - detect updates but do NOT restart services
sudo ./docker-updater.sh -d
```

See help message (``-h``) of script for all available options and usage.


## Requirements
- Bash (standard on most Linux distributions)
- Docker Engine + Docker Compose plugin
- sudo privileges (the scripts abort if not run as root)


## Version history

| Major | Minor | Fix | Concerns | Note |
| ----- | ----- | --- | -------- | ---- |
|       | 1     | 0   | all | Added new script ``docker-updater.sh``, adjusted the readme, and updated comments in all scripts. |
|       |       | 1   | ``README.md`` | Removed non-ASCII characters from readme. |
| 2     | 0     | 0   | all | Added root-directory layout, sudo check, and refined usage messages. |
| 1     | 0     | 0   | all | initial working version. |
