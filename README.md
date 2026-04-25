# MyBaT — My Blind Assistant Tool

MyBaT is a smart assistive ecosystem for blind and visually impaired users, combining a **Raspberry Pi wearable device**, **Flutter mobile app**, and **NestJS backend** into one connected solution.

The Raspberry Pi uses a camera, ultrasonic sensors, vibration motors, and Google Gemini AI to help users understand their surroundings through **voice guidance and haptic feedback**. With a button press, the device can read text, describe the scene ahead, or warn about nearby obstacles through increasing vibration intensity.

The mobile app acts as the control center, allowing device setup, Bluetooth and Wi-Fi pairing, profile management, relative linking, and personalized settings such as allergies, food preferences, and language.

The backend manages **authentication, user profiles, relative connections, SOS alerts, and transactional email**, using PostgreSQL, TypeORM, and Mailtrap.

---

## Architecture

```
┌─────────────────┐        Bluetooth        ┌──────────────────────┐
│  Flutter App    │◄───────────────────────►│  Raspberry Pi Device │
│  (Mobile)       │                         │  (rpi-scripts)       │
└────────┬────────┘                         └──────────────────────┘
         │ HTTPS (REST API)
         ▼
┌─────────────────┐        PostgreSQL       ┌──────────────────────┐
│  NestJS Backend │◄───────────────────────►│  Supabase Database   │
│  (backend/)     │                         └──────────────────────┘
└────────┬────────┘
         │ SMTP / API
         ▼
┌─────────────────┐
│    Mailtrap     │  (transactional email — SOS alerts, invitations)
└─────────────────┘
```

---

## Prerequisites

| Tool | Version | Used by |
|------|---------|---------|
| Node.js | 18+ | Backend |
| npm | 9+ | Backend |
| Flutter SDK | 3.0+ | Mobile app |
| Python | 3.12+ | RPi scripts |
| Docker (optional) | any | Local database |

---

## 1. Backend

### Setup

```bash
cd backend
npm install
```

Copy the environment template and fill in your values:

```bash
cp .env.example .env
```

See [Environment Variables](#environment-variables) for what each value means.

### Database

**Option A — Supabase (recommended):**
Create a project at [supabase.com](https://supabase.com), then copy the connection details into `.env`. Use the **Session Pooler** host (`aws-0-<region>.pooler.supabase.com`) to ensure IPv4 compatibility.

**Option B — Local Docker:**
```bash
npm run postgre:up
```

### Migrations

```bash
# Linux / macOS
npm run migration:run

# Windows
npm run migration:run:win
```

### Run

```bash
# Development (hot reload)
npm run start:dev

# Production
npm run start:prod
```

The API will be available at `http://localhost:3000`.  
Swagger docs are available at `http://localhost:3000/api`.

---

## 2. Mobile App

### Setup

```bash
cd mobile-app
flutter pub get
```

### Run

```bash
# Debug build on connected device
flutter run

# Release APK
flutter build apk --release
```

### Deep links

The app handles `mbt://` URI scheme for invite links. When a relative receives an invitation email and opens the link on their phone, the backend redirect page at `/invite` bounces them into the app automatically.

---

## 3. RPi Scripts

### Hardware required

- Raspberry Pi (3B+ or later recommended)
- Pi Camera Module
- Ultrasonic distance sensor (HC-SR04)
- Vibration motor(s)
- Push button

### Setup

```bash
cd rpi-scripts
pip install RPi.GPIO picamera2 bluetooth google-genai
```

Set your Google Gemini API key as an environment variable:

```bash
export GOOGLE_API_KEY=your_gemini_api_key
```

### Run

Start the Bluetooth server first (handles mobile app pairing):

```bash
python bt_server.py
```

The main device logic starts automatically once the mobile app connects over Bluetooth.

---

## Environment Variables

All backend environment variables are documented in [`backend/.env.example`](backend/.env.example).

Key variables:

| Variable | Description |
|----------|-------------|
| `DATABASE_HOST` | PostgreSQL host (use Supabase pooler for IPv4) |
| `DATABASE_PASSWORD` | PostgreSQL password |
| `JWT_ACCESS_SECRET` | Secret for signing access tokens (min 64 chars) |
| `JWT_REFRESH_SECRET` | Secret for signing refresh tokens (min 64 chars) |
| `MAILTRAP_API_TOKEN` | Mailtrap API token for sending emails |
| `MAILTRAP_FROM` | Verified sender address in your Mailtrap account |
| `DEEP_LINK_BASE_URL` | Base URL for invite links (e.g. `https://api.mybat.tech`) |
| `ANDROID_SHA256_FINGERPRINT` | SHA-256 fingerprint of your Android signing key |

---

## Generating secrets

JWT secrets should be at least 64 random hex characters. Generate them with:

```bash
# Linux / macOS
openssl rand -hex 64

# Windows (PowerShell)
[System.BitConverter]::ToString([System.Security.Cryptography.RandomNumberGenerator]::GetBytes(64)).Replace("-","").ToLower()
```

## Getting the Android SHA-256 fingerprint

```bash
# Debug keystore (default location)
keytool -list -v -keystore ~/.android/debug.keystore -alias androiddebugkey -storepass android -keypass android
```

---

## License

[MIT](LICENSE)
