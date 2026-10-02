#!/bin/sh
docker run -it --rm -v "$(pwd)":/workspace -v opencode_config:/home/opencode/.config/opencode -v opencode_data:/home/opencode/.local/share/opencode -v opencode_state:/home/opencode/.local/state/opencode -v opencode_cache:/home/opencode/.cache/opencode --name opencode_fresh ghcr.io/anomalyco/opencode:2.0.22 "$@"
