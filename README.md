# Docker Helper Scripts

A tiny collection of Bash utilities to manage Docker projects locally.
Both scripts (``docker-refresh.sh`` and ``docker-bake.sh``) operate on the current directory by default, or on a directory passed with ``-d``. 
They enforce execution as root (or via sudo) and provide minimal, clear output.


## Repository Structure
```
/root
 ├─ docker-refresh.sh   # Stop, remove, pull and restart containers
 ├─ docker-bake.sh      # Build images, tag them, and restart containers
 └─ README.md           # Documentation
```


## Usage

### docker-refresh.sh

```shell
# Run in the current folder
sudo ./docker-refresh.sh

# Or specify a folder
sudo ./docker-refresh.sh -d /path/to/project
```

Stops, removes, pulls, and recreates containers defined in docker-compose.yml.


### docker-bake.sh

```shell
# Build using the current folder name as repository, tag = today's date
sudo ./docker-bake.sh

# Custom directory, repository, or tag
sudo ./docker-bake.sh -d /path/to/project -r myrepo -t v1.2.3
```

Builds Docker images, tags them, and restarts the compose stack.


## Requirements
- Bash (standard on most Linux distributions)
- Docker Engine + Docker Compose plugin
- sudo privileges (the scripts abort if not run as root)


## Version history

| Major | Minor | Fix | Concerns | Note |
| ----- | ----- | --- | -------- | ---- |
|       |       | 1   | ``README.md`` | Removed non-ASCII characters from readme. |
| 2     | 0     | 0   | all | Added root-directory layout, sudo check, and refined usage messages. |
| 1     | 0     | 0   | all | initial working version. |
