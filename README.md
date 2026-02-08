# Docker Helper Scripts


A tiny collection of Bash utilities to manage Docker projects locally.
The scripts ``docker-refresh.sh`` and ``docker-bake.sh`` operate on the current directory by default, or on a directory passed with ``-d``.
The script ``docker-updater.sh`` can be executed in a safe dry-run with the ``-d``option.
All scripts display a help message with the ``-h``option.

They enforce execution as root (or via sudo) and provide minimal, clear output.


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


### docker-updater.sh

```shell
# Normal mode - update services that have newer images
sudo ./docker-updater.sh

# Dry-run mode - detect updates but do NOT restart services
sudo ./docker-updater.sh -d
```

1. Lists all compose services (docker compose ls --format table).
2. Uses the first path from the third column (handles comma‑separated lists).
3. Skips a service if a Dockerfile is present in its root folder.
4. Records current image IDs, pulls the latest images, records new IDs.
5. If any image digest changed, it runs docker compose up -d --force-recreate (unless -d dry‑run is set).
6. Prints only minimal log lines, e.g.
    - myservice: updated images --> repo1:tag1 repo2:tag2 or
    - myservice: up-to-date.



## Requirements
- Bash (standard on most Linux distributions)
- Docker Engine + Docker Compose plugin
- sudo privileges (the scripts abort if not run as root)


## Version history

| Major | Minor | Fix | Concerns | Note |
| ----- | ----- | --- | -------- | ---- |
|       | 1     | 0   | ``docker-updater.sh``, ``README.md`` | Added new script ``docker-updater.sh`` and adjusted the readme. |
|       |       | 1   | ``README.md`` | Removed non-ASCII characters from readme. |
| 2     | 0     | 0   | all | Added root-directory layout, sudo check, and refined usage messages. |
| 1     | 0     | 0   | all | initial working version. |
