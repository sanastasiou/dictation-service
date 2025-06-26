#!/bin/bash
# Wrapper script to handle X11/Wayland authentication issues

# Set DISPLAY if not set
export DISPLAY="${DISPLAY:-:0}"

# Find the correct Xauthority file
if [ -n "$XAUTHORITY" ] && [ -f "$XAUTHORITY" ]; then
    # Use existing XAUTHORITY if valid
    true
elif [ -f "$HOME/.Xauthority" ]; then
    export XAUTHORITY="$HOME/.Xauthority"
elif [ -f "/run/user/$(id -u)/gdm/Xauthority" ]; then
    export XAUTHORITY="/run/user/$(id -u)/gdm/Xauthority"
else
    # Check for Wayland/Mutter auth files
    for auth in /run/user/$(id -u)/.mutter-Xwaylandauth*; do
        if [ -f "$auth" ]; then
            export XAUTHORITY="$auth"
            break
        fi
    done
fi

# If still no XAUTHORITY, unset it to allow X11 to work without auth
if [ ! -f "$XAUTHORITY" ]; then
    unset XAUTHORITY
fi

# Try to allow local connections (may fail under Wayland, that's OK)
xhost +local: >/dev/null 2>&1 || true

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Run the Python script with the correct Python from whisper environment
PYTHON_PATH="$HOME/miniconda3/envs/whisper/bin/python"
if [ ! -f "$PYTHON_PATH" ]; then
    # Fallback to anaconda3 if miniconda3 doesn't exist
    PYTHON_PATH="$HOME/anaconda3/envs/whisper/bin/python"
fi

exec "$PYTHON_PATH" "$SCRIPT_DIR/dictation-service.py" "$@"