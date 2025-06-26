#!/bin/bash
# Installation verification tests

set -e

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Test results
TESTS_PASSED=0
TESTS_FAILED=0

# Test function
run_test() {
    local test_name="$1"
    local test_command="$2"
    
    echo -ne "${BLUE}Testing:${NC} $test_name... "
    
    if eval "$test_command" &>/dev/null; then
        echo -e "${GREEN}PASS${NC}"
        ((TESTS_PASSED++))
        return 0
    else
        echo -e "${RED}FAIL${NC}"
        ((TESTS_FAILED++))
        return 1
    fi
}

# Header
echo -e "${BLUE}=== Dictation Service Installation Test ===${NC}"
echo

# 1. Check if conda environment exists
run_test "Conda environment 'whisper'" "conda env list | grep -q '^whisper '"

# 2. Check if Python packages are installed
if conda env list | grep -q '^whisper '; then
    run_test "PyTorch installation" "conda run -n whisper python -c 'import torch'"
    run_test "Whisper installation" "conda run -n whisper python -c 'import whisper'"
    run_test "PyAutoGUI installation" "conda run -n whisper python -c 'import pyautogui'"
    run_test "SciPy installation" "conda run -n whisper python -c 'import scipy'"
fi

# 3. Check if service files exist
run_test "Dictation service script" "[ -f ~/.local/share/dictation-service/dictation-service.py ]"
run_test "Mic-monitor script" "[ -f ~/.local/share/mic-monitor/mic-monitor.py ]"
run_test "Dictation control script" "[ -f ~/.local/bin/dictation ]"
run_test "Mic-monitor control script" "[ -f ~/.local/bin/mic-monitor ]"
run_test "Arcrecord script" "[ -f ~/.local/bin/arcrecord ]"

# 4. Check if configuration files exist
run_test "Dictation config" "[ -f ~/.config/dictation-service/config.json ]"
run_test "Mic-monitor config" "[ -f ~/.config/mic-monitor/config.json ]"

# 5. Check systemd service
run_test "Mic-monitor service file" "[ -f ~/.config/systemd/user/mic-monitor.service ]"
run_test "Mic-monitor service loaded" "systemctl --user list-unit-files | grep -q mic-monitor.service"

# 6. Check if binaries are in PATH
run_test "Dictation in PATH" "which dictation || [ -f ~/.local/bin/dictation ]"

# 7. Check audio system
run_test "PulseAudio running" "pactl info"
run_test "Audio sources available" "pactl list sources | grep -q 'Name:'"

# 8. Check for GPU (optional)
if command -v nvidia-smi &>/dev/null; then
    run_test "NVIDIA GPU available" "nvidia-smi"
    run_test "CUDA available in PyTorch" "conda run -n whisper python -c 'import torch; assert torch.cuda.is_available()'"
else
    echo -e "${YELLOW}Skipping:${NC} GPU tests (no NVIDIA GPU detected)"
fi

# 9. Check model directory
if [ -f ~/.config/dictation-service/config.json ]; then
    MODEL_PATH=$(jq -r '.model_base_path' ~/.config/dictation-service/config.json | sed "s|~|$HOME|g")
    run_test "Model directory exists" "[ -d '$MODEL_PATH' ]"
    
    # Check if any models are downloaded
    if [ -d "$MODEL_PATH" ]; then
        if ls "$MODEL_PATH"/openai-whisper-*/*.pt &>/dev/null || ls "$MODEL_PATH"/faster-whisper-*/model.bin &>/dev/null; then
            echo -e "${GREEN}Found Whisper models in $MODEL_PATH${NC}"
        else
            echo -e "${YELLOW}No Whisper models found in $MODEL_PATH${NC}"
        fi
    fi
fi

# 10. Test mic-monitor service
echo
echo -e "${BLUE}Testing services:${NC}"
if systemctl --user is-active --quiet mic-monitor.service; then
    echo -e "Mic-monitor service: ${GREEN}Running${NC}"
else
    echo -e "Mic-monitor service: ${YELLOW}Not running${NC}"
    echo "  Start with: systemctl --user start mic-monitor.service"
fi

# Summary
echo
echo -e "${BLUE}=== Test Summary ===${NC}"
echo -e "Tests passed: ${GREEN}$TESTS_PASSED${NC}"
echo -e "Tests failed: ${RED}$TESTS_FAILED${NC}"

if [ $TESTS_FAILED -eq 0 ]; then
    echo
    echo -e "${GREEN}All tests passed! Installation appears to be complete.${NC}"
    exit 0
else
    echo
    echo -e "${YELLOW}Some tests failed. Please check the installation.${NC}"
    exit 1
fi