#!/usr/bin/env bash
# Draait een scanner-container met een KOPIE van de repository in /src.
#
# Waarom niet "docker run -v $PWD:/src"? De job-container en de Docker-daemon
# (Docker-in-Docker in de runner-pod) delen geen bestandssysteem. Een bind-mount
# van $PWD levert dan een LEGE map op, en de scan slaagt altijd ("0 files").
#
# Gebruik: scripts/scan.sh <image> <commando en argumenten...>
set -euo pipefail

name="scan-${GITHUB_RUN_ID:-local}-${RANDOM}"
docker create --name "$name" "$@" >/dev/null
docker cp . "$name:/src"
docker start -a "$name" || true
rc="$(docker inspect "$name" --format '{{.State.ExitCode}}')"
docker rm "$name" >/dev/null
exit "$rc"
