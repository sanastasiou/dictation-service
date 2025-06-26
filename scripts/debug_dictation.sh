#!/bin/bash
# Debug script for dictation service issues

echo "=== DICTATION SERVICE DEBUG ==="
echo

echo "1. PATH CHECK:"
echo "Current PATH: $PATH"
echo "Checking for dictation command:"
which dictation || echo "NOT FOUND in PATH"
ls -la ~/.local/bin/dictation 2>/dev/null || echo "~/.local/bin/dictation does not exist"
echo

echo "2. SERVICE FILE CHECK:"
echo "Service file contents:"
cat ~/.config/systemd/user/dictation-service.service
echo

echo "3. PYTHON SCRIPT CHECK:"
echo "Checking if Python script exists:"
ls -la ~/.local/share/dictation-service/dictation-service.py
echo

echo "4. LOG FILES:"
echo "Recent logs:"
cat ~/.local/share/dictation-service/logs/dictation-service.log 2>/dev/null | tail -20
echo

echo "5. X11/DISPLAY CHECK:"
echo "DISPLAY: $DISPLAY"
echo "XAUTHORITY: $XAUTHORITY"
echo "Checking .Xauthority files:"
ls -la ~/.Xauthority 2>/dev/null || echo "~/.Xauthority not found"
ls -la /run/user/$(id -u)/gdm/Xauthority 2>/dev/null || echo "/run/user/$(id -u)/gdm/Xauthority not found"
echo "Checking Wayland auth files:"
ls -la /run/user/$(id -u)/.mutter-Xwaylandauth* 2>/dev/null || echo "No Wayland auth files found"
echo

echo "6. TESTING PYTHON SCRIPT DIRECTLY:"
cd ~
export DISPLAY=:0
# Try to find Wayland auth file
for auth in /run/user/$(id -u)/.mutter-Xwaylandauth*; do
    if [ -f "$auth" ]; then
        export XAUTHORITY="$auth"
        echo "Using XAUTHORITY: $auth"
        break
    fi
done
xhost +local: 2>/dev/null || echo "xhost failed (normal under Wayland)"
echo "Trying to run Python script directly:"
timeout 5 ~/miniconda3/envs/whisper/bin/python ~/.local/share/dictation-service/dictation-service.py 2>&1 | head -50
echo

echo "7. CONDA CHECK:"
echo "Conda environment:"
ls -la ~/miniconda3/envs/whisper/bin/python

echo "8. CONFIG FILE:"
cat ~/.config/dictation-service/config.json

echo "9. SYSTEMD SERVICE STATUS:"
systemctl --user status dictation-service --no-pager