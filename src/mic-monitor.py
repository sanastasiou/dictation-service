#!/usr/bin/env python3
"""
Microphone Activity Monitor - Device Selective Version
Monitors specific microphone usage and displays visual indicators
"""

import subprocess
import signal
import sys
import time
import os
import json
import logging
from datetime import datetime
from pathlib import Path

class MicrophoneMonitor:
    def __init__(self):
        self.config_dir = Path.home() / ".config" / "mic-monitor"
        self.log_dir = Path.home() / ".local" / "share" / "mic-monitor" / "logs"
        self.config_file = self.config_dir / "config.json"
        self.state_file = "/tmp/mic-monitor-state"
        self.indicator_pid_file = "/tmp/mic-indicator-pid"

        # Setup logging
        self.setup_logging()

        # Load configuration
        self.config = self.load_config()

        # State tracking
        self.mic_active = False
        self.indicator_process = None

        # Signal handlers
        signal.signal(signal.SIGTERM, self.cleanup)
        signal.signal(signal.SIGINT, self.cleanup)

        # Set display environment
        self.setup_display_env()

    def setup_display_env(self):
        """Ensure display environment is set correctly"""
        if 'DISPLAY' not in os.environ:
            os.environ['DISPLAY'] = ':0'

        # Try to get Xauthority
        xauth_locations = [
            Path.home() / '.Xauthority',
            f"/run/user/{os.getuid()}/gdm/Xauthority",
            f"/tmp/.X11-unix/X0"
        ]

        for xauth in xauth_locations:
            if Path(xauth).exists():
                os.environ['XAUTHORITY'] = str(xauth)
                break

        self.logger.info(f"Display environment: DISPLAY={os.environ.get('DISPLAY')}, "
                        f"XAUTHORITY={os.environ.get('XAUTHORITY')}")

    def setup_logging(self):
        """Configure logging"""
        self.log_dir.mkdir(parents=True, exist_ok=True)
        log_file = self.log_dir / f"mic-monitor-{datetime.now():%Y%m%d}.log"

        logging.basicConfig(
            level=logging.DEBUG,
            format='%(asctime)s - %(levelname)s - %(message)s',
            handlers=[
                logging.FileHandler(log_file),
                logging.StreamHandler(sys.stdout)
            ]
        )
        self.logger = logging.getLogger(__name__)

    def load_config(self):
        """Load configuration from file"""
        default_config = {
            "check_interval": 0.5,
            "indicator_type": "tray",  # tray, notification, osd
            "show_app_name": True,
            "log_activity": True,
            "position": "top-right",
            "monitor_all_devices": True,  # New option
            "monitor_device": "",  # Device name pattern to monitor
            "ignore_devices": []  # List of device patterns to ignore
        }

        if self.config_file.exists():
            try:
                with open(self.config_file, 'r') as f:
                    config = json.load(f)
                    return {**default_config, **config}
            except Exception as e:
                self.logger.error(f"Failed to load config: {e}")

        return default_config

    def get_audio_source_info(self):
        """Get detailed information about active audio sources"""
        try:
            # Get list of all sources
            sources_result = subprocess.run(
                ['pactl', 'list', 'sources'],
                capture_output=True,
                text=True,
                check=True
            )

            # Parse sources to get their names and descriptions
            sources = {}
            current_source = None

            for line in sources_result.stdout.split('\n'):
                if line.startswith('Source #'):
                    current_source = line.split('#')[1].strip()
                    sources[current_source] = {}
                elif current_source and 'Name:' in line:
                    sources[current_source]['name'] = line.split('Name:')[1].strip()
                elif current_source and 'Description:' in line:
                    sources[current_source]['description'] = line.split('Description:')[1].strip()

            return sources

        except subprocess.CalledProcessError as e:
            self.logger.error(f"Failed to get source info: {e}")
            return {}

    def check_mic_activity(self):
        """Check if specific microphone is being used"""
        try:
            # Get list of active source outputs
            result = subprocess.run(
                ['pactl', 'list', 'source-outputs'],
                capture_output=True,
                text=True,
                check=True
            )

            if not result.stdout.strip():
                return False, None

            # Get source information
            sources = self.get_audio_source_info()

            # Parse source outputs
            outputs = result.stdout.split('Source Output #')

            for output in outputs[1:]:  # Skip first empty element
                lines = output.split('\n')
                app_name = "Unknown"
                source_id = None

                # Extract app name and source
                for line in lines:
                    if "application.name" in line:
                        start = line.find('"') + 1
                        end = line.rfind('"')
                        if start > 0 and end > start:
                            app_name = line[start:end]
                    elif "Source:" in line and "Source Output" not in line:
                        source_id = line.split('Source:')[1].strip()

                # Check if we should monitor this device
                if source_id and source_id in sources:
                    source_info = sources[source_id]
                    device_name = source_info.get('name', '')
                    device_desc = source_info.get('description', '')

                    self.logger.debug(f"Active recording: {app_name} on device: {device_desc}")

                    # Check monitoring rules
                    if not self.config["monitor_all_devices"]:
                        # Check if this is the device we want to monitor
                        monitor_pattern = self.config["monitor_device"].lower()
                        if monitor_pattern:
                            if (monitor_pattern not in device_name.lower() and
                                monitor_pattern not in device_desc.lower()):
                                self.logger.debug(f"Ignoring device: {device_desc}")
                                continue

                    # Check ignore list
                    for ignore_pattern in self.config.get("ignore_devices", []):
                        if (ignore_pattern.lower() in device_name.lower() or
                            ignore_pattern.lower() in device_desc.lower()):
                            self.logger.debug(f"Ignoring device by rule: {device_desc}")
                            continue

                    # If we got here, we should show indicator
                    return True, f"{app_name} ({device_desc})"

            return False, None

        except subprocess.CalledProcessError as e:
            self.logger.error(f"Failed to check mic status: {e}")
            return False, None

    def show_indicator(self, app_name="Unknown"):
        """Show microphone activity indicator"""
        self.logger.info(f"Showing indicator for: {app_name}")
        indicator_type = self.config["indicator_type"]

        try:
            if indicator_type == "tray":
                # Kill any existing indicator first
                self.hide_indicator()

                # System tray icon
                cmd = [
                    'yad',
                    '--notification',
                    '--image=audio-input-microphone',
                    f'--text={app_name}',
                    '--no-middle'
                ]

                self.logger.debug(f"Running command: {' '.join(cmd)}")

                # Run with proper environment
                env = os.environ.copy()
                self.indicator_process = subprocess.Popen(
                    cmd,
                    env=env,
                    stdout=subprocess.PIPE,
                    stderr=subprocess.PIPE
                )

                self.logger.info(f"Indicator process started with PID: {self.indicator_process.pid}")

                # Save PID to file
                with open(self.indicator_pid_file, 'w') as f:
                    f.write(str(self.indicator_process.pid))

            elif indicator_type == "notification":
                # Desktop notification
                subprocess.run([
                    'notify-send',
                    '-u', 'critical',
                    '-i', 'audio-input-microphone',
                    'Microphone Active',
                    app_name
                ])

            # Write state
            with open(self.state_file, 'w') as f:
                f.write(f"ACTIVE:{app_name}")

            # Log activity
            if self.config["log_activity"]:
                self.logger.info(f"Microphone activated: {app_name}")

        except Exception as e:
            self.logger.error(f"Failed to show indicator: {e}")
            self.logger.error(f"Exception details: {type(e).__name__}: {str(e)}")

    def hide_indicator(self):
        """Hide microphone activity indicator"""
        try:
            # Kill tray indicator if exists
            if self.indicator_process and self.config["indicator_type"] == "tray":
                try:
                    self.indicator_process.terminate()
                    try:
                        self.indicator_process.wait(timeout=2)
                    except subprocess.TimeoutExpired:
                        self.indicator_process.kill()
                        self.indicator_process.wait()
                except Exception as e:
                    self.logger.debug(f"Error terminating indicator: {e}")
                finally:
                    self.indicator_process = None
                    self.logger.info("Indicator process terminated")

            # Clear notification
            if self.config["indicator_type"] == "notification":
                subprocess.run(['notify-send', '-u', 'low', 'Microphone Inactive'])

            # Remove state file
            if os.path.exists(self.state_file):
                os.remove(self.state_file)

            # Remove PID file
            if os.path.exists(self.indicator_pid_file):
                os.remove(self.indicator_pid_file)

            # Log
            if self.config["log_activity"]:
                self.logger.info("Microphone deactivated")

        except Exception as e:
            self.logger.error(f"Failed to hide indicator: {e}")

    def run(self):
        """Main monitoring loop"""
        self.logger.info("Microphone monitor started")
        self.logger.info(f"Config: {self.config}")

        if not self.config["monitor_all_devices"]:
            self.logger.info(f"Monitoring only devices matching: {self.config['monitor_device']}")
        if self.config.get("ignore_devices"):
            self.logger.info(f"Ignoring devices: {self.config['ignore_devices']}")

        while True:
            try:
                is_active, app_info = self.check_mic_activity()

                if is_active and not self.mic_active:
                    # Microphone just activated
                    self.mic_active = True
                    self.show_indicator(app_info)

                elif not is_active and self.mic_active:
                    # Microphone just deactivated
                    self.mic_active = False
                    self.hide_indicator()

                time.sleep(self.config["check_interval"])

            except KeyboardInterrupt:
                break
            except Exception as e:
                self.logger.error(f"Monitor error: {e}")
                time.sleep(1)

    def cleanup(self, signum=None, frame=None):
        """Cleanup on exit"""
        self.logger.info("Shutting down microphone monitor")
        self.hide_indicator()
        sys.exit(0)

if __name__ == "__main__":
    monitor = MicrophoneMonitor()
    monitor.run()
