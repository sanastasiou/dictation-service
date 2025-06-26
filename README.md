# Speech-to-Text Dictation Service

A GPU-accelerated speech-to-text service that types what you say, powered by OpenAI's Whisper AI.

## Features

- 🎤 **Hands-free typing** - Speak naturally and watch your words appear
- 🚀 **GPU acceleration** - Leverages NVIDIA GPUs for fast transcription
- 🌍 **99+ languages** - Automatic language detection or manual selection
- 🔇 **Smart noise filtering** - Works well even with background noise
- 👁️ **Visual indicators** - See when the microphone is active
- ⚡ **Low latency** - Optimized for real-time dictation
- 🔄 **Automatic punctuation** - Intelligently adds punctuation to your speech
- 📊 **Multiple model support** - Choose between OpenAI Whisper and Faster Whisper

## Quick Install

1. **Clone the repository**:
   ```bash
   git clone https://github.com/sanastasiou/dictation-service.git
   cd dictation-service
   ```

2. **Run the installer**:
   ```bash
   chmod +x install.sh
   ./install.sh
   ```

3. **Follow the interactive prompts** to:
   - Select your microphone
   - Choose a Whisper model
   - Configure language settings
   - Set up the services

## Requirements

- **Operating System**: Ubuntu/Debian-based Linux (tested on Ubuntu 20.04+)
- **Python**: 3.8 or higher
- **Audio**: PulseAudio (standard on most Linux desktops)
- **GPU** (optional): NVIDIA GPU with CUDA support for faster processing
- **Disk Space**: ~4GB for models
- **RAM**: 4GB minimum (8GB+ recommended for larger models)

## Usage

### Basic Commands

```bash
# Start dictation service
dictation start

# Stop dictation service
dictation stop

# Toggle on/off
dictation toggle

# Check status
dictation status

# View logs
dictation logs
dictation logs -f  # Follow mode
```

### How It Works

1. **Start the service**: Run `dictation start`
2. **Position your cursor**: Click where you want text to appear
3. **Speak naturally**: The service detects when you start speaking
4. **Pause to finish**: Stop speaking for 1 second to end transcription
5. **Text appears**: Your words are typed where your cursor is

### Visual Indicators

The mic-monitor service shows a microphone icon in your system tray when:
- 🟢 **Green**: Service is running and ready
- 🔴 **Red**: Actively recording your speech

## Configuration

### Config File Location

The main configuration file is located at:
```
~/.config/dictation-service/config.json
```

### Key Settings

```json
{
    "whisper_model": "large-v3-turbo",    // Model to use
    "language": null,                      // null for auto-detect
    "silence_threshold": 0.02,             // Voice detection sensitivity
    "silence_duration": 1.0,               // Seconds of silence to stop
    "use_gpu": true,                       // Enable GPU acceleration
    "use_faster_whisper": false            // Use Faster Whisper implementation
}
```

### Available Models

| Model | Size | Speed | Accuracy | Best For |
|-------|------|-------|----------|----------|
| tiny | 39M | ⚡⚡⚡⚡⚡ | ⭐ | Quick notes, low-end systems |
| base | 74M | ⚡⚡⚡⚡ | ⭐⭐ | Basic transcription |
| small | 244M | ⚡⚡⚡ | ⭐⭐⭐ | Good balance |
| medium | 769M | ⚡⚡ | ⭐⭐⭐⭐ | Better accuracy |
| large-v3 | 1550M | ⚡ | ⭐⭐⭐⭐⭐ | Best accuracy |
| large-v3-turbo | 809M | ⚡⚡⚡ | ⭐⭐⭐⭐⭐ | **Recommended** |

### Language Support

Set `"language": null` for automatic detection, or use language codes:
- `"en"` - English
- `"es"` - Spanish
- `"fr"` - French
- `"de"` - German
- `"it"` - Italian
- `"pt"` - Portuguese
- `"zh"` - Chinese
- `"ja"` - Japanese
- [Full list of language codes](https://github.com/openai/whisper#available-models-and-languages)

## Troubleshooting

### Dictation not working?

1. **Check service status**:
   ```bash
   dictation status
   ```

2. **View logs for errors**:
   ```bash
   dictation logs
   ```

3. **Test your microphone**:
   ```bash
   # Replace with your device from 'pactl list sources'
   parecord --device=your_device -v | aplay
   ```

### Common Issues

**No GPU detected**:
- Check NVIDIA drivers: `nvidia-smi`
- The service will fall back to CPU (slower but functional)

**Poor transcription quality**:
- Try a larger model: Edit config.json and set `"whisper_model": "large-v3"`
- Adjust sensitivity: Lower `"silence_threshold"` for quiet environments
- Check microphone quality and positioning

**Service won't start**:
- Ensure conda environment is activated: `conda activate whisper`
- Check Python dependencies: `pip list | grep whisper`
- Verify audio device exists: `pactl list sources`

**Text appears in wrong location**:
- Click where you want text before speaking
- Some applications may not support simulated typing

### Performance Optimization

**For faster transcription**:
- Use `"large-v3-turbo"` model (best balance)
- Enable GPU: `"use_gpu": true`
- Try Faster Whisper: `"use_faster_whisper": true`
- Reduce beam size: `"beam_size": 1`

**For better accuracy**:
- Use `"large-v3"` model
- Increase beam size: `"beam_size": 10`
- Set specific language: `"language": "en"`

## Advanced Usage

### Using Different Microphones

Edit `~/.config/mic-monitor/config.json`:
```json
{
    "monitor_device": "Your Device Name",
    "monitor_all_devices": false
}
```

### Custom Model Paths

Edit `~/.config/dictation-service/config.json`:
```json
{
    "model_base_path": "/path/to/your/models",
    "openai_model_path": "/custom/path/model.pt"
}
```

### Running in Docker

See [docs/docker.md](docs/docker.md) for containerized deployment.

## Development

### Project Structure

```
dictation-service/
├── src/
│   ├── dictation-service.py    # Main transcription service
│   └── mic-monitor.py          # Microphone activity monitor
├── bin/
│   ├── dictation              # Service control script
│   ├── mic-monitor            # Monitor control script
│   └── arcrecord              # Audio recording wrapper
├── config/
│   ├── systemd/               # SystemD service files
│   └── *.json.default         # Default configurations
├── scripts/
│   └── download_whisper_models.sh  # Model download utility
└── docs/
    └── CONFIGURATION.md       # Detailed configuration guide
```

### Building from Source

```bash
# Clone repository
git clone https://github.com/sanastasiou/dictation-service.git
cd dictation-service

# Create conda environment
conda create -n whisper python=3.10
conda activate whisper

# Install dependencies
pip install -r requirements.txt

# Run tests
python -m pytest tests/
```

### Contributing

1. Fork the repository
2. Create a feature branch: `git checkout -b feature-name`
3. Make your changes
4. Run tests: `python -m pytest`
5. Submit a pull request

## Uninstalling

To completely remove the dictation service:

```bash
dictation-uninstall
```

This will remove:
- Service files and configurations
- Desktop shortcuts
- Log files

The following are preserved and must be removed manually:
- Whisper models (in `~/whisper-models` or your custom path)
- Conda environment: `conda env remove -n whisper`
- System packages (if you want to remove them)

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## Acknowledgments

- [OpenAI Whisper](https://github.com/openai/whisper) for the amazing speech recognition models
- [Faster Whisper](https://github.com/guillaumekln/faster-whisper) for the optimized implementation
- The open-source community for various tools and libraries used

## Support

- **Issues**: [GitHub Issues](https://github.com/sanastasiou/dictation-service/issues)
- **Discussions**: [GitHub Discussions](https://github.com/sanastasiou/dictation-service/discussions)
- **Wiki**: [Project Wiki](https://github.com/sanastasiou/dictation-service/wiki)

---

Made with ❤️ for the Linux community