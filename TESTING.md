# Testing Guide for Dictation Service

## Testing Approaches

### 1. Virtual Machine Testing (Recommended)

**Pros:**
- Clean environment
- Can snapshot before installation
- Test on different distros

**Cons:**
- Microphone passthrough can be tricky
- GPU passthrough is complex

#### VM Setup for Microphone:

**VirtualBox:**
1. Install VirtualBox Extension Pack
2. In VM Settings → Audio:
   - Enable Audio
   - Host Audio Driver: PulseAudio (or your system)
   - Audio Controller: Intel HD Audio
   - Enable Audio Input ✓
3. In VM, install: `sudo apt install virtualbox-guest-utils`

**VMware:**
1. VM Settings → Sound Card
2. Check "Connect at power on"
3. Use default device
4. Enable "Echo cancellation"

**QEMU/KVM (Virt-Manager):**
1. Add Hardware → Sound
2. Model: ich9 or ac97
3. In XML config, add:
```xml
<sound model='ich9'>
  <codec type='micro'/>
</sound>
```

### 2. Docker Testing (Limited)

Create a test container with audio support:

```bash
docker run -it --rm \
  --device /dev/snd \
  -e PULSE_SERVER=unix:${XDG_RUNTIME_DIR}/pulse/native \
  -v ${XDG_RUNTIME_DIR}/pulse/native:${XDG_RUNTIME_DIR}/pulse/native \
  -v ~/.config/pulse/cookie:/root/.config/pulse/cookie \
  ubuntu:22.04 bash
```

**Note:** GUI components (mic-monitor) won't work in Docker.

### 3. System Testing (Careful!)

Test on a separate user account:

```bash
# Create test user
sudo adduser dictation-test
sudo usermod -aG audio dictation-test

# Switch to test user
su - dictation-test

# Run installation
```

### 4. Component Testing (Safest)

Test individual components without full installation:

```bash
# Test 1: Check installer syntax
bash -n install.sh

# Test 2: Dry run (modify installer to add --dry-run flag)
./install.sh --dry-run

# Test 3: Test scripts individually
cd tests/
./test_installation.sh
./test_microphone.sh
python3 test_whisper.py
```

## Recommended Testing Workflow

### Phase 1: Static Testing
1. **Syntax check all scripts:**
   ```bash
   find . -name "*.sh" -exec bash -n {} \;
   find . -name "*.py" -exec python3 -m py_compile {} \;
   ```

2. **Check for hardcoded paths:**
   ```bash
   grep -r "/home/stefanos" --exclude-dir=.git
   ```

3. **Verify file permissions:**
   ```bash
   find . -type f -name "*.sh" -exec ls -l {} \;
   find . -type f -name "*.py" -exec ls -l {} \;
   ```

### Phase 2: VM Testing

1. **Create Ubuntu 22.04 VM**
   - 4GB RAM minimum
   - 20GB disk
   - Enable audio input

2. **Snapshot clean state**

3. **Test installation:**
   ```bash
   # Copy bundle to VM
   scp -r dictation-service-bundle/ vm-user@vm-ip:~/
   
   # In VM
   cd dictation-service-bundle
   ./install.sh
   ```

4. **Test each component:**
   - Microphone detection
   - Service startup
   - Model download
   - Actual dictation

### Phase 3: Multi-Distro Testing

Test on:
- Ubuntu 22.04 LTS ✓
- Ubuntu 20.04 LTS
- Debian 11/12
- Linux Mint 21
- Pop!_OS 22.04

### Testing Without Microphone

For testing without a real microphone:

1. **Create virtual audio device:**
   ```bash
   # Load dummy audio driver
   sudo modprobe snd-dummy
   
   # Create virtual source
   pactl load-module module-null-sink sink_name=virtual_mic
   pactl load-module module-virtual-source source_name=virtual_mic master=virtual_mic.monitor
   ```

2. **Play audio file as microphone input:**
   ```bash
   # Play audio file to virtual mic
   paplay --device=virtual_mic test-audio.wav
   ```

3. **Use in testing:**
   - Select "virtual_mic" during installation
   - Service will transcribe the audio file

## Continuous Integration

For automated testing, create `.github/workflows/test.yml`:

```yaml
name: Test Suite

on: [push, pull_request]

jobs:
  syntax-check:
    runs-on: ubuntu-latest
    steps:
    - uses: actions/checkout@v3
    - name: Check shell scripts
      run: |
        find . -name "*.sh" -exec bash -n {} \;
    
    - name: Check Python scripts
      run: |
        find . -name "*.py" -exec python3 -m py_compile {} \;
    
    - name: Check for hardcoded paths
      run: |
        ! grep -r "/home/stefanos" --exclude-dir=.git --exclude="*.md"

  test-installer:
    runs-on: ubuntu-latest
    steps:
    - uses: actions/checkout@v3
    - name: Test installer in dry-run mode
      run: |
        # Add dry-run support to installer first
        echo "Installer validation would run here"
```

## Quick Verification Commands

After installation, verify with:

```bash
# Check all components
./tests/test_installation.sh

# Test microphone
./tests/test_microphone.sh

# Test Python environment
conda activate whisper
python tests/test_whisper.py

# Check services
systemctl --user status mic-monitor
dictation status
```

## Troubleshooting Test Failures

1. **No audio devices in VM:**
   - Check VM audio settings
   - Verify PulseAudio in host: `pactl info`
   - Try different audio controller

2. **GPU not detected in VM:**
   - This is normal - test CPU mode
   - For GPU testing, use bare metal

3. **Service won't start:**
   - Check logs: `journalctl --user -u mic-monitor`
   - Verify conda activation
   - Check file permissions

Remember: Always test on a clean system or VM before running on your main machine!