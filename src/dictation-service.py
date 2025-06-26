#!/usr/bin/env python3
"""
GPU-Optimized Dictation Service for RTX 3090
Supporting both OpenAI Whisper and Faster Whisper
"""

import subprocess
import signal
import sys
import time
import os
import json
import logging
import threading
import queue
import numpy as np
import torch
import pyautogui
import scipy.signal
from scipy import signal as scipy_signal
from datetime import datetime
from pathlib import Path
from collections import deque

# Setup cuDNN paths before importing whisper libraries
def setup_cudnn_paths():
    """Setup cuDNN library paths for Faster Whisper"""
    conda_prefix = os.environ.get('CONDA_PREFIX')
    if not conda_prefix:
        return False

    lib_dir = Path(conda_prefix) / "lib"
    if not lib_dir.exists():
        return False

    # Add to LD_LIBRARY_PATH
    current_ld_path = os.environ.get('LD_LIBRARY_PATH', '')
    if str(lib_dir) not in current_ld_path:
        os.environ['LD_LIBRARY_PATH'] = f"{lib_dir}:{current_ld_path}".rstrip(':')

    # Add nvidia package paths if they exist
    site_packages = Path(conda_prefix) / "lib" / f"python{sys.version_info.major}.{sys.version_info.minor}" / "site-packages"
    nvidia_paths = [
        site_packages / "nvidia" / "cudnn" / "lib",
        site_packages / "nvidia_cudnn_cu12" / "lib",
        site_packages / "nvidia_cudnn_cu11" / "lib"
    ]

    for nvidia_path in nvidia_paths:
        if nvidia_path.exists():
            os.environ['LD_LIBRARY_PATH'] = f"{nvidia_path}:{os.environ['LD_LIBRARY_PATH']}"

    # Preload cudnn libraries if found - but avoid problematic ones
    try:
        import ctypes
        # First, find and load the main libcudnn.so file
        cudnn_main = lib_dir / "libcudnn.so.9.1.1"
        if cudnn_main.exists():
            try:
                ctypes.CDLL(str(cudnn_main), mode=ctypes.RTLD_GLOBAL)
            except:
                pass

        # Then load ops if it exists
        cudnn_ops = lib_dir / "libcudnn_ops.so.9.1.1"
        if cudnn_ops.exists():
            try:
                ctypes.CDLL(str(cudnn_ops), mode=ctypes.RTLD_GLOBAL)
            except:
                pass

        # DO NOT load libcudnn_graph.so - it's causing the issue
    except:
        pass

    return True

# Setup paths before imports - but only if we need Faster Whisper
# Check config to see if we need to setup cudnn
config_file = Path.home() / ".config" / "dictation-service" / "config.json"
should_setup_cudnn = False

if config_file.exists():
    try:
        with open(config_file, 'r') as f:
            config = json.load(f)
            should_setup_cudnn = config.get("use_faster_whisper", False)
    except:
        pass

if should_setup_cudnn:
    setup_cudnn_paths()

# Now import whisper libraries
import whisper
try:
    from faster_whisper import WhisperModel
    FASTER_WHISPER_AVAILABLE = True
except ImportError:
    FASTER_WHISPER_AVAILABLE = False
    print("Warning: faster-whisper not installed. Using OpenAI Whisper only.")

class DictationService:
    def __init__(self):
        self.config_dir = Path.home() / ".config" / "dictation-service"
        self.log_dir = Path.home() / ".local" / "share" / "dictation-service" / "logs"
        self.config_file = self.config_dir / "config.json"
        self.state_file = "/tmp/dictation-service-state"
        self.pid_file = "/tmp/dictation-service.pid"

        # Create directories
        self.config_dir.mkdir(parents=True, exist_ok=True)
        self.log_dir.mkdir(parents=True, exist_ok=True)

        # Write PID file
        with open(self.pid_file, 'w') as f:
            f.write(str(os.getpid()))

        # Setup logging
        self.setup_logging()

        # Load configuration
        self.config = self.load_config()

        # Audio parameters
        self.DEVICE = self.get_audio_device()
        self.RATE = 48000
        self.CHANNELS = 1
        self.CHUNK_SECONDS = 0.01
        self.CHUNK_SIZE = int(self.RATE * self.CHUNK_SECONDS * 2)

        # Voice detection parameters
        self.SILENCE_THRESHOLD = self.config.get("silence_threshold", 0.02)
        self.SILENCE_DURATION = self.config.get("silence_duration", 1.0)
        self.MIN_SPEECH_DURATION = self.config.get("min_speech_duration", 0.3)

        # Pre-recording buffer
        self.PRE_RECORD_SECONDS = self.config.get("pre_record_seconds", 0.5)
        self.pre_record_chunks = int(self.PRE_RECORD_SECONDS / self.CHUNK_SECONDS)
        self.audio_ring_buffer = deque(maxlen=self.pre_record_chunks)

        # State tracking
        self.is_recording = False
        self.audio_buffer = []
        self.silence_start = None
        self.speech_start = None
        self.parecord_process = None

        # Initialize noise suppression
        self.setup_noise_suppression()

        # Setup GPU and load Whisper model
        self.setup_whisper_model()

        # Signal handlers
        signal.signal(signal.SIGTERM, self.cleanup)
        signal.signal(signal.SIGINT, self.cleanup)

        # Write state file
        with open(self.state_file, 'w') as f:
            f.write("ACTIVE")

    def setup_logging(self):
        """Configure logging"""
        log_file = self.log_dir / f"dictation-{datetime.now():%Y%m%d}.log"

        logging.basicConfig(
            level=logging.INFO,
            format='%(asctime)s - %(levelname)s - %(message)s',
            handlers=[
                logging.FileHandler(log_file),
                logging.StreamHandler(sys.stdout)
            ]
        )
        self.logger = logging.getLogger(__name__)

    def get_audio_device(self):
        """Get audio device from config or environment"""
        # First check config file
        if hasattr(self, 'config') and self.config.get('audio_device'):
            return self.config['audio_device']
        
        # Then check environment variable
        device = os.environ.get('DICTATION_AUDIO_DEVICE')
        if device:
            return device
        
        # Finally, try to get first available non-monitor device
        try:
            result = subprocess.run(
                ['pactl', 'list', 'short', 'sources'],
                capture_output=True,
                text=True,
                check=True
            )
            for line in result.stdout.strip().split('\n'):
                if line and '.monitor' not in line:
                    # Return the device name (second column)
                    return line.split('\t')[1]
        except:
            pass
        
        # Fallback to default
        self.logger.warning("No audio device configured or found, using default")
        return "default"
    
    def load_config(self):
        """Load configuration from file"""
        default_config = {
            "silence_threshold": 0.02,
            "silence_duration": 1.0,
            "min_speech_duration": 0.3,
            "pre_record_seconds": 0.5,
            "whisper_model": "large-v3",
            "use_faster_whisper": False,
            "model_base_path": "~/Work/tools/whisper_models",
            "openai_model_path": None,  # Will be auto-generated if None
            "faster_model_path": None,   # Will be auto-generated if None
            "language": "en",
            "auto_punctuation": True,
            "noise_suppression": True,
            "high_pass_freq": 80,
            "debug_audio": False,
            "use_gpu": True,
            "fp16": True,
            "beam_size": 5,
            "best_of": 5,
            "compute_type": "float16"  # For Faster Whisper
        }

        if self.config_file.exists():
            try:
                with open(self.config_file, 'r') as f:
                    config = json.load(f)
                    # Merge with defaults
                    for key, value in default_config.items():
                        if key not in config:
                            config[key] = value
                    return config
            except Exception as e:
                self.logger.error(f"Failed to load config: {e}")

        # Save default config
        with open(self.config_file, 'w') as f:
            json.dump(default_config, f, indent=2)

        return default_config

    def get_model_path(self):
        """Get the appropriate model path based on configuration"""
        model_name = self.config.get("whisper_model", "large-v3")
        base_path = Path(self.config.get("model_base_path", "~/Work/tools/whisper_models")).expanduser()

        if self.config.get("use_faster_whisper", False):
            # Use custom path or generate default
            if self.config.get("faster_model_path"):
                return Path(self.config["faster_model_path"]).expanduser()
            else:
                return base_path / f"faster-whisper-{model_name}"
        else:
            # Use custom path or generate default
            if self.config.get("openai_model_path"):
                return Path(self.config["openai_model_path"]).expanduser()
            else:
                # Map model names to file names
                model_file_map = {
                    "large-v3": "large-v3.pt",
                    "large-v3-turbo": "large-v3-turbo.pt",
                    "large-v2": "large-v2.pt",
                    "large-v1": "large-v1.pt",
                    "large": "large-v1.pt",
                    "medium": "medium.pt",
                    "small": "small.pt",
                    "base": "base.pt",
                    "tiny": "tiny.pt"
                }
                model_file = model_file_map.get(model_name, f"{model_name}.pt")
                return base_path / f"openai-whisper-{model_name}" / model_file

    def find_best_available_model(self, preferred_model, use_faster_whisper):
        """Find the best available model based on preference and what's downloaded"""
        base_path = Path(self.config.get("model_base_path", "~/Work/tools/whisper_models")).expanduser()

        # Model hierarchy from best to worst
        model_hierarchy = [
            "large-v3-turbo", "large-v3", "large-v2", "large-v1", "large",
            "medium.en", "medium", "small.en", "small", "base.en", "base",
            "tiny.en", "tiny"
        ]

        # Models available for each whisper type
        faster_whisper_models = ["large-v3", "large-v2", "large-v1", "medium", "small", "base", "tiny"]
        openai_whisper_models = ["large-v3-turbo", "large-v3", "large-v2", "large-v1", "large",
                                "medium.en", "medium", "small.en", "small", "base.en", "base",
                                "tiny.en", "tiny"]

        # Get appropriate model list
        valid_models = faster_whisper_models if use_faster_whisper else openai_whisper_models

        # Start with preferred model if it's valid
        if preferred_model in valid_models:
            start_index = model_hierarchy.index(preferred_model) if preferred_model in model_hierarchy else 0
        else:
            # Map to closest equivalent
            model_map = {
                "large-v3-turbo": "large-v3",
                "large": "large-v1",
                "tiny.en": "tiny",
                "base.en": "base",
                "small.en": "small",
                "medium.en": "medium"
            }
            mapped = model_map.get(preferred_model, preferred_model)
            start_index = model_hierarchy.index(mapped) if mapped in model_hierarchy else 0

        # Check for available models starting from preferred
        for i in range(start_index, len(model_hierarchy)):
            model = model_hierarchy[i]

            # Skip if not valid for this whisper type
            if model not in valid_models:
                continue

            # Check if model exists
            if use_faster_whisper:
                model_path = base_path / f"faster-whisper-{model}"
                if model_path.exists() and (model_path / "model.bin").exists():
                    return model, model_path
            else:
                # Map model names to file names for OpenAI
                model_file_map = {
                    "large-v3": "large-v3.pt",
                    "large-v3-turbo": "large-v3-turbo.pt",
                    "large-v2": "large-v2.pt",
                    "large-v1": "large-v1.pt",
                    "large": "large-v1.pt",
                    "medium": "medium.pt",
                    "medium.en": "medium.en.pt",
                    "small": "small.pt",
                    "small.en": "small.en.pt",
                    "base": "base.pt",
                    "base.en": "base.en.pt",
                    "tiny": "tiny.pt",
                    "tiny.en": "tiny.en.pt"
                }
                model_file = model_file_map.get(model, f"{model}.pt")
                model_path = base_path / f"openai-whisper-{model}" / model_file
                if model_path.exists():
                    return model, model_path

        return None, None

    def setup_whisper_model(self):
        """Setup Whisper model with GPU optimization"""
        model_name = self.config.get("whisper_model", "large-v3")
        use_faster_whisper = self.config.get("use_faster_whisper", False)
        original_model = model_name

        # Check for GPU
        if torch.cuda.is_available() and self.config.get("use_gpu", True):
            self.device = "cuda"
            self.fp16 = self.config.get("fp16", True)

            # Log GPU info
            gpu_name = torch.cuda.get_device_name(0)
            gpu_memory = torch.cuda.get_device_properties(0).total_memory / 1024**3
            self.logger.info(f"Using GPU: {gpu_name} ({gpu_memory:.1f} GB)")

            # Set PyTorch to use GPU efficiently
            torch.backends.cudnn.benchmark = True
            torch.backends.cuda.matmul.allow_tf32 = True
        else:
            self.device = "cpu"
            self.fp16 = False
            self.logger.info("Using CPU (GPU not available or disabled)")

        # Find best available model
        model_name, model_path = self.find_best_available_model(original_model, use_faster_whisper)

        if not model_name:
            # No model found for preferred type, try the other type
            self.logger.warning(f"No {'Faster' if use_faster_whisper else 'OpenAI'} Whisper models found")
            self.logger.info(f"Trying {'OpenAI' if use_faster_whisper else 'Faster'} Whisper instead")

            # Try the other whisper type
            use_faster_whisper = not use_faster_whisper
            model_name, model_path = self.find_best_available_model(original_model, use_faster_whisper)

            if not model_name:
                self.logger.error("No Whisper models found at all!")
                self.logger.error(f"Please download models to: {self.config.get('model_base_path')}")
                self.logger.error("Run: ./download_whisper_models.sh")
                sys.exit(1)

        # Log if using different model
        if model_name != original_model:
            self.logger.warning(f"Model '{original_model}' not available, using '{model_name}' instead")

        # Update config with actual model being used
        self.config["whisper_model"] = model_name

        # Load the appropriate model
        if use_faster_whisper and FASTER_WHISPER_AVAILABLE:
            self.logger.info(f"Loading Faster Whisper model: {model_name}")
            self.logger.info(f"Model path: {model_path}")

            try:
                compute_type = self.config.get("compute_type", "float16" if self.device == "cuda" else "int8")
                self.whisper_model = WhisperModel(
                    str(model_path),
                    device=self.device,
                    compute_type=compute_type
                )
                self.logger.info(f"Faster Whisper loaded successfully (compute_type: {compute_type})")
                self.using_faster_whisper = True
                return
            except Exception as e:
                self.logger.error(f"Failed to load Faster Whisper: {e}")
                self.logger.info("Falling back to OpenAI Whisper")
                use_faster_whisper = False
                # Find best OpenAI model
                model_name, model_path = self.find_best_available_model(original_model, False)

        # Load OpenAI Whisper
        if not use_faster_whisper or not FASTER_WHISPER_AVAILABLE:
            if not model_name:
                self.logger.error("No OpenAI Whisper models found either!")
                sys.exit(1)

            self.logger.info(f"Loading OpenAI Whisper model: {model_name}")
            self.logger.info(f"Model path: {model_path}")

            try:
                self.whisper_model = whisper.load_model(str(model_path), device=self.device)
                self.logger.info(f"OpenAI Whisper loaded successfully (FP16: {self.fp16})")
                self.using_faster_whisper = False
            except Exception as e:
                self.logger.error(f"Failed to load OpenAI Whisper: {e}")
                self.logger.error("No working Whisper implementation found!")
                sys.exit(1)

    def setup_noise_suppression(self):
        """Setup noise suppression filters"""
        # Basic high-pass filter
        self.highpass_sos = scipy_signal.butter(
            4,
            self.config.get("high_pass_freq", 80),
            'hp',
            fs=self.RATE,
            output='sos'
        )

    def calculate_rms(self, data):
        """Calculate Root Mean Square (volume level)"""
        return np.sqrt(np.mean(np.square(data)))

    def apply_noise_filters(self, audio_data):
        """Apply noise suppression"""
        if not self.config.get("noise_suppression", True):
            return audio_data

        # Apply high-pass filter
        filtered = scipy_signal.sosfilt(self.highpass_sos, audio_data)
        return filtered

    def start_recording(self):
        """Start recording speech"""
        if not self.is_recording:
            self.is_recording = True
            self.audio_buffer = []

            # Add pre-recorded audio
            if len(self.audio_ring_buffer) > 0:
                self.audio_buffer.extend(list(self.audio_ring_buffer))
                self.logger.info(f"Added {len(self.audio_ring_buffer)} pre-recorded chunks")

            self.speech_start = time.time()
            self.logger.info("Started recording speech")

            # Notify mic monitor
            try:
                subprocess.run(['touch', '/tmp/dictation-recording'], check=False)
            except:
                pass

    def stop_recording(self):
        """Stop recording and process speech"""
        if self.is_recording:
            self.is_recording = False

            # Remove recording indicator
            try:
                subprocess.run(['rm', '-f', '/tmp/dictation-recording'], check=False)
            except:
                pass

            # Check minimum duration
            speech_duration = time.time() - self.speech_start
            if speech_duration < self.MIN_SPEECH_DURATION:
                self.logger.debug(f"Speech too short ({speech_duration:.2f}s), discarding")
                self.audio_buffer = []
                return

            if len(self.audio_buffer) > 0:
                audio_data = np.concatenate(self.audio_buffer)
                self.logger.info(f"Processing {speech_duration:.1f}s of audio")

                # Process in separate thread
                threading.Thread(
                    target=self.process_speech,
                    args=(audio_data,),
                    daemon=True
                ).start()

            self.audio_buffer = []
            self.logger.info("Stopped recording speech")

    def process_speech(self, audio_data):
        """Process recorded speech with Whisper"""
        try:
            start_time = time.time()

            # Apply noise suppression
            audio_data = self.apply_noise_filters(audio_data)

            # Resample from 48kHz to 16kHz for Whisper
            audio_data_16k = scipy.signal.resample(audio_data, len(audio_data) // 3)
            audio_data_16k = audio_data_16k.astype(np.float32)

            # Normalize
            max_val = np.max(np.abs(audio_data_16k))
            if max_val > 0:
                audio_data_16k = audio_data_16k / max_val * 0.95

            # Transcribe based on model type
            if self.using_faster_whisper:
                # Faster Whisper transcription
                segments, info = self.whisper_model.transcribe(
                    audio_data_16k,
                    language=self.config.get("language", None),
                    beam_size=self.config.get("beam_size", 5),
                    best_of=self.config.get("best_of", 5),
                    temperature=0.0,
                    compression_ratio_threshold=2.4,
                    log_prob_threshold=-1.0,
                    no_speech_threshold=0.6,
                    condition_on_previous_text=False,
                    initial_prompt=None,
                    suppress_tokens="-1",
                    without_timestamps=True,
                    vad_filter=True,
                    vad_parameters=dict(min_silence_duration_ms=500)
                )

                # Convert segments to text
                text = " ".join([segment.text.strip() for segment in segments])

            else:
                # OpenAI Whisper transcription
                # Move to GPU if available
                if self.device == "cuda":
                    audio_tensor = torch.from_numpy(audio_data_16k).to(self.device)
                else:
                    audio_tensor = audio_data_16k

                # Transcribe with GPU acceleration
                with torch.amp.autocast('cuda', enabled=self.fp16):
                    result = self.whisper_model.transcribe(
                        audio_tensor,
                        language=self.config.get("language", None),
                        fp16=self.fp16,
                        verbose=False,
                        temperature=0.0,
                        compression_ratio_threshold=2.4,
                        logprob_threshold=-1.0,
                        no_speech_threshold=0.6,
                        condition_on_previous_text=False,
                        initial_prompt=None,
                        suppress_tokens="-1",
                        without_timestamps=True,
                        beam_size=self.config.get("beam_size", 5),
                        best_of=self.config.get("best_of", 5)
                    )

                text = result["text"].strip()

            processing_time = time.time() - start_time
            self.logger.info(f"Transcription took {processing_time:.2f}s")

            # Validate transcription
            if text and self.is_valid_transcription(text):
                self.logger.info(f"Transcribed: {text}")
                self.type_text(text)
            else:
                self.logger.info(f"Filtered out: '{text}'")

        except Exception as e:
            self.logger.error(f"Error processing speech: {e}")
            import traceback
            self.logger.error(traceback.format_exc())

    def is_valid_transcription(self, text):
        """Filter out Whisper hallucinations"""
        # Common Whisper hallucinations
        noise_patterns = [
            "thank you", "thanks for watching", "subscribe", "bye",
            "music", "[music]", "applause", "[applause]",
            "foreign", "[foreign]", "blank", "[blank]"
        ]

        text_lower = text.lower().strip()

        if len(text) < 2:
            return False

        if len(set(text.replace(" ", ""))) < 2:
            return False

        if text_lower in noise_patterns:
            return False

        if all(c in ".,!?;: " for c in text):
            return False

        return True

    def type_text(self, text):
        """Type transcribed text"""
        try:
            if self.config["auto_punctuation"] and not text.endswith(('.', '!', '?')):
                text += " "
            else:
                text += " "

            pyautogui.typewrite(text, interval=0.005)

        except Exception as e:
            self.logger.error(f"Error typing text: {e}")

    def process_audio_stream(self):
        """Process audio stream from parecord"""
        try:
            while self.parecord_process and self.parecord_process.poll() is None:
                # Read chunk of audio
                raw_data = self.parecord_process.stdout.read(self.CHUNK_SIZE)
                if not raw_data:
                    continue

                # Convert to numpy array
                audio_data = np.frombuffer(raw_data, dtype=np.int16).astype(np.float32) / 32768.0

                # Add to ring buffer for pre-recording
                self.audio_ring_buffer.append(audio_data)

                # Calculate RMS
                rms = self.calculate_rms(audio_data)

                # Voice activity detection
                if rms > self.SILENCE_THRESHOLD:
                    # Voice detected
                    if not self.is_recording:
                        self.start_recording()
                    self.silence_start = None
                    self.audio_buffer.append(audio_data)
                else:
                    # Silence detected
                    if self.is_recording:
                        if self.silence_start is None:
                            self.silence_start = time.time()
                        elif time.time() - self.silence_start > self.SILENCE_DURATION:
                            # End of speech
                            self.stop_recording()
                        else:
                            # Still recording during short silence
                            self.audio_buffer.append(audio_data)

        except Exception as e:
            self.logger.error(f"Error processing audio stream: {e}")

    def run(self):
        """Main loop"""
        self.logger.info("=" * 50)
        self.logger.info("Starting GPU-Optimized Dictation Service")
        self.logger.info(f"Model Type: {'Faster Whisper' if self.using_faster_whisper else 'OpenAI Whisper'}")
        self.logger.info(f"Model: {self.config['whisper_model']}")
        self.logger.info(f"Device: {self.device.upper()}")
        self.logger.info(f"FP16: {self.fp16}")
        self.logger.info(f"Model Path: {self.get_model_path()}")
        self.logger.info(f"Pre-record buffer: {self.PRE_RECORD_SECONDS}s")
        self.logger.info("=" * 50)

        # Start parecord
        cmd = [
            'parecord',
            f'--device={self.DEVICE}',
            '--format=s16le',
            f'--rate={self.RATE}',
            f'--channels={self.CHANNELS}',
            '--raw',
            '--latency-msec=10'
        ]

        try:
            self.parecord_process = subprocess.Popen(
                cmd,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                bufsize=0
            )

            time.sleep(0.5)
            if self.parecord_process.poll() is not None:
                stderr = self.parecord_process.stderr.read().decode()
                self.logger.error(f"parecord failed: {stderr}")
                sys.exit(1)

            self.logger.info("Listening for speech...")
            self.process_audio_stream()

        except KeyboardInterrupt:
            self.logger.info("Interrupted")
        finally:
            self.cleanup()

    def cleanup(self, signum=None, frame=None):
        """Cleanup on exit"""
        self.logger.info("Shutting down")

        if self.is_recording:
            self.stop_recording()

        if self.parecord_process:
            try:
                self.parecord_process.terminate()
                self.parecord_process.wait(timeout=2)
            except:
                self.parecord_process.kill()
                self.parecord_process.wait()

        # Clear GPU cache
        if self.device == "cuda":
            torch.cuda.empty_cache()

        for f in [self.state_file, self.pid_file, '/tmp/dictation-recording']:
            try:
                os.remove(f)
            except:
                pass

        sys.exit(0)

if __name__ == "__main__":
    service = DictationService()
    service.run()