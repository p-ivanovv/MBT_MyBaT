#!/usr/bin/env python3

import warnings
warnings.filterwarnings("ignore", category=RuntimeWarning, message=".*neon capable.*")

import os
import sys
import json
import time
import base64
import asyncio
import socket
from datetime import datetime

# ── Preferences ───────────────────────────────────────────────────────────────
PREFS_FILE = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'preferences.json')

def load_prefs():
    """
    Load food preferences from the shared cache file written by bt_server.py.
    Returns empty lists if the file does not exist or cannot be parsed.
    Called fresh on every food-label scan so updates from the app are picked up
    without restarting rpi.py.
    """
    try:
        with open(PREFS_FILE) as f:
            return json.load(f)
    except Exception:
        return {"preferred": [], "allergies": []}

# ── Optional OCR scanner ──────────────────────────────────────────────────────
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
try:
    import ocr_scanner
    OCR_AVAILABLE = True
    print("[INFO] ocr_scanner loaded — food filtering enabled")
except ImportError:
    OCR_AVAILABLE = False
    print("[WARNING] ocr_scanner not available — food filtering disabled")

# ── RPi-specific imports ───────────────────────────────────────────────────────
import RPi.GPIO as GPIO
from picamera2 import Picamera2
from libcamera import Transform, controls

# ── Google GenAI (lazy — initialised on first use) ────────────────────────────
try:
    import google.genai as genai
    GENAI_AVAILABLE = True
    print("[INFO] google.genai loaded")
except ImportError:
    genai = None
    GENAI_AVAILABLE = False
    print("[WARNING] google.genai not available — AI features disabled")

_genai_client = None

def _get_client():
    """Return a cached Gemini client, creating it on first call."""
    global _genai_client
    if _genai_client is not None:
        return _genai_client
    if not GENAI_AVAILABLE:
        raise RuntimeError("google.genai is not installed")
    api_key = os.getenv("GOOGLE_API_KEY")
    if not api_key:
        raise RuntimeError(
            "GOOGLE_API_KEY environment variable is not set. "
            "If running via sudo, use: sudo -E python3 bt_server.py"
        )
    _genai_client = genai.Client(api_key=api_key)
    print("[INFO] Gemini client initialised")
    return _genai_client


# ── TTS ───────────────────────────────────────────────────────────────────────

async def speak_text(text):
    try:
        import edge_tts
        os.environ["PYGAME_HIDE_SUPPORT_PROMPT"] = "1"
        import pygame

        cyrillic_count = sum(1 for ch in text if '\u0400' <= ch <= '\u04FF')
        voice = ("bg-BG-BorislavNeural"
                 if len(text) > 0 and cyrillic_count / len(text) > 0.2
                 else "en-US-AriaNeural")

        audio_file = "/tmp/tts_audio.mp3"
        communicate = edge_tts.Communicate(text, voice=voice)
        await communicate.save(audio_file)

        pygame.mixer.init()
        pygame.mixer.music.load(audio_file)
        pygame.mixer.music.play()
        while pygame.mixer.music.get_busy():
            await asyncio.sleep(0.1)
        pygame.mixer.music.unload()
        pygame.mixer.quit()

        if os.path.exists(audio_file):
            os.remove(audio_file)
    except Exception as e:
        print(f"[TTS] Error: {e}")


# ── Sensors ───────────────────────────────────────────────────────────────────

def get_distance(trig, echo, speed=34300, timeout=0.04):
    GPIO.output(trig, False)
    time.sleep(0.000002)
    GPIO.output(trig, True)
    time.sleep(0.00001)
    GPIO.output(trig, False)

    deadline = time.time() + timeout
    while GPIO.input(echo) == 0:
        if time.time() > deadline:
            return -1
    start = time.time()
    while GPIO.input(echo) == 1:
        if time.time() > deadline:
            return -1
    return (time.time() - start) * speed / 2


def has_internet(host="generativelanguage.googleapis.com", port=443, timeout=2.0):
    try:
        with socket.create_connection((host, port), timeout=timeout):
            return True
    except OSError:
        return False


# ── Gemini ────────────────────────────────────────────────────────────────────

def capture_and_send(picam2, prompt):
    """Capture an image, query Gemini, speak the response. Returns response text."""
    print("[BTN] Capturing image...")
    path = f"/tmp/img_{datetime.now().strftime('%H%M%S')}.jpg"
    picam2.capture_file(path)

    with open(path, "rb") as f:
        img = base64.b64encode(f.read()).decode()

    if not has_internet():
        print("[BTN] No internet — skipping Gemini")
        asyncio.run(speak_text("No internet connection. Please try again."))
        return None

    try:
        client = _get_client()
    except RuntimeError as e:
        print(f"[BTN] Gemini client error: {e}")
        asyncio.run(speak_text("AI not configured."))
        return None

    for attempt in range(2):
        try:
            response = client.models.generate_content(
                model="models/gemini-flash-lite-latest",
                contents=[{
                    "role": "user",
                    "parts": [
                        {"text": prompt},
                        {"inline_data": {"mime_type": "image/jpeg", "data": img}},
                    ],
                }],
            )
            print(f"[AI] {response.text[:120]}")
            asyncio.run(speak_text(response.text))
            return response.text
        except Exception as e:
            print(f"[BTN] Gemini error (attempt {attempt + 1}/2): {e}")
            if attempt == 0:
                time.sleep(1.0)

    asyncio.run(speak_text("AI service unavailable."))
    return None


# ── Food label scan ───────────────────────────────────────────────────────────

def scan_food_label(picam2):
    """
    Left-button: read food label via Gemini with allergen/preference context.
    Preferences are loaded fresh from disk on every call so that updates sent
    by the app via bt_server are picked up without restarting rpi.py.
    """
    print("[BTN] Left pressed — food label scan")

    prefs    = load_prefs()
    allergens = prefs.get("allergies", [])
    preferred = prefs.get("preferred", [])
    print(f"[PREFS] {len(allergens)} allergen(s), {len(preferred)} preferred food(s)")

    prompt_parts = [
        "Answer ONLY in Bulgarian.",
        "Read only clearly visible text on this food label.",
        "Focus on Bulgarian and English text.",
        "Ignore blurry, cut, or unreadable text.",
    ]
    if allergens:
        prompt_parts.append(
            f"After reading the text, explicitly state whether any of these allergens "
            f"are present in the ingredients: {', '.join(allergens)}."
        )
    if preferred:
        prompt_parts.append(
            f"Also state whether any of these preferred foods are present: {', '.join(preferred)}."
        )
    if allergens:
        prompt_parts.append(
            "Finish with БЕЗОПАСНО if no allergens found, or ВНИМАНИЕ АЛЕРГЕНИ if allergens found."
        )

    response_text = capture_and_send(picam2, " ".join(prompt_parts))
    if response_text is None:
        return

    if OCR_AVAILABLE:
        result = ocr_scanner.filter_food(response_text, prefs)
    else:
        result = {
            "safe": None,
            "allergens_found": [],
            "preferred_found": [],
            "summary": response_text[:200],
            "raw_text": response_text[:500],
        }

    # bt_server.py reads stdout and forwards BT:-prefixed lines to the app
    print(f"BT:SCAN_RESULT:{json.dumps(result, ensure_ascii=False)}", flush=True)


# ── Vibration helpers ─────────────────────────────────────────────────────────

def vibrate_once(pin):
    GPIO.output(pin, GPIO.HIGH); time.sleep(0.15); GPIO.output(pin, GPIO.LOW)

def vibrate_twice(pin):
    for _ in range(2):
        GPIO.output(pin, GPIO.HIGH); time.sleep(0.12)
        GPIO.output(pin, GPIO.LOW);  time.sleep(0.12)

def vibrate_continuous(pin, duration=1.0):
    GPIO.output(pin, GPIO.HIGH); time.sleep(duration); GPIO.output(pin, GPIO.LOW)

def handle_vibration(distance, motor_pin):
    if distance <= 0 or distance == -1:
        GPIO.output(motor_pin, GPIO.LOW)
    elif distance < 20:
        vibrate_continuous(motor_pin)
    elif distance < 50:
        vibrate_twice(motor_pin)
    elif distance < 100:
        vibrate_once(motor_pin)
    else:
        GPIO.output(motor_pin, GPIO.LOW)


# ── Main ──────────────────────────────────────────────────────────────────────

def main():
    # ── Camera ────────────────────────────────────────────────────────────────
    picam2 = Picamera2()
    config = picam2.create_still_configuration(
        main={"size": (1920, 1080)},
        transform=Transform(vflip=True, hflip=True),
    )
    picam2.configure(config)
    picam2.start()
    time.sleep(2)

    try:
        picam2.set_controls({"AfMode": controls.AfModeEnum.Continuous})
        time.sleep(1.0)
        print("[INFO] Autofocus enabled (continuous mode)")
    except Exception as e:
        print(f"[INFO] Autofocus not available: {e}")

    # ── Pins ──────────────────────────────────────────────────────────────────
    TRIG1, ECHO1 = 27, 22
    TRIG2, ECHO2 = 17, 18
    TRIG3, ECHO3 = 5,  6
    TRIG4, ECHO4 = 21, 20

    MOTOR1, MOTOR2, MOTOR3, MOTOR4 = 4, 13, 26, 19

    BTN_LEFT   = 12
    BTN_MIDDLE = 0
    BTN_RIGHT  = 25

    # ── GPIO setup ────────────────────────────────────────────────────────────
    GPIO.setmode(GPIO.BCM)

    for trig in [TRIG1, TRIG2, TRIG3, TRIG4]:
        GPIO.setup(trig, GPIO.OUT)
        GPIO.output(trig, False)

    for echo in [ECHO1, ECHO2, ECHO3, ECHO4]:
        GPIO.setup(echo, GPIO.IN)

    for m in [MOTOR1, MOTOR2, MOTOR3, MOTOR4]:
        GPIO.setup(m, GPIO.OUT)
        GPIO.output(m, GPIO.LOW)

    GPIO.setup(BTN_LEFT,   GPIO.IN, pull_up_down=GPIO.PUD_UP)
    GPIO.setup(BTN_MIDDLE, GPIO.IN, pull_up_down=GPIO.PUD_UP)
    GPIO.setup(BTN_RIGHT,  GPIO.IN, pull_up_down=GPIO.PUD_UP)

    # ── Log startup preferences ───────────────────────────────────────────────
    prefs = load_prefs()
    print(f"[INFO] Startup preferences: "
          f"{len(prefs.get('preferred', []))} preferred, "
          f"{len(prefs.get('allergies', []))} allergies")
    print("[INFO] System ready — waiting for button presses")

    # ── Main loop ─────────────────────────────────────────────────────────────
    DEBOUNCE_SEC = 0.35
    sensors_on   = False
    last_time    = time.time()

    last_left_press   = 0.0
    last_middle_press = 0.0
    last_right_press  = 0.0

    prev_left   = GPIO.input(BTN_LEFT)
    prev_middle = GPIO.input(BTN_MIDDLE)
    prev_right  = GPIO.input(BTN_RIGHT)

    try:
        while True:
            now          = time.time()
            left_state   = GPIO.input(BTN_LEFT)
            middle_state = GPIO.input(BTN_MIDDLE)
            right_state  = GPIO.input(BTN_RIGHT)

            # ── TEXT / FOOD LABEL ─────────────────────────────────────────────
            if (left_state == GPIO.LOW and prev_left == GPIO.HIGH
                    and now - last_left_press >= DEBOUNCE_SEC):
                last_left_press = now
                scan_food_label(picam2)

            # ── SCENE DESCRIPTION ─────────────────────────────────────────────
            if (middle_state == GPIO.LOW and prev_middle == GPIO.HIGH
                    and now - last_middle_press >= DEBOUNCE_SEC):
                last_middle_press = now
                print("[BTN] Middle pressed — scene description")
                capture_and_send(
                    picam2,
                    "Answer ONLY in Bulgarian. "
                    "1-2 sentence description of the scene. "
                    "Say only important and useful things. "
                    "Ignore small or unclear details.",
                )

            # ── SENSOR TOGGLE ─────────────────────────────────────────────────
            if (right_state == GPIO.LOW and prev_right == GPIO.HIGH
                    and now - last_right_press >= DEBOUNCE_SEC):
                last_right_press = now
                sensors_on = not sensors_on
                print(f"[BTN] Right pressed — sensors {'ON' if sensors_on else 'OFF'}")

            # ── DISTANCE SENSORS ──────────────────────────────────────────────
            if sensors_on and time.time() - last_time > 1:
                d1 = get_distance(TRIG1, ECHO1); time.sleep(0.2)
                d2 = get_distance(TRIG2, ECHO2); time.sleep(0.2)
                d3 = get_distance(TRIG3, ECHO3); time.sleep(0.2)
                d4 = get_distance(TRIG4, ECHO4); time.sleep(0.2)
                print(f"\rS1:{d1:.1f} S2:{d2:.1f} S3:{d3:.1f} S4:{d4:.1f} ", end="")
                handle_vibration(d1, MOTOR1)
                handle_vibration(d2, MOTOR2)
                handle_vibration(d3, MOTOR3)
                handle_vibration(d4, MOTOR4)
                last_time = time.time()

            if not sensors_on:
                for m in [MOTOR1, MOTOR2, MOTOR3, MOTOR4]:
                    GPIO.output(m, GPIO.LOW)

            prev_left   = left_state
            prev_middle = middle_state
            prev_right  = right_state

            time.sleep(0.02)

    except KeyboardInterrupt:
        pass
    finally:
        GPIO.cleanup()
        picam2.stop()


if __name__ == "__main__":
    main()
