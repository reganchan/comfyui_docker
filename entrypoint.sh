#!/bin/bash
set -e

# If the mounted volume is empty, copy the pre-built environment into it
if [ -z "$(ls -A /home/comfy/python_env)" ]; then
    echo "Initializing persistent Python environment in host volume..."
    cp -r /home/comfy/python_env_base/. /home/comfy/python_env/
else
    echo "Using existing persistent Python environment from host volume."
fi

# Hand over execution to the main ComfyUI process
exec "$@"
