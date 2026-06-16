# TrainMate

**Graduation project — AI-powered fitness companion**

TrainMate is a full-stack fitness application that combines pose-based exercise tracking, personalized workout plans, body-progress analysis, and an AI fitness chatbot. The system is split into three code pillars plus a report folder for academic submission.

## Project structure

```
PP/
├── ai/                              # ML training, Streamlit prototype, body analysis
├── trainmate_backend/               # FastAPI REST API (auth, plans, workouts, ML)
├── trainmate_app/                   # Flutter mobile client (Android / iOS / desktop)
└── GP Feedback & Report template/   # Graduation report templates and feedback forms
```

| Folder | Role |
|--------|------|
| `ai/` | Exercise classifier training, TFLite export, body before/after analyzer, original Streamlit demo |
| `trainmate_backend/` | JWT authentication, user profiles, workout plans, sessions, chatbot, ML endpoints |
| `trainmate_app/` | Onboarding, live rep counting, form feedback, plan completion, profile & settings |
| `GP Feedback & Report template/` | Official GP report and feedback documents (kept for submission) |

## Main features

- **User onboarding** — profile setup, fitness goal, before photo, initial workout plan
- **Workout plans** — create/edit plans, track sessions toward a target, plan completion flow
- **Live exercise tracking** — camera pose detection for squat, push-up, shoulder press, barbell biceps curl
- **Form analysis** — rep counting, partial-rep detection, posture faults, good-form percentage
- **Body progress** — before/after photo comparison with AI metrics (MediaPipe + vision LLM)
- **AI chatbot** — fitness Q&A powered by Groq (optional API key)
- **Bilingual UI** — English and Arabic

## Supported exercises

Only these four exercises are supported end-to-end (training data, backend, and app):

- Squat  
- Push-up  
- Shoulder press  
- Barbell biceps curl  

## Prerequisites

- **Python** 3.10–3.11 (backend + AI scripts)
- **Flutter** SDK 3.11+ with Android toolchain (or desktop/iOS for local testing)
- **Android Studio** or VS Code with Flutter extension (recommended)
- Optional: **Groq API key** for chatbot; **Resend or SMTP** for email verification

## Quick start

### 1. Backend

```powershell
cd trainmate_backend
python -m venv .venv
.\.venv\Scripts\Activate.ps1
pip install -r requirements.txt
copy .env.example .env
# Edit .env: set JWT_SECRET_KEY, and optionally GROQ_API_KEY / email settings
uvicorn app.main:app --host 0.0.0.0 --port 8000
```

**Fast one-click start:** `.\start.ps1` (creates venv, installs core deps, runs server)

**ML extras (optional, heavy ~500MB):** only if you need server exercise classify or body photo analysis:

```powershell
pip install -r requirements-ml.txt
```

> Do **not** cancel `pip install` midway — that breaks the venv. Core install takes ~1–2 min; ML install can take 10–20 min.

Health check: [http://127.0.0.1:8000/api/health](http://127.0.0.1:8000/api/health)

### 2. Flutter app

```powershell
cd trainmate_app
flutter pub get
flutter run --dart-define=API_BASE_URL=http://10.0.2.2:8000
```

| Platform | API base URL |
|----------|----------------|
| Android emulator | `http://10.0.2.2:8000` |
| Physical device (same Wi‑Fi) | `http://<your-pc-ip>:8000` |
| Desktop / iOS simulator | `http://127.0.0.1:8000` |

### 3. ML model files

Exercise classifier weights live in `ai/models/`:

- `final_forthesis_bidirectionallstm_and_encoders_exercise_classifier_model.h5`
- `thesis_bidirectionallstm_scaler.pkl`
- `thesis_bidirectionallstm_label_encoder.pkl`

To export an on-device TFLite model for the Flutter app:

```powershell
cd ai
pip install -r requirements-tflite-export.txt
python export_for_flutter.py
```

Output goes to `trainmate_app/assets/models/` (`exercise_classifier.tflite`, `scaler_params.json`, `classes.json`).

## Email delivery (verification & password reset codes)

The app shows the code **inside the app** and prints it in the **server terminal** when `EXPOSE_VERIFICATION_CODES=true` (default for dev). This is enough for the demo — no inbox needed.

To make codes actually arrive in **any** email inbox, use Gmail SMTP with an **App Password** (the normal account password does **not** work):

1. Enable 2-Step Verification: [myaccount.google.com/security](https://myaccount.google.com/security)
2. Create an App Password: [myaccount.google.com/apppasswords](https://myaccount.google.com/apppasswords) → choose "Mail" → copy the 16-character code
3. In `trainmate_backend/.env` set:

```env
SMTP_HOST=smtp.gmail.com
SMTP_PORT=587
SMTP_USE_TLS=true
SMTP_USER=your@gmail.com
SMTP_PASSWORD=abcd efgh ijkl mnop   # the 16-char App Password (spaces optional)
SMTP_FROM=your@gmail.com
```

4. Restart the backend.

> **Resend free tier** (`onboarding@resend.dev`) only delivers to the Resend account owner's email. To reach other addresses with Resend you must verify a domain. For arbitrary recipients, prefer Gmail SMTP above.

The backend tries **SMTP first, then Resend**; if both fail it falls back to showing the code in-app/logs (dev).

## API overview

| Area | Endpoints |
|------|-----------|
| Auth | `POST /api/auth/register`, `login`, `verify-email`, `forgot-password`, `reset-password` |
| User | `GET/PATCH /api/users/me`, profile, account, plan |
| Plans | `GET/POST/PATCH/DELETE /api/plans`, `POST /api/plans/{id}/complete`, `GET /api/plans/completed` |
| Workouts | `POST/GET /api/workouts` |
| ML | `GET /api/ml/status`, `POST /api/ml/classify`, body progress analysis |
| Chat | `POST /api/chat` |

Full backend notes: `trainmate_backend/BACKEND_DOCUMENTATION.md` and `trainmate_backend/BACKEND_DOCUMENTATION_AR.md`.

## AI / Streamlit prototype

The `ai/` folder also contains the original Streamlit-based demo (`main.py`) used during model development. Run it separately if needed:

```powershell
cd ai
python -m venv .venv
.\.venv\Scripts\Activate.ps1
pip install -r requirements.txt
streamlit run main.py
```

## Report folder

`GP Feedback & Report template/` contains the graduation report template and term feedback documents. Do not remove this folder when submitting the project.

## What is not included (by design)

The following are generated locally and are **not** shipped in the repository:

- Python virtual environments (`.venv/`, `.venv_export/`)
- Flutter build output (`trainmate_app/build/`, `.dart_tool/`)
- Gradle cache (`trainmate_app/android/.gradle/`)
- Runtime database (`trainmate_backend/trainmate.db`)
- Secrets file (`trainmate_backend/.env` — use `.env.example` as template)

Recreate them with the setup steps above.

## Troubleshooting

| Problem | Fix |
|---------|-----|
| App cannot reach API | Confirm backend is running; use `10.0.2.2` on Android emulator |
| Registration returns 503 | Configure SMTP or Resend in `.env`, or set `EXPOSE_VERIFICATION_CODES=true` for dev |
| Exercise model missing | Place `.h5`/`.pkl` files in `ai/models/` or run `export_for_flutter.py` |
| `mediapipe` install fails | Use Python 3.10–3.11 and `pip install mediapipe==0.10.9` |

---

**TrainMate** — Graduation Project · FastAPI + Flutter + TensorFlow/MediaPipe
