#!/usr/bin/env python3
"""
Whisper Model Test Script
Tests if Whisper models are properly installed and working
"""

import sys
import os
import time
import json
import argparse
from pathlib import Path

# Add color support
class Colors:
    GREEN = '\033[0;32m'
    RED = '\033[0;31m'
    YELLOW = '\033[1;33m'
    BLUE = '\033[0;34m'
    CYAN = '\033[0;36m'
    NC = '\033[0m'  # No Color

def print_colored(message, color):
    print(f"{color}{message}{Colors.NC}")

def test_imports():
    """Test if required packages can be imported"""
    print_colored("\n=== Testing Python Imports ===", Colors.BLUE)
    
    imports = {
        'torch': 'PyTorch',
        'whisper': 'OpenAI Whisper',
        'pyautogui': 'PyAutoGUI',
        'scipy': 'SciPy',
        'numpy': 'NumPy'
    }
    
    failed = []
    for module, name in imports.items():
        try:
            __import__(module)
            print_colored(f"✓ {name}", Colors.GREEN)
        except ImportError as e:
            print_colored(f"✗ {name}: {e}", Colors.RED)
            failed.append(name)
    
    # Optional imports
    print_colored("\nOptional imports:", Colors.YELLOW)
    try:
        import faster_whisper
        print_colored("✓ Faster Whisper", Colors.GREEN)
    except ImportError:
        print_colored("- Faster Whisper (not installed)", Colors.YELLOW)
    
    return len(failed) == 0

def test_gpu():
    """Test GPU availability"""
    print_colored("\n=== Testing GPU Support ===", Colors.BLUE)
    
    try:
        import torch
        
        if torch.cuda.is_available():
            print_colored(f"✓ CUDA available", Colors.GREEN)
            print(f"  Device: {torch.cuda.get_device_name(0)}")
            print(f"  Memory: {torch.cuda.get_device_properties(0).total_memory / 1024**3:.1f} GB")
            print(f"  CUDA version: {torch.version.cuda}")
            return True
        else:
            print_colored("- No GPU detected (CPU mode will be used)", Colors.YELLOW)
            return False
    except Exception as e:
        print_colored(f"✗ Error checking GPU: {e}", Colors.RED)
        return False

def test_config():
    """Test configuration file"""
    print_colored("\n=== Testing Configuration ===", Colors.BLUE)
    
    config_path = Path.home() / ".config" / "dictation-service" / "config.json"
    
    if not config_path.exists():
        print_colored(f"✗ Config file not found: {config_path}", Colors.RED)
        return None
    
    try:
        with open(config_path, 'r') as f:
            config = json.load(f)
        
        print_colored("✓ Config file loaded successfully", Colors.GREEN)
        print(f"  Model: {config.get('whisper_model', 'not set')}")
        print(f"  Language: {config.get('language', 'auto-detect')}")
        print(f"  Model path: {config.get('model_base_path', 'not set')}")
        
        return config
    except Exception as e:
        print_colored(f"✗ Error reading config: {e}", Colors.RED)
        return None

def test_models(config):
    """Test if Whisper models are available"""
    print_colored("\n=== Testing Whisper Models ===", Colors.BLUE)
    
    if not config:
        print_colored("✗ No configuration available", Colors.RED)
        return False
    
    model_base = Path(config.get('model_base_path', '~/whisper-models')).expanduser()
    model_name = config.get('whisper_model', 'base')
    use_faster = config.get('use_faster_whisper', False)
    
    if not model_base.exists():
        print_colored(f"✗ Model directory not found: {model_base}", Colors.RED)
        return False
    
    # Check for models
    print(f"Looking for models in: {model_base}")
    
    found_models = []
    
    # Check OpenAI models
    for model_dir in model_base.glob("openai-whisper-*"):
        for model_file in model_dir.glob("*.pt"):
            found_models.append(('openai', model_file))
            print_colored(f"  ✓ Found OpenAI model: {model_file.name}", Colors.GREEN)
    
    # Check Faster Whisper models
    for model_dir in model_base.glob("faster-whisper-*"):
        if (model_dir / "model.bin").exists():
            found_models.append(('faster', model_dir))
            print_colored(f"  ✓ Found Faster Whisper model: {model_dir.name}", Colors.GREEN)
    
    if not found_models:
        print_colored("✗ No models found!", Colors.RED)
        print(f"  Download models to: {model_base}")
        print(f"  Use: ./download_whisper_models.sh")
        return False
    
    return True

def test_transcription(config):
    """Test actual transcription with a sample"""
    print_colored("\n=== Testing Transcription ===", Colors.BLUE)
    
    if not config:
        print_colored("✗ No configuration available", Colors.RED)
        return False
    
    try:
        import whisper
        import torch
        import numpy as np
        
        # Try to load the model
        model_name = config.get('whisper_model', 'base')
        model_base = Path(config.get('model_base_path', '~/whisper-models')).expanduser()
        
        # Find model file
        model_path = None
        for model_dir in model_base.glob(f"openai-whisper-{model_name}"):
            for model_file in model_dir.glob("*.pt"):
                model_path = model_file
                break
        
        if not model_path:
            # Try finding any model
            for model_dir in model_base.glob("openai-whisper-*"):
                for model_file in model_dir.glob("*.pt"):
                    model_path = model_file
                    print_colored(f"Using alternative model: {model_file.name}", Colors.YELLOW)
                    break
                if model_path:
                    break
        
        if not model_path:
            print_colored("✗ No model file found to test", Colors.RED)
            return False
        
        print(f"Loading model: {model_path}")
        device = "cuda" if torch.cuda.is_available() else "cpu"
        
        # Load model
        start_time = time.time()
        model = whisper.load_model(str(model_path), device=device)
        load_time = time.time() - start_time
        print_colored(f"✓ Model loaded in {load_time:.1f}s", Colors.GREEN)
        
        # Create a test audio (1 second of silence)
        print("Testing with sample audio...")
        sample_rate = 16000
        duration = 1.0
        audio = np.zeros(int(sample_rate * duration), dtype=np.float32)
        
        # Add a small beep
        freq = 440  # A4 note
        t = np.linspace(0, 0.1, int(sample_rate * 0.1))
        beep = 0.1 * np.sin(2 * np.pi * freq * t)
        audio[:len(beep)] = beep
        
        # Transcribe
        start_time = time.time()
        result = model.transcribe(audio, fp16=False)
        trans_time = time.time() - start_time
        
        print_colored(f"✓ Transcription completed in {trans_time:.2f}s", Colors.GREEN)
        print(f"  Result: '{result['text'].strip()}'")
        
        return True
        
    except Exception as e:
        print_colored(f"✗ Transcription test failed: {e}", Colors.RED)
        import traceback
        traceback.print_exc()
        return False

def main():
    parser = argparse.ArgumentParser(description='Test Whisper installation')
    parser.add_argument('--full', action='store_true', help='Run full transcription test')
    args = parser.parse_args()
    
    print_colored("=== Whisper Installation Test ===", Colors.CYAN)
    
    # Run tests
    tests_passed = 0
    tests_total = 0
    
    # Test imports
    tests_total += 1
    if test_imports():
        tests_passed += 1
    
    # Test GPU
    tests_total += 1
    if test_gpu():
        tests_passed += 1
    
    # Test config
    tests_total += 1
    config = test_config()
    if config:
        tests_passed += 1
    
    # Test models
    tests_total += 1
    if test_models(config):
        tests_passed += 1
    
    # Test transcription (only if requested)
    if args.full:
        tests_total += 1
        if test_transcription(config):
            tests_passed += 1
    
    # Summary
    print_colored(f"\n=== Summary ===", Colors.BLUE)
    print(f"Tests passed: {tests_passed}/{tests_total}")
    
    if tests_passed == tests_total:
        print_colored("All tests passed! ✓", Colors.GREEN)
        return 0
    else:
        print_colored("Some tests failed. Please check the installation.", Colors.YELLOW)
        return 1

if __name__ == "__main__":
    sys.exit(main())