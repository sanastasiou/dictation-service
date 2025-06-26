#!/bin/bash
# Microphone testing script

set -e

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

echo -e "${BLUE}=== Microphone Test Utility ===${NC}"
echo

# Function to list audio devices
list_devices() {
    echo -e "${CYAN}Available audio input devices:${NC}"
    echo "=============================="
    
    local i=1
    while IFS= read -r line; do
        if [[ $line =~ ^[[:space:]]*Name:[[:space:]](.+)$ ]]; then
            device_name="${BASH_REMATCH[1]}"
            if [[ ! $device_name =~ \.monitor$ ]]; then
                desc=$(pactl list sources | grep -A20 "Name: $device_name" | grep "Description:" | head -1 | sed 's/.*Description: //')
                echo -e "${GREEN}$i)${NC} $desc"
                echo "   Device: $device_name"
                ((i++))
            fi
        fi
    done < <(pactl list sources | grep "Name:")
}

# Function to test recording
test_recording() {
    local device="$1"
    local duration="${2:-3}"
    
    echo -e "${YELLOW}Recording for $duration seconds...${NC}"
    echo "Speak into your microphone now!"
    echo
    
    # Create temp file
    local temp_file="/tmp/mic-test-$(date +%s).wav"
    
    # Record audio
    if parecord --device="$device" --format=s16le --rate=16000 --channels=1 --latency-msec=10 -r "$temp_file" &
    then
        local record_pid=$!
        
        # Show level meter
        local end_time=$(($(date +%s) + duration))
        while [ $(date +%s) -lt $end_time ]; do
            if parecord --device="$device" --format=s16le --rate=16000 --channels=1 2>/dev/null | \
               dd bs=1024 count=1 2>/dev/null | \
               od -t d2 -N 1024 -v 2>/dev/null | \
               awk '{ for(i=2;i<=NF;i++) { sum+=$i<0?-$i:$i; n++ }} 
                    END { if(n>0) { avg=sum/n; 
                          bar=""; 
                          for(j=0;j<avg/500;j++) bar=bar"█"; 
                          printf "\rLevel: %-50s", bar }}'
            then
                :
            fi
            sleep 0.1
        done
        
        # Stop recording
        kill $record_pid 2>/dev/null
        wait $record_pid 2>/dev/null
        
        echo
        echo
        
        # Check if file has content
        if [ -f "$temp_file" ] && [ -s "$temp_file" ]; then
            local file_size=$(stat -c%s "$temp_file" 2>/dev/null || stat -f%z "$temp_file" 2>/dev/null)
            echo -e "${GREEN}Recording successful!${NC} (Size: $((file_size/1024))KB)"
            
            # Offer playback
            echo
            echo "Would you like to play back the recording? (Y/n)"
            read -n 1 -r
            echo
            if [[ ! $REPLY =~ ^[Nn]$ ]]; then
                echo "Playing back..."
                aplay "$temp_file" 2>/dev/null || paplay "$temp_file" 2>/dev/null
            fi
            
            # Cleanup
            rm -f "$temp_file"
            return 0
        else
            echo -e "${RED}Recording failed - no audio data captured${NC}"
            rm -f "$temp_file" 2>/dev/null
            return 1
        fi
    else
        echo -e "${RED}Failed to start recording${NC}"
        return 1
    fi
}

# Function to monitor levels
monitor_levels() {
    local device="$1"
    
    echo -e "${YELLOW}Monitoring microphone levels...${NC}"
    echo "Speak into your microphone (Press Ctrl+C to stop)"
    echo
    
    parecord --device="$device" --format=s16le --rate=16000 --channels=1 2>/dev/null | \
    while true; do
        dd bs=1024 count=1 2>/dev/null | \
        od -t d2 -N 1024 -v | \
        awk '{ for(i=2;i<=NF;i++) { sum+=$i<0?-$i:$i; n++ }} 
              END { if(n>0) { 
                    avg=sum/n; 
                    bar=""; 
                    for(j=0;j<avg/500;j++) bar=bar"█"; 
                    # Color based on level
                    if(avg > 5000) color="\033[0;31m";      # Red for high
                    else if(avg > 1000) color="\033[0;32m"; # Green for good
                    else if(avg > 100) color="\033[1;33m";  # Yellow for low
                    else color="\033[0;34m";                 # Blue for very low
                    printf "\r%sLevel: %-50s %5d\033[0m", color, bar, avg }}'
    done
}

# Main menu
main_menu() {
    while true; do
        echo
        echo -e "${CYAN}Microphone Test Menu:${NC}"
        echo "===================="
        echo "1) List audio devices"
        echo "2) Test recording (with config device)"
        echo "3) Test recording (select device)"
        echo "4) Monitor microphone levels"
        echo "5) Check audio system status"
        echo "6) Exit"
        echo
        read -p "Select option (1-6): " choice
        
        case $choice in
            1)
                echo
                list_devices
                ;;
            2)
                echo
                # Get device from config
                if [ -f ~/.config/mic-monitor/config.json ]; then
                    device_name=$(jq -r '.monitor_device' ~/.config/mic-monitor/config.json)
                    # Find actual device ID
                    device=$(pactl list sources | grep -B2 "Description:.*$device_name" | grep "Name:" | head -1 | awk '{print $2}')
                    if [ -n "$device" ]; then
                        echo "Using configured device: $device_name"
                        test_recording "$device"
                    else
                        echo -e "${RED}Configured device not found${NC}"
                    fi
                else
                    echo -e "${RED}No configuration found${NC}"
                fi
                ;;
            3)
                echo
                list_devices
                echo
                read -p "Enter device name (copy from above): " device
                if [ -n "$device" ]; then
                    test_recording "$device"
                fi
                ;;
            4)
                echo
                list_devices
                echo
                read -p "Enter device name to monitor: " device
                if [ -n "$device" ]; then
                    monitor_levels "$device"
                fi
                ;;
            5)
                echo
                echo -e "${CYAN}Audio System Status:${NC}"
                echo "==================="
                
                # Check PulseAudio
                if pactl info &>/dev/null; then
                    echo -e "PulseAudio: ${GREEN}Running${NC}"
                    pactl info | grep "Server Name:"
                    pactl info | grep "Default Source:"
                else
                    echo -e "PulseAudio: ${RED}Not running${NC}"
                fi
                
                # Count devices
                local source_count=$(pactl list sources | grep -c "Name:" || echo 0)
                echo -e "Audio sources found: ${GREEN}$source_count${NC}"
                ;;
            6)
                echo "Exiting..."
                exit 0
                ;;
            *)
                echo -e "${RED}Invalid option${NC}"
                ;;
        esac
    done
}

# Check if running with specific command
if [ "$1" = "list" ]; then
    list_devices
elif [ "$1" = "test" ] && [ -n "$2" ]; then
    test_recording "$2" "${3:-3}"
elif [ "$1" = "monitor" ] && [ -n "$2" ]; then
    monitor_levels "$2"
else
    main_menu
fi