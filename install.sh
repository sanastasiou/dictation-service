#!/bin/bash
# Dictation Service Complete Installer
# Interactive installation for speech-to-text dictation service

set -e  # Exit on error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m' # No Color

# Installation directories
INSTALL_BASE="$HOME/.local"
CONFIG_BASE="$HOME/.config"
LOG_FILE="/tmp/dictation-install-$(date +%Y%m%d-%H%M%S).log"
BACKUP_DIR="/tmp/dictation-backup-$(date +%Y%m%d-%H%M%S)"

# Default values
DEFAULT_MODEL_PATH="$HOME/whisper-models"
DEFAULT_CONDA_PATH="$HOME/miniconda3"

# Installation state tracking
INSTALLED_COMPONENTS=()
ORIGINAL_DIR="$(pwd)"
DICTATION_AUTO_START=false
PATH_UPDATE_NEEDED=false

# Logging functions
log() {
    echo -e "${GREEN}[$(date +'%H:%M:%S')]${NC} $1" | tee -a "$LOG_FILE"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1" | tee -a "$LOG_FILE"
    echo -e "${YELLOW}Check log file: $LOG_FILE${NC}"
    # Attempt rollback on error
    if [ ${#INSTALLED_COMPONENTS[@]} -gt 0 ]; then
        echo -e "${YELLOW}Attempting to rollback installation...${NC}"
        rollback_installation
    fi
    exit 1
}

warn() {
    echo -e "${YELLOW}[WARNING]${NC} $1" | tee -a "$LOG_FILE"
}

info() {
    echo -e "${BLUE}[INFO]${NC} $1" | tee -a "$LOG_FILE"
}

success() {
    echo -e "${GREEN}[✓]${NC} $1" | tee -a "$LOG_FILE"
}

# Progress indicator
show_progress() {
    local pid=$1
    local delay=0.1
    local spinstr='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏'
    echo -n " "
    while [ "$(ps a | awk '{print $1}' | grep $pid)" ]; do
        local temp=${spinstr#?}
        printf " [%c]  " "$spinstr"
        local spinstr=$temp${spinstr%"$temp"}
        sleep $delay
        printf "\b\b\b\b\b\b"
    done
    echo "    "
}

# Check if running as root
check_not_root() {
    if [ "$EUID" -eq 0 ]; then
        error "Please don't run this script as root. Run as normal user."
    fi
}

# Backup existing installation
backup_existing() {
    log "Checking for existing installation..."
    
    local need_backup=false
    local backup_items=()
    
    # Check what exists
    [ -d "$INSTALL_BASE/share/dictation-service" ] && { need_backup=true; backup_items+=("dictation-service"); }
    [ -d "$INSTALL_BASE/share/mic-monitor" ] && { need_backup=true; backup_items+=("mic-monitor"); }
    [ -d "$CONFIG_BASE/dictation-service" ] && { need_backup=true; backup_items+=("dictation-config"); }
    [ -d "$CONFIG_BASE/mic-monitor" ] && { need_backup=true; backup_items+=("mic-monitor-config"); }
    
    if [ "$need_backup" = true ]; then
        echo -e "${YELLOW}Found existing installation components:${NC}"
        printf '%s\n' "${backup_items[@]}"
        echo
        echo "Would you like to:"
        echo "1) Backup existing installation (recommended)"
        echo "2) Overwrite existing installation"
        echo "3) Cancel installation"
        read -p "Choice (1-3): " backup_choice
        
        case $backup_choice in
            1)
                log "Creating backup at $BACKUP_DIR..."
                mkdir -p "$BACKUP_DIR"
                
                # Backup components
                [ -d "$INSTALL_BASE/share/dictation-service" ] && cp -r "$INSTALL_BASE/share/dictation-service" "$BACKUP_DIR/"
                [ -d "$INSTALL_BASE/share/mic-monitor" ] && cp -r "$INSTALL_BASE/share/mic-monitor" "$BACKUP_DIR/"
                [ -d "$CONFIG_BASE/dictation-service" ] && cp -r "$CONFIG_BASE/dictation-service" "$BACKUP_DIR/"
                [ -d "$CONFIG_BASE/mic-monitor" ] && cp -r "$CONFIG_BASE/mic-monitor" "$BACKUP_DIR/"
                [ -f "$INSTALL_BASE/bin/dictation" ] && cp "$INSTALL_BASE/bin/dictation" "$BACKUP_DIR/"
                [ -f "$INSTALL_BASE/bin/mic-monitor" ] && cp "$INSTALL_BASE/bin/mic-monitor" "$BACKUP_DIR/"
                
                success "Backup created successfully"
                ;;
            2)
                warn "Proceeding with overwrite"
                ;;
            3)
                log "Installation cancelled by user"
                exit 0
                ;;
            *)
                error "Invalid choice"
                ;;
        esac
    fi
}

# Rollback installation on failure
rollback_installation() {
    warn "Rolling back installation..."
    
    for component in "${INSTALLED_COMPONENTS[@]}"; do
        case $component in
            "system-deps")
                info "System dependencies will remain installed"
                ;;
            "conda")
                info "Conda environment will remain (manually remove with: conda env remove -n whisper)"
                ;;
            "mic-monitor")
                systemctl --user stop mic-monitor.service 2>/dev/null || true
                systemctl --user disable mic-monitor.service 2>/dev/null || true
                rm -rf "$INSTALL_BASE/share/mic-monitor"
                rm -f "$INSTALL_BASE/bin/mic-monitor"
                rm -f "$CONFIG_BASE/systemd/user/mic-monitor.service"
                ;;
            "dictation-service")
                rm -rf "$INSTALL_BASE/share/dictation-service"
                rm -f "$INSTALL_BASE/bin/dictation"
                rm -f "$INSTALL_BASE/bin/arcrecord"
                ;;
            *)
                warn "Unknown component: $component"
                ;;
        esac
    done
    
    # Restore backup if exists
    if [ -d "$BACKUP_DIR" ]; then
        info "Restoring from backup..."
        [ -d "$BACKUP_DIR/dictation-service" ] && cp -r "$BACKUP_DIR/dictation-service" "$INSTALL_BASE/share/"
        [ -d "$BACKUP_DIR/mic-monitor" ] && cp -r "$BACKUP_DIR/mic-monitor" "$INSTALL_BASE/share/"
        [ -d "$BACKUP_DIR/dictation-config" ] && cp -r "$BACKUP_DIR/dictation-config" "$CONFIG_BASE/dictation-service"
        [ -d "$BACKUP_DIR/mic-monitor-config" ] && cp -r "$BACKUP_DIR/mic-monitor-config" "$CONFIG_BASE/mic-monitor"
        [ -f "$BACKUP_DIR/dictation" ] && cp "$BACKUP_DIR/dictation" "$INSTALL_BASE/bin/"
        [ -f "$BACKUP_DIR/mic-monitor" ] && cp "$BACKUP_DIR/mic-monitor" "$INSTALL_BASE/bin/"
        success "Backup restored"
    fi
}

# Welcome message
show_welcome() {
    clear
    echo -e "${BLUE}╔═══════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║       ${CYAN}Speech-to-Text Dictation Service Installer${BLUE}         ║${NC}"
    echo -e "${BLUE}╠═══════════════════════════════════════════════════════════╣${NC}"
    echo -e "${BLUE}║  This installer will set up:                              ║${NC}"
    echo -e "${BLUE}║  ${GREEN}•${BLUE} Microphone monitoring service                          ║${NC}"
    echo -e "${BLUE}║  ${GREEN}•${BLUE} GPU-accelerated speech recognition                     ║${NC}"
    echo -e "${BLUE}║  ${GREEN}•${BLUE} Whisper AI models for transcription                    ║${NC}"
    echo -e "${BLUE}║  ${GREEN}•${BLUE} All required dependencies                              ║${NC}"
    echo -e "${BLUE}╚═══════════════════════════════════════════════════════════╝${NC}"
    echo
    echo -e "${YELLOW}Requirements:${NC}"
    echo "  • Ubuntu/Debian-based Linux distribution"
    echo "  • Active internet connection"
    echo "  • ~4GB free disk space for models"
    echo "  • NVIDIA GPU (optional but recommended)"
    echo
    echo -e "${YELLOW}Installation log: $LOG_FILE${NC}"
    echo
    read -p "Press Enter to continue or Ctrl+C to cancel..."
}

# Check system requirements
check_system() {
    log "Checking system requirements..."
    
    # Check OS
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        info "Detected OS: $NAME $VERSION"
        
        if ! echo "$ID $ID_LIKE" | grep -qE "ubuntu|debian|mint|pop"; then
            warn "This installer is optimized for Ubuntu/Debian-based systems"
            echo "Your system: $NAME"
            echo "Installation may still work but some commands might need adjustment."
            read -p "Continue anyway? (y/N): " -n 1 -r
            echo
            if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                exit 1
            fi
        fi
    else
        warn "Could not detect OS. Assuming Ubuntu/Debian-based system."
    fi
    
    # Check architecture
    ARCH=$(uname -m)
    if [ "$ARCH" != "x86_64" ]; then
        error "This installer requires x86_64 architecture. Detected: $ARCH"
    fi
    
    # Check audio system
    if ! command -v pactl &> /dev/null; then
        warn "PulseAudio not found. Will install it as part of system dependencies."
    else
        success "PulseAudio detected"
    fi
    
    # Check GPU (optional)
    if command -v nvidia-smi &> /dev/null; then
        log "NVIDIA GPU detected:"
        nvidia-smi --query-gpu=name,memory.total,driver_version --format=csv,noheader | while read line; do
            info "  $line"
        done
        GPU_AVAILABLE=true
    else
        warn "No NVIDIA GPU detected. Will use CPU for transcription (slower)"
        echo "For best performance, an NVIDIA GPU with CUDA support is recommended."
        echo
        echo "Continue with CPU-only installation? (y/N): "
        read -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            exit 1
        fi
        GPU_AVAILABLE=false
    fi
    
    # Check available disk space
    AVAILABLE_SPACE=$(df -BG "$HOME" | awk 'NR==2 {print $4}' | sed 's/G//')
    if [ "$AVAILABLE_SPACE" -lt 4 ]; then
        warn "Low disk space detected: ${AVAILABLE_SPACE}GB available"
        echo "At least 4GB is recommended for model storage."
        read -p "Continue anyway? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            exit 1
        fi
    else
        success "Sufficient disk space: ${AVAILABLE_SPACE}GB available"
    fi
}

# Install system dependencies
install_system_deps() {
    log "Installing system dependencies..."
    
    # Detect package manager
    if command -v apt-get &> /dev/null; then
        PKG_MANAGER="apt"
        PKG_INSTALL="apt-get install -y"
        PKG_UPDATE="apt-get update"
    elif command -v dnf &> /dev/null; then
        PKG_MANAGER="dnf"
        PKG_INSTALL="dnf install -y"
        PKG_UPDATE="dnf check-update"
    elif command -v yum &> /dev/null; then
        PKG_MANAGER="yum"
        PKG_INSTALL="yum install -y"
        PKG_UPDATE="yum check-update"
    else
        error "No supported package manager found (apt, dnf, or yum)"
    fi
    
    local packages=(
        # Audio
        "pulseaudio"
        "pulseaudio-utils"
        "portaudio19-dev"
        "ffmpeg"
        
        # Python build
        "python3-dev"
        "python3-pip"
        "python3-venv"
        
        # GUI dependencies
        "python3-tk"
        "yad"
        "libnotify-bin"
        
        # Build tools
        "build-essential"
        "cmake"
        "git"
        "curl"
        "wget"
        "jq"
        "bc"
    )
    
    # Adjust package names for non-debian systems
    if [ "$PKG_MANAGER" != "apt" ]; then
        # Map debian package names to fedora/rhel equivalents
        packages=(
            "pulseaudio"
            "pulseaudio-utils"
            "portaudio-devel"
            "python3-devel"
            "python3-pip"
            "python3-tkinter"
            "yad"
            "libnotify"
            "gcc"
            "gcc-c++"
            "make"
            "cmake"
            "git"
            "curl"
            "wget"
            "jq"
            "bc"
        )
    fi
    
    echo "The installer needs to install some system packages."
    echo "You'll be prompted for your password."
    echo
    echo "Packages to install:"
    printf '%s ' "${packages[@]}"
    echo
    echo
    read -p "Continue? (Y/n): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Nn]$ ]]; then
        error "System dependency installation cancelled"
    fi
    
    # Update package list
    info "Updating package list..."
    sudo $PKG_UPDATE || warn "Package update had issues but continuing..."
    
    # Install packages
    info "Installing packages..."
    sudo $PKG_INSTALL "${packages[@]}" || error "Failed to install system packages"
    
    INSTALLED_COMPONENTS+=("system-deps")
    success "System dependencies installed successfully"
}

# Install Miniconda
install_conda() {
    log "Setting up Python environment..."
    
    # Check if conda already exists
    if command -v conda &> /dev/null; then
        log "Conda already installed"
        CONDA_PATH=$(conda info --base)
        
        # Check if whisper environment exists
        if conda env list | grep -q "^whisper "; then
            warn "Whisper conda environment already exists"
            echo "Would you like to:"
            echo "1) Use existing environment"
            echo "2) Remove and recreate environment"
            echo "3) Cancel installation"
            read -p "Choice (1-3): " env_choice
            
            case $env_choice in
                1)
                    info "Using existing whisper environment"
                    return 0
                    ;;
                2)
                    info "Removing existing whisper environment..."
                    conda env remove -n whisper -y
                    ;;
                3)
                    error "Installation cancelled by user"
                    ;;
                *)
                    error "Invalid choice"
                    ;;
            esac
        fi
    else
        echo
        echo "Conda is required for managing Python environments."
        echo "Where would you like to install Miniconda?"
        echo "Default: $DEFAULT_CONDA_PATH"
        echo "(Press Enter for default or type a custom path)"
        read -p "> " CONDA_CUSTOM_PATH
        
        CONDA_PATH=${CONDA_CUSTOM_PATH:-$DEFAULT_CONDA_PATH}
        
        # Check if directory exists
        if [ -d "$CONDA_PATH" ]; then
            warn "Directory $CONDA_PATH already exists"
            read -p "Continue anyway? (y/N): " -n 1 -r
            echo
            if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                error "Installation cancelled"
            fi
        fi
        
        log "Installing Miniconda to $CONDA_PATH..."
        
        # Download Miniconda
        info "Downloading Miniconda installer..."
        wget -q --show-progress https://repo.anaconda.com/miniconda/Miniconda3-latest-Linux-x86_64.sh -O /tmp/miniconda.sh || error "Failed to download Miniconda"
        
        # Install Miniconda
        info "Installing Miniconda..."
        bash /tmp/miniconda.sh -b -p "$CONDA_PATH" || error "Failed to install Miniconda"
        rm /tmp/miniconda.sh
        
        # Initialize conda for bash
        "$CONDA_PATH/bin/conda" init bash || error "Failed to initialize conda"
        
        success "Miniconda installed successfully"
    fi
    
    # Source conda
    source "$CONDA_PATH/etc/profile.d/conda.sh" || error "Failed to source conda"
}

# Create conda environment
setup_conda_env() {
    log "Creating whisper conda environment..."
    
    # Create environment
    conda create -n whisper python=3.10 -y || warn "Environment might already exist"
    
    # Activate environment
    conda activate whisper || error "Failed to activate whisper environment"
    
    log "Installing Python packages..."
    echo "This may take several minutes..."
    
    # Determine CUDA version for PyTorch
    if [ "$GPU_AVAILABLE" = true ]; then
        # Try to detect CUDA version
        if command -v nvcc &> /dev/null; then
            CUDA_VERSION=$(nvcc --version | grep "release" | sed -n 's/.*release \([0-9]\+\.[0-9]\+\).*/\1/p')
            info "Detected CUDA version: $CUDA_VERSION"
        else
            CUDA_VERSION="12.1"  # Default to latest
            info "Using default CUDA version: $CUDA_VERSION"
        fi
        
        # Install PyTorch with CUDA
        log "Installing PyTorch with CUDA support..."
        if [[ "$CUDA_VERSION" == "11."* ]]; then
            pip install torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cu118 || error "Failed to install PyTorch"
        else
            pip install torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cu121 || error "Failed to install PyTorch"
        fi
    else
        log "Installing PyTorch (CPU only)..."
        pip install torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cpu || error "Failed to install PyTorch"
    fi
    
    # Install other dependencies
    log "Installing additional Python packages..."
    pip install openai-whisper pyautogui scipy numpy || error "Failed to install Python packages"
    
    # Try to install faster-whisper (optional)
    if [ "$GPU_AVAILABLE" = true ]; then
        log "Installing faster-whisper with GPU support..."
        pip install faster-whisper || warn "Faster-whisper installation failed (optional)"
        
        # Install cuDNN for faster-whisper
        log "Installing cuDNN libraries..."
        conda install -c conda-forge cudnn -y || warn "cuDNN installation failed (optional)"
    else
        log "Installing faster-whisper (CPU optimized)..."
        pip install faster-whisper || warn "Faster-whisper installation failed (optional)"
    fi
    
    INSTALLED_COMPONENTS+=("conda")
    success "Python environment setup complete"
}

# Select audio device
select_audio_device() {
    log "Detecting audio input devices..."
    
    echo
    echo -e "${CYAN}Available microphones:${NC}"
    echo "====================="
    
    # Get list of audio sources
    local devices=()
    local device_names=()
    local i=1
    
    # Save and restore IFS
    local OLD_IFS=$IFS
    IFS=$'\n'
    
    # Get all audio sources
    while read -r line; do
        if [[ $line =~ ^[[:space:]]*Name:[[:space:]](.+)$ ]]; then
            device_name="${BASH_REMATCH[1]}"
            # Skip monitor devices
            if [[ ! $device_name =~ \.monitor$ ]]; then
                devices+=("$device_name")
                # Get description for this device
                desc=$(pactl list sources | grep -A20 "Name: $device_name" | grep "Description:" | head -1 | sed 's/.*Description: //')
                if [ -z "$desc" ]; then
                    desc="$device_name"
                fi
                device_names+=("$desc")
                echo -e "${GREEN}$i)${NC} $desc"
                if [[ $device_name =~ alsa_input ]]; then
                    echo "   Device: $device_name"
                fi
                ((i++))
            fi
        fi
    done < <(pactl list sources | grep "Name:")
    
    IFS=$OLD_IFS
    
    if [ ${#devices[@]} -eq 0 ]; then
        error "No audio input devices found!"
    fi
    
    echo
    echo -e "${YELLOW}Select your microphone (1-$((i-1))):${NC}"
    echo "(Choose the microphone you'll use for dictation)"
    read -p "> " device_choice
    
    if [[ $device_choice -ge 1 && $device_choice -lt $i ]]; then
        SELECTED_DEVICE="${devices[$((device_choice-1))]}"
        SELECTED_DEVICE_NAME="${device_names[$((device_choice-1))]}"
        success "Selected device: $SELECTED_DEVICE_NAME"
        info "Device ID: $SELECTED_DEVICE"
        
        # Test microphone
        echo
        echo "Would you like to test this microphone? (Y/n)"
        read -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Nn]$ ]]; then
            test_microphone "$SELECTED_DEVICE"
        fi
    else
        error "Invalid selection"
    fi
}

# Test microphone
test_microphone() {
    local device=$1
    log "Testing microphone..."
    echo "Speak into your microphone for 3 seconds..."
    echo "(You should see the level meter moving)"
    echo
    
    # Test if parec works with this device
    if ! parec --device=$device --format=s16le --rate=16000 --channels=1 2>/dev/null | head -c 1 >/dev/null 2>&1; then
        warn "Could not access microphone device"
        echo "This might be normal in a VM or with certain audio configurations."
        echo
        echo "Continue anyway? (Y/n)"
        read -n 1 -r
        echo
        if [[ $REPLY =~ ^[Nn]$ ]]; then
            error "Installation cancelled due to microphone access issues"
        fi
        return
    fi
    
    # Record and show levels with better error handling
    (
        timeout 3 bash -c "parec --device=$device --format=s16le --rate=16000 --channels=1 2>/dev/null | \
            while true; do
                dd bs=1024 count=1 2>/dev/null | \
                od -t d2 -N 1024 -v | \
                awk '{ for(i=2;i<=NF;i++) { sum+=\$i<0?-\$i:\$i; n++ }} \
                    END { avg=n?sum/n:0; \
                          bar=\"\"; \
                          for(j=0;j<avg/500;j++) bar=bar\"█\"; \
                          printf \"\rLevel: %-50s\", bar }'
            done" || true
    )
    
    echo
    echo
    echo "Did you see the level meter moving when you spoke? (Y/n)"
    read -n 1 -r
    echo
    if [[ $REPLY =~ ^[Nn]$ ]]; then
        warn "Microphone test failed. You may need to:"
        echo "  • Check your microphone connection"
        echo "  • Adjust microphone permissions in system settings"
        echo "  • Try a different microphone"
        echo
        echo "Continue anyway? (y/N)"
        read -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            error "Installation cancelled due to microphone issues"
        fi
    else
        success "Microphone test passed!"
    fi
}

# Install mic-monitor service
install_mic_monitor() {
    log "Installing mic-monitor service..."
    
    # Create directories
    mkdir -p "$INSTALL_BASE/share/mic-monitor/logs"
    mkdir -p "$CONFIG_BASE/mic-monitor"
    mkdir -p "$CONFIG_BASE/systemd/user"
    mkdir -p "$INSTALL_BASE/bin"
    
    # Copy mic-monitor script
    cp src/mic-monitor.py "$INSTALL_BASE/share/mic-monitor/" || error "mic-monitor.py not found in bundle"
    chmod +x "$INSTALL_BASE/share/mic-monitor/mic-monitor.py"
    
    # Create configuration
    cat > "$CONFIG_BASE/mic-monitor/config.json" << EOF
{
    "check_interval": 0.5,
    "indicator_type": "tray",
    "show_app_name": true,
    "log_activity": false,
    "position": "top-right",
    "monitor_all_devices": false,
    "monitor_device": "$SELECTED_DEVICE_NAME",
    "ignore_devices": ["Monitor of", "QuickCam"]
}
EOF
    
    # Install control script
    cp bin/mic-monitor "$INSTALL_BASE/bin/" || error "mic-monitor control script not found"
    chmod +x "$INSTALL_BASE/bin/mic-monitor"
    
    # Update paths in control script
    sed -i "s|~/.local/share/mic-monitor/mic-monitor.py|$INSTALL_BASE/share/mic-monitor/mic-monitor.py|g" \
        "$INSTALL_BASE/bin/mic-monitor"
    
    # Install systemd service
    cp config/systemd/mic-monitor.service "$CONFIG_BASE/systemd/user/" || error "mic-monitor.service not found"
    
    # Update paths in service file
    sed -i "s|%h/.local/share/mic-monitor/mic-monitor.py|$INSTALL_BASE/share/mic-monitor/mic-monitor.py|g" \
        "$CONFIG_BASE/systemd/user/mic-monitor.service"
    
    # Reload systemd
    systemctl --user daemon-reload
    
    # Ask about auto-start
    echo
    echo "Would you like mic-monitor to start automatically on login? (Y/n)"
    read -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Nn]$ ]]; then
        systemctl --user enable mic-monitor.service
        success "Mic-monitor will start automatically on login"
    else
        info "You can enable auto-start later with: systemctl --user enable mic-monitor.service"
    fi
    
    INSTALLED_COMPONENTS+=("mic-monitor")
    success "Mic-monitor service installed"
}

# Install dictation service
install_dictation_service() {
    log "Installing dictation service..."
    
    # Create directories
    mkdir -p "$INSTALL_BASE/share/dictation-service/logs"
    mkdir -p "$CONFIG_BASE/dictation-service"
    
    # Copy dictation script
    cp src/dictation-service.py "$INSTALL_BASE/share/dictation-service/" || error "dictation-service.py not found"
    chmod +x "$INSTALL_BASE/share/dictation-service/dictation-service.py"
    
    # Copy arcrecord script
    cp bin/arcrecord "$INSTALL_BASE/bin/" || error "arcrecord script not found"
    chmod +x "$INSTALL_BASE/bin/arcrecord"
    
    # Update device in arcrecord script
    # Set environment variable in the script
    sed -i "2i AUDIO_DEVICE=\"$SELECTED_DEVICE\"" "$INSTALL_BASE/bin/arcrecord"
    
    # Install control script
    cp bin/dictation "$INSTALL_BASE/bin/" || error "dictation control script not found"
    chmod +x "$INSTALL_BASE/bin/dictation"
    
    # Update paths in control script
    sed -i "s|~/.local/share/dictation-service/dictation-service.py|$INSTALL_BASE/share/dictation-service/dictation-service.py|g" \
        "$INSTALL_BASE/bin/dictation"
    sed -i "s|~/anaconda3|$CONDA_PATH|g" "$INSTALL_BASE/bin/dictation"
    sed -i "s|~/miniconda3|$CONDA_PATH|g" "$INSTALL_BASE/bin/dictation"
    
    # Install systemd service
    cp config/systemd/dictation-service.service "$CONFIG_BASE/systemd/user/" || error "dictation-service.service not found"
    
    # Update paths in service file - replace %h with actual home directory
    sed -i "s|%h|$HOME|g" "$CONFIG_BASE/systemd/user/dictation-service.service"
    sed -i "s|$HOME/miniconda3|$CONDA_PATH|g" "$CONFIG_BASE/systemd/user/dictation-service.service"
    
    # Reload systemd
    systemctl --user daemon-reload
    
    # Ask about auto-start
    echo
    echo "Would you like the dictation service to start automatically on login? (Y/n)"
    read -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Nn]$ ]]; then
        systemctl --user enable dictation-service.service
        success "Dictation service will start automatically on login"
        DICTATION_AUTO_START=true
        
        # Also start it now
        echo
        echo "Would you like to start the dictation service now? (Y/n)"
        read -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Nn]$ ]]; then
            systemctl --user start dictation-service
            if systemctl --user is-active --quiet dictation-service; then
                success "Dictation service is now running"
            else
                warn "Could not start service. Check logs after installation."
            fi
        fi
    else
        info "You can enable auto-start later with: systemctl --user enable dictation-service"
        DICTATION_AUTO_START=false
    fi
    
    # Device will be configured in config.json instead of hardcoded
    
    INSTALLED_COMPONENTS+=("dictation-service")
    success "Dictation service installed"
}

# Download Whisper models
download_models() {
    log "Setting up Whisper models..."
    
    echo
    echo "Where would you like to store the Whisper models?"
    echo "These files can be quite large (1-3 GB each)"
    echo "Default: $DEFAULT_MODEL_PATH"
    echo "(Press Enter for default or type a custom path)"
    read -p "> " MODEL_CUSTOM_PATH
    
    MODEL_PATH=${MODEL_CUSTOM_PATH:-$DEFAULT_MODEL_PATH}
    
    # Expand tilde
    MODEL_PATH="${MODEL_PATH/#\~/$HOME}"
    
    # Create directory
    mkdir -p "$MODEL_PATH" || error "Failed to create model directory"
    
    # Copy model download script
    cp scripts/download_whisper_models.sh "$MODEL_PATH/" || error "download_whisper_models.sh not found"
    chmod +x "$MODEL_PATH/download_whisper_models.sh"
    
    # Update base directory in script
    sed -i "s|BASE_DIR=.*|BASE_DIR=\"$MODEL_PATH\"|g" "$MODEL_PATH/download_whisper_models.sh"
    
    echo
    echo -e "${CYAN}Available Whisper Models:${NC}"
    echo "════════════════════════"
    echo
    echo -e "${GREEN}Recommended Models:${NC}"
    echo "1) large-v3-turbo (809M) - Best balance of speed and accuracy ⭐"
    echo "2) large-v3 (1.5GB) - Best accuracy"
    echo
    echo -e "${YELLOW}Other Models:${NC}"
    echo "3) medium (769M) - Good balance"
    echo "4) small (244M) - Faster, decent accuracy"
    echo "5) base (74M) - Fast, basic accuracy"
    echo "6) tiny (39M) - Very fast, limited accuracy"
    echo
    echo "7) Skip download (configure later)"
    echo
    echo -e "${CYAN}Select model to download (1-7):${NC}"
    read -p "> " model_choice
    
    cd "$MODEL_PATH"
    
    case $model_choice in
        1)
            log "Downloading large-v3-turbo model (recommended)..."
            ./download_whisper_models.sh openai large-v3-turbo || warn "Model download failed"
            WHISPER_MODEL="large-v3-turbo"
            USE_FASTER_WHISPER="false"
            ;;
        2)
            log "Downloading large-v3 model..."
            # Ask which implementation
            echo "Which implementation would you like?"
            echo "1) OpenAI Whisper (original)"
            echo "2) Faster Whisper (optimized)"
            read -p "> " impl_choice
            if [ "$impl_choice" = "2" ]; then
                ./download_whisper_models.sh faster large-v3 || warn "Model download failed"
                USE_FASTER_WHISPER="true"
            else
                ./download_whisper_models.sh openai large-v3 || warn "Model download failed"
                USE_FASTER_WHISPER="false"
            fi
            WHISPER_MODEL="large-v3"
            ;;
        3)
            log "Downloading medium model..."
            ./download_whisper_models.sh openai medium || warn "Model download failed"
            WHISPER_MODEL="medium"
            USE_FASTER_WHISPER="false"
            ;;
        4)
            log "Downloading small model..."
            ./download_whisper_models.sh openai small || warn "Model download failed"
            WHISPER_MODEL="small"
            USE_FASTER_WHISPER="false"
            ;;
        5)
            log "Downloading base model..."
            ./download_whisper_models.sh openai base || warn "Model download failed"
            WHISPER_MODEL="base"
            USE_FASTER_WHISPER="false"
            ;;
        6)
            log "Downloading tiny model..."
            ./download_whisper_models.sh openai tiny || warn "Model download failed"
            WHISPER_MODEL="tiny"
            USE_FASTER_WHISPER="false"
            ;;
        7)
            log "Skipping model download"
            warn "You'll need to download models manually before using the service"
            WHISPER_MODEL="base"
            USE_FASTER_WHISPER="false"
            ;;
        *)
            warn "Invalid selection, skipping download"
            WHISPER_MODEL="base"
            USE_FASTER_WHISPER="false"
            ;;
    esac
    
    cd "$ORIGINAL_DIR"
}

# Configure dictation service
configure_dictation() {
    log "Configuring dictation service..."
    
    # Language selection
    echo
    echo -e "${CYAN}Select transcription language:${NC}"
    echo "1) Auto-detect (multilingual)"
    echo "2) English"
    echo "3) Spanish"
    echo "4) French"
    echo "5) German"
    echo "6) Italian"
    echo "7) Portuguese"
    echo "8) Russian"
    echo "9) Chinese"
    echo "10) Japanese"
    echo "11) Other (specify)"
    echo
    read -p "Select language (1-11): " lang_choice
    
    case $lang_choice in
        1) LANGUAGE="null" ;;
        2) LANGUAGE="en" ;;
        3) LANGUAGE="es" ;;
        4) LANGUAGE="fr" ;;
        5) LANGUAGE="de" ;;
        6) LANGUAGE="it" ;;
        7) LANGUAGE="pt" ;;
        8) LANGUAGE="ru" ;;
        9) LANGUAGE="zh" ;;
        10) LANGUAGE="ja" ;;
        11)
            echo "Enter language code (e.g., 'ko' for Korean, 'ar' for Arabic):"
            read -p "> " LANGUAGE
            ;;
        *) LANGUAGE="null" ;;
    esac
    
    # Advanced settings
    echo
    echo "Configure advanced settings? (y/N)"
    read -n 1 -r
    echo
    
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        echo
        echo -e "${CYAN}Voice Activity Detection:${NC}"
        echo "1) High sensitivity (picks up quiet speech)"
        echo "2) Normal sensitivity (default)"
        echo "3) Low sensitivity (requires louder speech)"
        read -p "Select (1-3): " vad_choice
        
        case $vad_choice in
            1)
                SILENCE_THRESHOLD="0.01"
                SILENCE_DURATION="0.8"
                ;;
            3)
                SILENCE_THRESHOLD="0.04"
                SILENCE_DURATION="1.5"
                ;;
            *)
                SILENCE_THRESHOLD="0.02"
                SILENCE_DURATION="1.0"
                ;;
        esac
        
        echo
        echo -e "${CYAN}Processing Quality:${NC}"
        echo "1) Maximum quality (slower)"
        echo "2) Balanced (default)"
        echo "3) Fast (lower quality)"
        read -p "Select (1-3): " quality_choice
        
        case $quality_choice in
            1)
                BEAM_SIZE="10"
                BEST_OF="10"
                ;;
            3)
                BEAM_SIZE="1"
                BEST_OF="1"
                ;;
            *)
                BEAM_SIZE="5"
                BEST_OF="5"
                ;;
        esac
    else
        # Use defaults
        SILENCE_THRESHOLD="0.02"
        SILENCE_DURATION="1.0"
        BEAM_SIZE="5"
        BEST_OF="5"
    fi
    
    # Use GPU?
    USE_GPU="true"
    if [ "$GPU_AVAILABLE" = false ]; then
        USE_GPU="false"
    fi
    
    # Create configuration
    cat > "$CONFIG_BASE/dictation-service/config.json" << EOF
{
    "audio_device": "$SELECTED_DEVICE",
    "silence_threshold": $SILENCE_THRESHOLD,
    "silence_duration": $SILENCE_DURATION,
    "min_speech_duration": 0.3,
    "pre_record_seconds": 0.5,
    "whisper_model": "$WHISPER_MODEL",
    "use_faster_whisper": $USE_FASTER_WHISPER,
    "model_base_path": "$MODEL_PATH",
    "language": $([ "$LANGUAGE" = "null" ] && echo "null" || echo "\"$LANGUAGE\""),
    "auto_punctuation": true,
    "noise_suppression": true,
    "high_pass_freq": 80,
    "debug_audio": false,
    "use_gpu": $USE_GPU,
    "fp16": true,
    "beam_size": $BEAM_SIZE,
    "best_of": $BEST_OF,
    "compute_type": "float16"
}
EOF
    
    success "Configuration complete"
}

# Test installation
test_installation() {
    log "Testing installation..."
    
    echo
    echo "Starting services for testing..."
    
    # Start mic-monitor
    systemctl --user start mic-monitor.service
    sleep 2
    
    if systemctl --user is-active --quiet mic-monitor.service; then
        success "Mic-monitor service is running"
        echo "You should see a microphone icon in your system tray when recording"
    else
        warn "Mic-monitor service failed to start"
        echo "Check logs with: journalctl --user -u mic-monitor.service"
    fi
    
    # Add to PATH if needed
    if [[ ":$PATH:" != *":$INSTALL_BASE/bin:"* ]]; then
        echo
        warn "The installation directory is not in your PATH"
        echo "Add the following line to your ~/.bashrc:"
        echo "export PATH=\"\$PATH:$INSTALL_BASE/bin\""
        echo
        echo "Would you like me to add it now? (Y/n)"
        read -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Nn]$ ]]; then
            echo "export PATH=\"\$PATH:$INSTALL_BASE/bin\"" >> ~/.bashrc
            export PATH="$PATH:$INSTALL_BASE/bin"
            success "PATH updated"
        fi
    fi
    
    echo
    echo "Would you like to test the dictation service now?"
    echo "This will:"
    echo "  • Start recording from your microphone"
    echo "  • Transcribe your speech using Whisper"
    echo "  • Type the text where your cursor is"
    echo
    read -p "Test dictation? (y/N): " -n 1 -r
    echo
    
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        log "Starting dictation test..."
        echo
        echo "Instructions:"
        echo "1. Click where you want the text to appear (like a text editor)"
        echo "2. Speak clearly into your microphone"
        echo "3. Pause for 1 second when done speaking"
        echo "4. The text will appear where your cursor is"
        echo "5. Press Ctrl+C to stop the test"
        echo
        echo "Starting in 5 seconds..."
        sleep 5
        
        # Activate conda environment and run test
        source "$CONDA_PATH/etc/profile.d/conda.sh"
        conda activate whisper
        
        # Run for 30 seconds or until Ctrl+C
        timeout 30 "$INSTALL_BASE/bin/dictation" test || true
        
        echo
        echo "Test complete. Did the transcription work correctly? (Y/n)"
        read -n 1 -r
        echo
        if [[ $REPLY =~ ^[Nn]$ ]]; then
            warn "If transcription didn't work, check:"
            echo "  • Microphone is working (test with 'parecord')"
            echo "  • Models are downloaded correctly"
            echo "  • GPU drivers are installed (if using GPU)"
            echo "  • Check logs: dictation logs"
        else
            success "Dictation service is working correctly!"
        fi
    fi
}

# Create desktop shortcuts
create_shortcuts() {
    log "Creating desktop shortcuts..."
    
    local desktop_dir="$HOME/Desktop"
    if [ ! -d "$desktop_dir" ]; then
        desktop_dir="$(xdg-user-dir DESKTOP 2>/dev/null || echo "$HOME/Desktop")"
    fi
    
    if [ -d "$desktop_dir" ]; then
        echo "Would you like desktop shortcuts for easy access? (Y/n)"
        read -n 1 -r
        echo
        
        if [[ ! $REPLY =~ ^[Nn]$ ]]; then
            # Dictation toggle shortcut
            cat > "$desktop_dir/dictation-toggle.desktop" << EOF
[Desktop Entry]
Version=1.0
Type=Application
Name=Toggle Dictation
Comment=Start/Stop speech-to-text dictation
Exec=$INSTALL_BASE/bin/dictation toggle
Icon=audio-input-microphone
Terminal=false
Categories=Utility;Audio;
EOF
            chmod +x "$desktop_dir/dictation-toggle.desktop"
            
            # Dictation settings shortcut
            cat > "$desktop_dir/dictation-settings.desktop" << EOF
[Desktop Entry]
Version=1.0
Type=Application
Name=Dictation Settings
Comment=Configure dictation service
Exec=xdg-open $CONFIG_BASE/dictation-service/config.json
Icon=preferences-system
Terminal=false
Categories=Settings;
EOF
            chmod +x "$desktop_dir/dictation-settings.desktop"
            
            success "Desktop shortcuts created"
        fi
    else
        info "Desktop directory not found, skipping shortcuts"
    fi
}

# Create uninstaller
create_uninstaller() {
    log "Creating uninstaller..."
    
    cat > "$INSTALL_BASE/bin/dictation-uninstall" << 'EOF'
#!/bin/bash
# Dictation Service Uninstaller

echo "This will remove the dictation service and mic-monitor."
echo "Your Whisper models and conda environment will be preserved."
echo
read -p "Continue? (y/N): " -n 1 -r
echo

if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    exit 1
fi

echo "Stopping services..."
systemctl --user stop mic-monitor.service 2>/dev/null
systemctl --user disable mic-monitor.service 2>/dev/null

# Kill any running dictation processes
pkill -f dictation-service.py 2>/dev/null
pkill -f parecord 2>/dev/null

echo "Removing files..."
rm -rf ~/.local/share/mic-monitor
rm -rf ~/.local/share/dictation-service
rm -f ~/.local/bin/mic-monitor
rm -f ~/.local/bin/dictation
rm -f ~/.local/bin/arcrecord
rm -f ~/.local/bin/dictation-uninstall
rm -rf ~/.config/mic-monitor
rm -rf ~/.config/dictation-service
rm -f ~/.config/systemd/user/mic-monitor.service
rm -f ~/Desktop/dictation-toggle.desktop
rm -f ~/Desktop/dictation-settings.desktop

# Clean up temp files
rm -f /tmp/dictation-*
rm -f /tmp/mic-*

echo "Uninstallation complete."
echo
echo "Note: The following were preserved:"
echo "  • Whisper models (remove manually if needed)"
echo "  • Conda environment (remove with: conda env remove -n whisper)"
echo "  • System packages (remove with your package manager if needed)"
EOF
    
    chmod +x "$INSTALL_BASE/bin/dictation-uninstall"
}

# Configure shell PATH
configure_shell_path() {
    log "Configuring shell PATH..."
    
    # Check if ~/.local/bin is already in PATH
    if [[ ":$PATH:" != *":$HOME/.local/bin:"* ]]; then
        # Add to .bashrc if it exists
        if [ -f "$HOME/.bashrc" ]; then
            echo "" >> "$HOME/.bashrc"
            echo "# Added by dictation-service installer" >> "$HOME/.bashrc"
            echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$HOME/.bashrc"
            info "Added ~/.local/bin to PATH in .bashrc"
        fi
        
        # Add to .zshrc if it exists
        if [ -f "$HOME/.zshrc" ]; then
            echo "" >> "$HOME/.zshrc"
            echo "# Added by dictation-service installer" >> "$HOME/.zshrc"
            echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$HOME/.zshrc"
            info "Added ~/.local/bin to PATH in .zshrc"
        fi
        
        # Export for current session
        export PATH="$HOME/.local/bin:$PATH"
        
        PATH_UPDATE_NEEDED=true
    else
        info "~/.local/bin already in PATH"
        PATH_UPDATE_NEEDED=false
    fi
}

# Show completion message
show_completion() {
    clear
    echo -e "${GREEN}╔═══════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║              Installation Complete! 🎉                     ║${NC}"
    echo -e "${GREEN}╚═══════════════════════════════════════════════════════════╝${NC}"
    echo
    echo "The dictation service has been successfully installed!"
    echo
    echo -e "${CYAN}Quick Start Guide:${NC}"
    echo "────────────────"
    echo -e "${GREEN}Start dictation:${NC}  dictation start"
    echo -e "${RED}Stop dictation:${NC}   dictation stop"
    echo -e "${YELLOW}Toggle on/off:${NC}    dictation toggle"
    echo -e "${BLUE}View status:${NC}      dictation status"
    echo -e "${MAGENTA}View logs:${NC}        dictation logs"
    echo
    echo -e "${CYAN}Configuration:${NC}"
    echo "─────────────"
    echo "• Config file: $CONFIG_BASE/dictation-service/config.json"
    echo "• Models directory: $MODEL_PATH"
    echo "• Logs directory: $INSTALL_BASE/share/dictation-service/logs"
    echo
    echo -e "${CYAN}Selected Settings:${NC}"
    echo "────────────────"
    echo "• Microphone: $SELECTED_DEVICE_NAME"
    echo "• Model: $WHISPER_MODEL"
    echo "• Language: ${LANGUAGE:-auto-detect}"
    echo "• GPU acceleration: $GPU_AVAILABLE"
    echo
    echo -e "${YELLOW}Important Tips:${NC}"
    echo "─────────────"
    echo "• The mic-monitor indicator shows when recording is active"
    echo "• Speak naturally, the service detects speech automatically"
    echo "• Pause for 1 second to end a sentence"
    echo "• Text appears where your cursor is positioned"
    echo
    echo -e "${CYAN}Troubleshooting:${NC}"
    echo "──────────────"
    echo "• If dictation doesn't work: dictation logs"
    echo "• Test microphone: parecord --device=$SELECTED_DEVICE -v | aplay"
    echo "• Adjust sensitivity in config.json (silence_threshold)"
    echo
    echo -e "${GREEN}Documentation:${NC}"
    echo "────────────"
    echo "• Full configuration guide: less $BUNDLE_DIR/docs/CONFIGURATION.md"
    echo "• Uninstall: dictation-uninstall"
    echo
    echo -e "${MAGENTA}Enjoy hands-free typing with AI-powered transcription!${NC}"
    echo
    
    # Add PATH reload notice if needed
    if [ "$PATH_UPDATE_NEEDED" = true ]; then
        echo -e "${YELLOW}Note:${NC} PATH has been updated. To use 'dictation' command in this terminal:"
        echo "      source ~/.bashrc"
        echo "      (or open a new terminal)"
        echo
    fi
    
    # Add reboot notice if auto-start was enabled but service isn't running
    if [ "$DICTATION_AUTO_START" = true ] && ! systemctl --user is-active --quiet dictation-service; then
        echo -e "${YELLOW}╔═══════════════════════════════════════════════════════════╗${NC}"
        echo -e "${YELLOW}║                    REBOOT REQUIRED                         ║${NC}"
        echo -e "${YELLOW}╚═══════════════════════════════════════════════════════════╝${NC}"
        echo
        echo "The dictation service is set to start automatically, but requires"
        echo "a reboot or re-login for the auto-start to take effect."
        echo
        echo -e "${GREEN}Options:${NC}"
        echo "1. Reboot now: sudo reboot"
        echo "2. Start manually now: dictation start"
        echo "3. Re-login to your session"
        echo
    fi
    
    echo "Installation log saved to: $LOG_FILE"
    
    # Clean up backup if everything succeeded
    if [ -d "$BACKUP_DIR" ]; then
        echo
        echo "Remove installation backup? (y/N)"
        read -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            rm -rf "$BACKUP_DIR"
            info "Backup removed"
        else
            info "Backup preserved at: $BACKUP_DIR"
        fi
    fi
}

# Main installation flow
main() {
    # Initial checks
    check_not_root
    show_welcome
    check_system
    
    log "Starting installation..."
    
    # Backup existing installation if any
    backup_existing
    
    # Core installation steps
    install_system_deps
    install_conda
    setup_conda_env
    select_audio_device
    install_mic_monitor
    install_dictation_service
    download_models
    configure_dictation
    create_shortcuts
    create_uninstaller
    configure_shell_path
    test_installation
    
    # Show completion
    show_completion
    
    log "Installation completed successfully!"
}

# Run main installation
main