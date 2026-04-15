#!/usr/bin/env python3
"""
Bluetooth SPP Server for Raspberry Pi
Handles mobile app pairing, preference sync, and launching rpi.py.

Boot behaviour:
  - If preferences.json exists  → rpi.py starts immediately (standalone mode).
  - If no cached preferences    → rpi.py starts after the first PREFS: message.
  - Bluetooth disconnect        → rpi.py keeps running with cached preferences.
  - App reconnect               → fresh preferences are requested and saved;
                                  rpi.py picks them up on the next button press.
"""

import bluetooth
import sys
import os
import signal
import time
import subprocess
import json
import threading

try:
    import ocr_scanner
    OCR_AVAILABLE = True
    print("[INFO] OCR scanner module loaded")
except ImportError:
    OCR_AVAILABLE = False
    print("[INFO] ocr_scanner not available — install pytesseract + pillow on the Pi")

# ── Paths ─────────────────────────────────────────────────────────────────────
_DIR        = os.path.dirname(os.path.abspath(__file__))
RPI_SCRIPT  = os.path.join(_DIR, 'rpi.py')
PREFS_FILE  = os.path.join(_DIR, 'preferences.json')

# ── Globals ───────────────────────────────────────────────────────────────────
server_sock         = None
client_sock         = None          # currently connected app socket
current_client_sock = None          # same ref used by the stdout-reader thread
rpi_process         = None
current_prefs       = {"preferred": [], "allergies": []}


# ── rpi.py subprocess helpers ─────────────────────────────────────────────────

def _rpi_stdout_reader(process):
    """
    Background thread: read rpi.py stdout line-by-line.
    Lines prefixed with 'BT:' are stripped and forwarded to the currently
    connected app socket.  All other lines are printed as [RPI] logs.
    """
    try:
        for raw in iter(process.stdout.readline, b''):
            line = raw.decode('utf-8', errors='replace').rstrip('\r\n')
            if line.startswith('BT:'):
                payload = line[3:]
                sock = current_client_sock      # read the live reference
                if sock is not None:
                    try:
                        sock.send((payload + '\n').encode('utf-8'))
                        print(f"[RPI→APP] {payload[:120]}")
                    except Exception as e:
                        print(f"[WARNING] Could not forward to app: {e}")
                else:
                    print(f"[RPI→APP (no client)] {payload[:120]}")
            else:
                if line:
                    print(f"[RPI] {line}")
    except Exception as e:
        print(f"[INFO] rpi.py stdout reader stopped: {e}")


def start_rpi_script():
    """Launch rpi.py as a background subprocess if it is not already running."""
    global rpi_process
    if rpi_process is not None and rpi_process.poll() is None:
        print("[INFO] rpi.py is already running")
        return
    try:
        rpi_process = subprocess.Popen(
            [sys.executable, RPI_SCRIPT],
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
        )
        print(f"[INFO] Started rpi.py (pid {rpi_process.pid})")
        t = threading.Thread(target=_rpi_stdout_reader, args=(rpi_process,), daemon=True)
        t.start()
    except Exception as e:
        print(f"[ERROR] Failed to start rpi.py: {e}")
        rpi_process = None


def stop_rpi_script():
    """Terminate the rpi.py subprocess if it is running."""
    global rpi_process
    if rpi_process is None:
        return
    if rpi_process.poll() is None:
        rpi_process.terminate()
        try:
            rpi_process.wait(timeout=5)
        except subprocess.TimeoutExpired:
            rpi_process.kill()
        print("[INFO] rpi.py stopped")
    rpi_process = None


# ── Preferences helpers ───────────────────────────────────────────────────────

def load_cached_prefs():
    """Load preferences from the local cache file (returns empty dict on failure)."""
    try:
        with open(PREFS_FILE) as f:
            return json.load(f)
    except Exception:
        return {"preferred": [], "allergies": []}


def save_prefs(prefs):
    """Persist preferences to disk so rpi.py can load them independently."""
    try:
        with open(PREFS_FILE, 'w') as f:
            json.dump(prefs, f)
    except Exception as e:
        print(f"[PREFS] Could not save to disk: {e}")


# ── Signal / cleanup ──────────────────────────────────────────────────────────

def cleanup(signum=None, frame=None):
    print("\n[INFO] Shutting down Bluetooth server...")
    stop_rpi_script()
    if client_sock:
        try:
            client_sock.close()
        except Exception:
            pass
    if server_sock:
        try:
            server_sock.close()
        except Exception:
            pass
    sys.exit(0)


signal.signal(signal.SIGINT, cleanup)
signal.signal(signal.SIGTERM, cleanup)


# ── Bluetooth setup ───────────────────────────────────────────────────────────

def setup_bluetooth():
    print("[INFO] Setting up Bluetooth adapter...")
    commands = [
        ("sudo hciconfig hci0 up",       "Powering on Bluetooth adapter"),
        ("sudo hciconfig hci0 piscan",   "Making Bluetooth discoverable"),
        ("sudo hciconfig hci0 sspmode 1","Enabling Simple Pairing mode"),
    ]
    for cmd, description in commands:
        try:
            print(f"[INFO] {description}...")
            result = subprocess.run(cmd, shell=True, capture_output=True, text=True, timeout=5)
            if result.returncode == 0:
                print(f"[SUCCESS] {description}")
            else:
                print(f"[WARNING] {description} failed: {result.stderr.strip()}")
        except subprocess.TimeoutExpired:
            print(f"[WARNING] {description} timed out")
        except Exception as e:
            print(f"[WARNING] {description} error: {e}")
    time.sleep(1)
    print("[SUCCESS] Bluetooth adapter setup complete\n")


def get_bluetooth_address():
    try:
        result = subprocess.run(['hciconfig', 'hci0'], capture_output=True, text=True, timeout=5)
        for line in result.stdout.split('\n'):
            if 'BD Address:' in line:
                return line.split('BD Address:')[1].strip().split()[0]
        return None
    except Exception as e:
        print(f"[WARNING] Could not get BD address via hciconfig: {e}")
        return None


# ── Message handlers ──────────────────────────────────────────────────────────

def handle_get_ip(sock):
    try:
        result = subprocess.run(['hostname', '-I'], capture_output=True, text=True, timeout=5)
        if result.returncode == 0 and result.stdout.strip():
            ip_address = result.stdout.strip().split()[0]
            sock.send(f"IP:{ip_address}\n".encode('utf-8'))
            print(f"[INFO] Sent IP address: {ip_address}")
        else:
            sock.send(b"IP:unknown\n")
    except Exception as e:
        sock.send(f"ERROR: Failed to get IP: {e}\n".encode('utf-8'))


def handle_prefs(json_str):
    """Store food preferences received from the app and start rpi.py if needed."""
    global current_prefs
    try:
        prefs = json.loads(json_str)
        if not isinstance(prefs, dict):
            raise ValueError("Expected a JSON object")
        current_prefs = prefs
        save_prefs(prefs)
        if OCR_AVAILABLE:
            ocr_scanner.save_preferences(prefs)
        n_pref = len(prefs.get('preferred', []))
        n_alrg = len(prefs.get('allergies', []))
        print(f"[PREFS] Updated — {n_pref} preferred food(s), {n_alrg} allerg(y/ies)")
        # Start rpi.py now that we have preferences (no-op if already running)
        start_rpi_script()
    except Exception as e:
        print(f"[PREFS] Failed to parse preferences: {e}")


def handle_scan(sock):
    if not OCR_AVAILABLE:
        sock.send(b'SCAN_RESULT:{"safe":null,"allergens_found":[],"preferred_found":[],"summary":"OCR not installed on Pi.","raw_text":""}\n')
        return
    sock.send(b"SCANNING\n")
    print("[SCAN] Starting capture + OCR...")
    result = ocr_scanner.scan_and_filter(current_prefs)
    result_json = json.dumps(result, ensure_ascii=False)
    sock.send(f"SCAN_RESULT:{result_json}\n".encode('utf-8'))
    print(f"[SCAN] Done — {result['summary']}")


def handle_wifi_config(sock, message):
    try:
        parts = message.split(':', 2)
        if len(parts) != 3:
            sock.send(b"ERROR: Invalid WiFi format. Expected WIFI:SSID:PASSWORD\n")
            return
        ssid     = parts[1]
        password = parts[2]
        print(f"[WIFI] Configuring WiFi: SSID='{ssid}'")
        sock.send(f"Configuring WiFi network: {ssid}\n".encode('utf-8'))
        configure_wifi(sock, ssid, password)
    except Exception as e:
        sock.send(f"ERROR: WiFi configuration failed: {e}\n".encode('utf-8'))


def handle_client(sock):
    """Receive and route messages from the connected app."""
    print("[INFO] Client connected. Requesting preferences...")
    # Ask the app to send preferences immediately
    try:
        sock.send(b"REQUEST_PREFS\n")
    except Exception as e:
        print(f"[WARNING] Could not send REQUEST_PREFS: {e}")

    try:
        while True:
            data = sock.recv(1024)
            if not data:
                print("[INFO] Client sent empty data (disconnecting)")
                break
            try:
                message = data.decode('utf-8').strip()
                print(f"[RECEIVED] {message}")
                if message.startswith('WIFI:'):
                    handle_wifi_config(sock, message)
                elif message == 'GET_IP':
                    handle_get_ip(sock)
                elif message.startswith('PREFS:'):
                    handle_prefs(message[6:])
                elif message == 'SCAN':
                    handle_scan(sock)
                else:
                    sock.send(f"Pi received: {message}\n".encode('utf-8'))
            except UnicodeDecodeError:
                print(f"[RECEIVED] Binary data ({len(data)} bytes)")
                sock.send(b"ACK\n")
    except bluetooth.BluetoothError as e:
        if "104" in str(e) or "Connection reset" in str(e):
            print("[INFO] Client disconnected")
        else:
            print(f"[ERROR] Bluetooth error: {e}")
    except Exception as e:
        print(f"[ERROR] Error handling client: {e}")


# ── Main server loop ──────────────────────────────────────────────────────────

def start_server():
    global server_sock, client_sock, current_client_sock, current_prefs

    # ── Load cached preferences and start rpi.py immediately if available ─────
    if os.path.exists(PREFS_FILE):
        current_prefs = load_cached_prefs()
        n_pref = len(current_prefs.get('preferred', []))
        n_alrg = len(current_prefs.get('allergies', []))
        print(f"[INFO] Loaded cached preferences: {n_pref} preferred, {n_alrg} allergies")
        print("[INFO] Starting rpi.py in standalone mode...")
        start_rpi_script()
    else:
        print("[INFO] No cached preferences found — rpi.py will start after first app connection")

    # ── Setup Bluetooth ───────────────────────────────────────────────────────
    setup_bluetooth()

    local_addr = None
    try:
        local_addr, _ = bluetooth.read_local_bdaddr()
        print(f"[INFO] Local Bluetooth adapter: {local_addr}")
    except Exception:
        local_addr = get_bluetooth_address()
        if local_addr:
            print(f"[INFO] Local Bluetooth adapter (via hciconfig): {local_addr}")

    server_sock = bluetooth.BluetoothSocket(bluetooth.RFCOMM)

    try:
        if local_addr:
            server_sock.bind((local_addr, bluetooth.PORT_ANY))
        else:
            server_sock.bind(("", bluetooth.PORT_ANY))
    except Exception:
        server_sock.bind(("", bluetooth.PORT_ANY))

    port = server_sock.getsockname()[1]
    server_sock.listen(1)

    uuid = "00001101-0000-1000-8000-00805F9B34FB"
    try:
        bluetooth.advertise_service(
            server_sock, "RPI Bridge Server",
            service_id=uuid,
            service_classes=[uuid, bluetooth.SERIAL_PORT_CLASS],
            profiles=[bluetooth.SERIAL_PORT_PROFILE],
        )
    except bluetooth.BluetoothError as e:
        print(f"[ERROR] Failed to advertise Bluetooth service: {e}")
        print("\nCommon fixes:")
        print("  sudo bluetoothctl → power on / discoverable on")
        print("  sudo systemctl start bluetooth")
        server_sock.close()
        sys.exit(1)

    print(f"[INFO] Bluetooth SPP Server started on RFCOMM port {port}")
    print(f"[INFO] Waiting for connections...")

    try:
        while True:
            client_sock, client_info = server_sock.accept()
            print(f"\n[SUCCESS] App connected from {client_info}")
            current_client_sock = client_sock   # make socket visible to stdout reader

            try:
                handle_client(client_sock)
            except bluetooth.BluetoothError as e:
                print(f"[ERROR] Bluetooth error: {e}")
            except Exception as e:
                print(f"[ERROR] Client handler error: {e}")
            finally:
                # Clear socket reference — rpi.py keeps running independently
                current_client_sock = None
                if client_sock:
                    try:
                        client_sock.close()
                    except Exception:
                        pass
                    client_sock = None
                print("[INFO] App disconnected. rpi.py continues running. Waiting for reconnect...")

    except KeyboardInterrupt:
        cleanup()
    except Exception as e:
        print(f"[ERROR] Server error: {e}")
        cleanup()


# ── WiFi helpers (unchanged) ──────────────────────────────────────────────────

def uses_networkmanager():
    try:
        result = subprocess.run(['systemctl', 'is-active', 'NetworkManager'],
                                capture_output=True, text=True, timeout=5)
        return result.stdout.strip() == 'active'
    except Exception:
        return False


def configure_wifi_networkmanager(sock, ssid, password):
    sock.send(b"Using NetworkManager to configure WiFi...\n")
    subprocess.run(['sudo', 'nmcli', 'device', 'wifi', 'rescan'], capture_output=True, timeout=10)
    time.sleep(3)
    subprocess.run(['sudo', 'nmcli', 'connection', 'delete', ssid], capture_output=True, timeout=10)
    sock.send(f"Connecting to WiFi network: {ssid}...\n".encode('utf-8'))
    cmd = (['sudo', 'nmcli', 'device', 'wifi', 'connect', ssid, 'password', password]
           if password else
           ['sudo', 'nmcli', 'device', 'wifi', 'connect', ssid])
    result = subprocess.run(cmd, capture_output=True, text=True, timeout=30)
    if result.returncode == 0:
        return result.stdout.strip()
    sock.send(b"Network not visible. Creating saved profile...\n")
    cmd = (['sudo', 'nmcli', 'connection', 'add', 'type', 'wifi',
            'con-name', ssid, 'ssid', ssid,
            'wifi-sec.key-mgmt', 'wpa-psk', 'wifi-sec.psk', password,
            'connection.autoconnect', 'yes']
           if password else
           ['sudo', 'nmcli', 'connection', 'add', 'type', 'wifi',
            'con-name', ssid, 'ssid', ssid, 'connection.autoconnect', 'yes'])
    result = subprocess.run(cmd, capture_output=True, text=True, timeout=30)
    if result.returncode != 0:
        raise Exception(f"nmcli failed: {result.stderr.strip()}")
    sock.send(b"WiFi profile saved. Will connect when network is in range.\n")
    return result.stdout.strip()


def configure_wifi_wpa_supplicant(sock, ssid, password):
    wpa_conf = '/etc/wpa_supplicant/wpa_supplicant.conf'
    if not os.path.exists(wpa_conf):
        sock.send(b"Creating wpa_supplicant.conf...\n")
        base = 'ctrl_interface=DIR=/var/run/wpa_supplicant GROUP=netdev\nupdate_config=1\ncountry=US\n'
        with open('/tmp/wpa_base.conf', 'w') as f:
            f.write(base)
        subprocess.run(['sudo', 'cp', '/tmp/wpa_base.conf', wpa_conf], timeout=5, check=True)
        os.remove('/tmp/wpa_base.conf')
    if password:
        sock.send(b"Generating WPA configuration...\n")
        result = subprocess.run(['wpa_passphrase', ssid, password],
                                capture_output=True, text=True, timeout=5)
        if result.returncode != 0:
            raise Exception(f"wpa_passphrase failed: {result.stderr}")
        subprocess.run(['sudo', 'cp', wpa_conf, f'{wpa_conf}.backup'], timeout=5)
        with open('/tmp/wifi_network.conf', 'w') as f:
            f.write(f'\n# Added by Bluetooth WiFi Setup\n{result.stdout}\n')
        subprocess.run(['sudo', 'bash', '-c', f'cat /tmp/wifi_network.conf >> {wpa_conf}'],
                       timeout=5, check=True)
        os.remove('/tmp/wifi_network.conf')
    else:
        with open('/tmp/wifi_network.conf', 'w') as f:
            f.write(f'\nnetwork={{\n    ssid="{ssid}"\n    key_mgmt=NONE\n}}\n')
        subprocess.run(['sudo', 'bash', '-c', f'cat /tmp/wifi_network.conf >> {wpa_conf}'],
                       timeout=5, check=True)
        os.remove('/tmp/wifi_network.conf')
    subprocess.run(['sudo', 'wpa_cli', '-i', 'wlan0', 'reconfigure'], timeout=5, check=True)


def configure_wifi(sock, ssid, password):
    try:
        if uses_networkmanager():
            print("[WIFI] Using NetworkManager")
            configure_wifi_networkmanager(sock, ssid, password)
        else:
            print("[WIFI] Using wpa_supplicant")
            configure_wifi_wpa_supplicant(sock, ssid, password)
        time.sleep(3)
        result = subprocess.run(['iwgetid', '-r'], capture_output=True, text=True, timeout=5)
        connected = result.stdout.strip()
        if connected == ssid:
            sock.send(f"SUCCESS: Connected to {ssid}!\n".encode('utf-8'))
        else:
            sock.send(f"WiFi configured. Current network: {connected or 'connecting...'}\n".encode('utf-8'))
    except subprocess.TimeoutExpired:
        sock.send(b"ERROR: WiFi configuration timed out\n")
    except Exception as e:
        sock.send(f"ERROR: {e}\n".encode('utf-8'))


# ── Entry point ───────────────────────────────────────────────────────────────

if __name__ == "__main__":
    print("=" * 60)
    print("  Raspberry Pi Bluetooth SPP Server")
    print("=" * 60)
    print()
    try:
        import bluetooth
    except ImportError:
        print("[ERROR] PyBluez not installed!")
        print("[FIX] Install it with: sudo pip3 install pybluez")
        sys.exit(1)
    start_server()
