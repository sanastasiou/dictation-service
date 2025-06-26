# GPU-Optimized Dictation Service

A high-performance speech-to-text dictation service optimized for NVIDIA GPUs, supporting both OpenAI Whisper and Faster Whisper models.

## Features

- **GPU Acceleration**: Optimized for NVIDIA GPUs with CUDA support
- **Dual Model Support**: Choose between OpenAI Whisper and Faster Whisper
- **Multi-language Support**: Automatic language detection for 99 languages
- **Pre-recording Buffer**: Captures audio before voice detection to avoid cutting off speech
- **Intelligent Model Fallback**: Automatically finds the best available model
- **Real-time Processing**: Low-latency transcription with configurable parameters

## Installation

1. Create and activate conda environment:
```bash
conda create -n whisper python=3.10
conda activate whisper
```

2. Install dependencies:
```bash
pip install torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cu121
pip install openai-whisper faster-whisper pyautogui scipy numpy
conda install -c conda-forge cudnn  # For Faster Whisper GPU support
```

3. Download Whisper models:
```bash
./download_whisper_models.sh openai large-v3-turbo
./download_whisper_models.sh faster large-v3
```

## Configuration

The service uses a JSON configuration file located at `~/.config/dictation-service/config.json`. Below are all available options:

### Audio Settings

- **`silence_threshold`** (float, default: 0.02)
  - Volume threshold for voice activity detection
  - Lower values = more sensitive (picks up quieter sounds)
  - Higher values = less sensitive (requires louder speech)
  - Range: 0.01 - 0.1 recommended

- **`silence_duration`** (float, default: 1.0)
  - Seconds of silence before ending speech segment
  - Shorter = more responsive but may cut off pauses
  - Longer = handles pauses better but less responsive
  - Range: 0.5 - 2.0 seconds recommended

- **`min_speech_duration`** (float, default: 0.3)
  - Minimum seconds of speech to process
  - Filters out very short sounds/noise
  - Range: 0.1 - 0.5 seconds recommended

- **`pre_record_seconds`** (float, default: 0.5)
  - Seconds of audio to capture before voice detection
  - Prevents cutting off the beginning of speech
  - Range: 0.3 - 1.0 seconds recommended

### Model Settings

- **`whisper_model`** (string, default: "large-v3")
  - Which Whisper model to use
  - Options: "tiny", "base", "small", "medium", "large-v1", "large-v2", "large-v3", "large-v3-turbo"
  - Larger models = better accuracy but slower
  - "large-v3-turbo" = best balance of speed and accuracy (OpenAI only)

- **`use_faster_whisper`** (boolean, default: false)
  - true = Use Faster Whisper (better performance)
  - false = Use OpenAI Whisper (better compatibility)
  - Faster Whisper typically 2-4x faster than OpenAI

- **`model_base_path`** (string, default: "~/Work/tools/whisper_models")
  - Base directory where models are stored
  - Can use ~ for home directory

- **`openai_model_path`** (string, default: null)
  - Custom path to OpenAI Whisper model file
  - If null, auto-generates from model_base_path and whisper_model

- **`faster_model_path`** (string, default: null)
  - Custom path to Faster Whisper model directory
  - If null, auto-generates from model_base_path and whisper_model

### Language Settings

- **`language`** (string or null, default: "en")
  - Language code for transcription
  - null = automatic language detection
  - Examples: "en" (English), "de" (German), "es" (Spanish), "fr" (French)
  - See [Whisper language codes](https://github.com/openai/whisper#available-models-and-languages)

- **`auto_punctuation`** (boolean, default: true)
  - Automatically add space after transcribed text
  - Helps with continuous dictation flow

### Audio Processing

- **`noise_suppression`** (boolean, default: true)
  - Enable high-pass filter for noise reduction
  - Reduces low-frequency noise (fans, hums)

- **`high_pass_freq`** (integer, default: 80)
  - High-pass filter cutoff frequency in Hz
  - Higher = more aggressive filtering
  - Range: 50-150 Hz recommended

### GPU Settings

- **`use_gpu`** (boolean, default: true)
  - Use GPU acceleration if available
  - Falls back to CPU if GPU not available

- **`fp16`** (boolean, default: true)
  - Use 16-bit floating point for GPU processing
  - Faster and uses less memory
  - Minimal impact on accuracy

- **`compute_type`** (string, default: "float16")
  - Computation precision for Faster Whisper
  - Options: "float16", "int8", "float32"
  - "float16" = best for GPU
  - "int8" = best for CPU

### Advanced Whisper Settings

- **`beam_size`** (integer, default: 5)
  - Number of beams for beam search
  - Higher = potentially better accuracy but slower
  - Range: 1-10 recommended

- **`best_of`** (integer, default: 5)
  - Number of candidates when sampling
  - Works with beam_size for better results
  - Range: 1-10 recommended

- **`debug_audio`** (boolean, default: false)
  - Enable detailed audio debugging logs
  - Useful for troubleshooting audio issues

## Example Configurations

### High Accuracy (Best Quality)
```json
{
    "whisper_model": "large-v3",
    "use_faster_whisper": false,
    "language": null,
    "beam_size": 10,
    "best_of": 10,
    "fp16": true
}
```

### High Speed (Best Performance)
```json
{
    "whisper_model": "large-v3",
    "use_faster_whisper": true,
    "language": "en",
    "beam_size": 1,
    "compute_type": "int8",
    "fp16": false
}
```

### Multilingual
```json
{
    "whisper_model": "large-v3",
    "language": null,
    "use_faster_whisper": true,
    "auto_punctuation": true
}
```

### Low-End System
```json
{
    "whisper_model": "base",
    "use_faster_whisper": true,
    "use_gpu": false,
    "compute_type": "int8",
    "beam_size": 1
}
```

## Model Selection Guide

| Model | Size | English-Only | Multilingual | Speed | Accuracy |
|-------|------|--------------|--------------|-------|----------|
| tiny | 39M | ✓ | ✓ | ★★★★★ | ★☆☆☆☆ |
| base | 74M | ✓ | ✓ | ★★★★☆ | ★★☆☆☆ |
| small | 244M | ✓ | ✓ | ★★★☆☆ | ★★★☆☆ |
| medium | 769M | ✓ | ✓ | ★★☆☆☆ | ★★★★☆ |
| large-v1 | 1550M | ✗ | ✓ | ★☆☆☆☆ | ★★★★☆ |
| large-v2 | 1550M | ✗ | ✓ | ★☆☆☆☆ | ★★★★★ |
| large-v3 | 1550M | ✗ | ✓ | ★☆☆☆☆ | ★★★★★ |
| large-v3-turbo | 809M | ✗ | ✓ | ★★★☆☆ | ★★★★★ |

## Usage

Start the service:
```bash
dictation start
```

Stop the service:
```bash
dictation stop
```

View logs:
```bash
dictation logs
dictation logs -f  # Follow mode
```

Test in foreground:
```bash
dictation test
```

## Troubleshooting

### GPU Not Detected
- Ensure CUDA is installed: `nvidia-smi`
- Check PyTorch CUDA: `python -c "import torch; print(torch.cuda.is_available())"`

### Faster Whisper cuDNN Errors
- Install cuDNN: `conda install -c conda-forge cudnn`
- The service automatically handles library path setup

### Model Not Found
- Check model path in config
- Download models using provided script
- Service will fall back to available models

### Poor Transcription Quality
- Use larger model (large-v3 or large-v3-turbo)
- Adjust silence_threshold for your microphone
- Ensure good audio quality and minimal background noise

## Performance Tips

1. **For Real-time Dictation**: Use Faster Whisper with large-v3
2. **For Best Accuracy**: Use OpenAI Whisper with large-v3-turbo
3. **For Low-latency**: Reduce beam_size to 1
4. **For GPU Memory Issues**: Use fp16=true or smaller models
5. **For CPU Usage**: Use Faster Whisper with compute_type="int8"