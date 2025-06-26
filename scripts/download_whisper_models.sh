#!/bin/bash

# Script to download Whisper models (both OpenAI and Faster Whisper)
# Usage: ./download_whisper_models.sh [model_type] [model_size]
# Example: ./download_whisper_models.sh openai large-v3
# Example: ./download_whisper_models.sh faster large-v3
# Default: faster large-v3

set -e  # Exit on error

# Configuration
BASE_DIR="$HOME/Work/tools/whisper_models"
MODEL_TYPE="${1:-faster}"
MODEL_SIZE="${2:-large-v3}"

# Validate model type
if [[ "$MODEL_TYPE" != "openai" && "$MODEL_TYPE" != "faster" ]]; then
    echo "Error: Invalid model type: $MODEL_TYPE"
    echo "Usage: $0 [openai|faster] [model_size]"
    exit 1
fi

# Set directory based on model type
if [ "$MODEL_TYPE" = "openai" ]; then
    MODEL_DIR="$BASE_DIR/openai-whisper-$MODEL_SIZE"
else
    MODEL_DIR="$BASE_DIR/faster-whisper-$MODEL_SIZE"
fi

# Create directory structure
echo "Creating directory: $MODEL_DIR"
mkdir -p "$MODEL_DIR"

# Function to download with aria2c or fallback to wget
download_file() {
    local url="$1"
    local output="$2"

    echo "Downloading $output..."
    if command -v aria2c &> /dev/null; then
        # aria2c will resume partial downloads automatically with -c
        aria2c -c -x 16 -s 16 -k 1M -d "$MODEL_DIR" -o "$output" "$url"
    else
        # wget -c continues partial downloads
        wget -c -O "$MODEL_DIR/$output" "$url"
    fi
}

# Download OpenAI Whisper models
if [ "$MODEL_TYPE" = "openai" ]; then
    echo "Downloading OpenAI Whisper $MODEL_SIZE model..."

    # Define model URLs for OpenAI Whisper
    case "$MODEL_SIZE" in
        "tiny")
            MODEL_URL="https://openaipublic.azureedge.net/main/whisper/models/65147644a518d12f04e32d6f3b26facc3f8dd46e5390956a9424a650c0ce22b9/tiny.pt"
            ;;
        "tiny.en")
            MODEL_URL="https://openaipublic.azureedge.net/main/whisper/models/d3dd57d32accea0b295c96e26691aa14d8822fac7d9d27d5dc00b4ca2826dd03/tiny.en.pt"
            ;;
        "base")
            MODEL_URL="https://openaipublic.azureedge.net/main/whisper/models/ed3a0b6b1c0edf879ad9b11b1af5a0e6ab5db9205f891f668f8b0e6c6326e34e/base.pt"
            ;;
        "base.en")
            MODEL_URL="https://openaipublic.azureedge.net/main/whisper/models/25a8566e1d0c1e2231d1c762132cd20e0f96a85d16145c3a00adf5d1ac670ead/base.en.pt"
            ;;
        "small")
            MODEL_URL="https://openaipublic.azureedge.net/main/whisper/models/9ecf779972d90ba49c06d968637d720dd632c55bbf19d441fb42bf17a411e794/small.pt"
            ;;
        "small.en")
            MODEL_URL="https://openaipublic.azureedge.net/main/whisper/models/f953ad0fd29cacd07d5a9eda5624af0f6bcf2258be67c92b79389873d91e0872/small.en.pt"
            ;;
        "medium")
            MODEL_URL="https://openaipublic.azureedge.net/main/whisper/models/345ae4da62f9b3d59415adc60127b97c714f32e89e936602e85993674d08dcb1/medium.pt"
            ;;
        "medium.en")
            MODEL_URL="https://openaipublic.azureedge.net/main/whisper/models/d7440d1dc186f76616474e0ff0b3b6b879abc9d1a4aaf28c7e515df2abd215290/medium.en.pt"
            ;;
        "large"|"large-v1")
            MODEL_URL="https://openaipublic.azureedge.net/main/whisper/models/e4b87e7e0bf463eb8e6956e646f1e277e901512310def2c24bf0e11bd3c28e9a/large-v1.pt"
            MODEL_SIZE="large-v1"
            ;;
        "large-v2")
            MODEL_URL="https://openaipublic.azureedge.net/main/whisper/models/81f7c96c852ee8fc832187b0132e569d6c3065a3252ed18e56effd0b6a73e524/large-v2.pt"
            ;;
        "large-v3")
            MODEL_URL="https://openaipublic.azureedge.net/main/whisper/models/e5b1a55b89c1367dacf97e3e19bfd829a01529dbfdeefa8caeb59b3f1b81dadb/large-v3.pt"
            ;;
        "large-v3-turbo")
            MODEL_URL="https://openaipublic.azureedge.net/main/whisper/models/aff26ae408abcba5fbf8813c21e62b0941638c5f6eebfb145be0c9839262a19a/large-v3-turbo.pt"
            ;;
        *)
            echo "Error: Unknown model size for OpenAI Whisper: $MODEL_SIZE"
            echo "Valid options: tiny, tiny.en, base, base.en, small, small.en, medium, medium.en, large, large-v1, large-v2, large-v3, large-v3-turbo"
            exit 1
            ;;
    esac

    # Download the model file
    if [ -f "$MODEL_DIR/$MODEL_SIZE.pt" ]; then
        size=$(stat -c%s "$MODEL_DIR/$MODEL_SIZE.pt" 2>/dev/null || stat -f%z "$MODEL_DIR/$MODEL_SIZE.pt" 2>/dev/null)
        size_mb=$(echo "scale=2; $size / 1048576" | bc)
        echo "✓ $MODEL_SIZE.pt already exists ($size_mb MB), skipping download..."
    else
        download_file "$MODEL_URL" "$MODEL_SIZE.pt"
    fi

    # Verify download
    echo -e "\nVerifying downloaded file..."
    if [ -f "$MODEL_DIR/$MODEL_SIZE.pt" ]; then
        size=$(stat -c%s "$MODEL_DIR/$MODEL_SIZE.pt" 2>/dev/null || stat -f%z "$MODEL_DIR/$MODEL_SIZE.pt" 2>/dev/null)
        size_mb=$(echo "scale=2; $size / 1048576" | bc)
        echo "✓ $MODEL_SIZE.pt ($size_mb MB)"
    else
        echo "✗ $MODEL_SIZE.pt missing!"
    fi

    # Create a summary file
    echo -e "\nCreating model info file..."
    cat > "$MODEL_DIR/model_info.txt" << EOF
Model: OpenAI Whisper $MODEL_SIZE
Downloaded: $(date)
Path: $MODEL_DIR
Model file: $MODEL_SIZE.pt
EOF

# Download Faster Whisper models
else

    echo "Downloading Faster Whisper $MODEL_SIZE model..."

    # Define model URLs for Faster Whisper
    case "$MODEL_SIZE" in
        "tiny")
            REPO="Systran/faster-whisper-tiny"
            ;;
        "base")
            REPO="Systran/faster-whisper-base"
            ;;
        "small")
            REPO="Systran/faster-whisper-small"
            ;;
        "medium")
            REPO="Systran/faster-whisper-medium"
            ;;
        "large-v1")
            REPO="Systran/faster-whisper-large-v1"
            ;;
        "large-v2")
            REPO="Systran/faster-whisper-large-v2"
            ;;
        "large-v3")
            REPO="Systran/faster-whisper-large-v3"
            ;;
        *)
            echo "Error: Unknown model size for Faster Whisper: $MODEL_SIZE"
            echo "Valid options: tiny, base, small, medium, large-v1, large-v2, large-v3"
            exit 1
            ;;
    esac

    BASE_URL="https://huggingface.co/$REPO/resolve/main"

    cd "$MODEL_DIR"

    # Download model.bin (the large file)
    if [ -f "model.bin" ]; then
        size=$(stat -c%s "model.bin" 2>/dev/null || stat -f%z "model.bin" 2>/dev/null)
        size_gb=$(echo "scale=2; $size / 1073741824" | bc)
        echo "✓ model.bin already exists ($size_gb GB), skipping download..."
    else
        download_file "$BASE_URL/model.bin" "model.bin"
    fi

    # Download configuration files - check each one first
    declare -a POSSIBLE_FILES=(
        "config.json"
        "tokenizer.json"
        "preprocessor_config.json"
        "vocabulary.json"
        "vocabulary.txt"
    )

    echo -e "\nChecking and downloading configuration files..."
    for file in "${POSSIBLE_FILES[@]}"; do
        if [ -f "$file" ]; then
            size=$(stat -c%s "$file" 2>/dev/null || stat -f%z "$file" 2>/dev/null)
            echo "✓ $file already exists ($size bytes), skipping..."
        else
            # Check if file exists on server before downloading
            if wget --spider "$BASE_URL/$file" 2>/dev/null; then
                download_file "$BASE_URL/$file" "$file"
            else
                echo "- $file not available for this model (this is normal)"
            fi
        fi
    done

    # Verify downloads - only check files that actually exist
    echo -e "\nVerifying downloaded files..."

    # Always check model.bin
    if [ -f "model.bin" ]; then
        size=$(stat -c%s "model.bin" 2>/dev/null || stat -f%z "model.bin" 2>/dev/null)
        size_gb=$(echo "scale=2; $size / 1073741824" | bc)
        echo "✓ model.bin ($size_gb GB)"
    else
        echo "✗ model.bin missing! (This is required)"
    fi

    # Check which config files we actually have
    for file in "${POSSIBLE_FILES[@]}"; do
        if [ -f "$file" ]; then
            size=$(stat -c%s "$file" 2>/dev/null || stat -f%z "$file" 2>/dev/null)
            echo "✓ $file ($size bytes)"
        fi
    done

    # Minimal requirement check
    if [ ! -f "model.bin" ] || [ ! -f "config.json" ]; then
        echo -e "\n⚠️  Warning: Missing critical files (model.bin or config.json)"
        echo "The model may not work properly."
    fi

    # Create a summary file
    echo -e "\nCreating model info file..."
    cat > "$MODEL_DIR/model_info.txt" << EOF
Model: Faster Whisper $MODEL_SIZE
Repository: $REPO
Downloaded: $(date)
Path: $MODEL_DIR
EOF
fi

echo -e "\nModel downloaded to: $MODEL_DIR"
echo "Use this path in your Python script: $MODEL_DIR"
echo "Done!"