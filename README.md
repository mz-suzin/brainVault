# 🧠 BrainVault

> A secure external hard drive for the human brain — record, categorize, and query your life events with ease.

Built entirely on **free-tier infrastructure**: Gemini 2.5 Flash, Supabase PostgreSQL + pgvector, Render, and Flutter.

## Architecture

```
User speaks/types a memory
        │
        ▼
┌─────────────────┐     ┌──────────────────┐     ┌────────────────────┐
│  Flutter App     │────▶│  Node.js/Express  │────▶│  Gemini 2.5 Flash  │
│  (Android)       │◀────│  (Render)         │◀────│  + Embedding API   │
└─────────────────┘     └──────┬───────────┘     └────────────────────┘
                               │
                               ▼
                       ┌──────────────────┐
                       │  Supabase        │
                       │  PostgreSQL      │
                       │  + pgvector      │
                       └──────────────────┘
```

## Project Structure

```
brainVault/
├── backend/                    # Node.js/Express API
│   ├── db/                     # SQL schemas & functions
│   ├── src/                    # Server, routes, services
│   ├── package.json
│   └── README.md               # ← Setup & deployment guide
├── frontend/                   # Flutter Android app
│   ├── lib/                    # Dart source code
│   ├── android/                # Android-specific config
│   ├── pubspec.yaml
│   └── README.md
├── .gitignore
└── README.md                   # ← You are here
```

## Quick Start

### Backend
```bash
cd backend
cp .env.example .env            # Fill in your API keys
npm install
npm run dev
```

### Frontend
```bash
cd frontend
flutter pub get
flutter run                     # Requires Android device/emulator
```

## Tech Stack

| Layer | Technology | Free Tier |
|-------|-----------|-----------|
| Frontend | Flutter 3.x (Android) | Local build |
| Backend | Node.js 20 + Express | Render (512 MB, spins down after 15 min) |
| Database | Supabase PostgreSQL + pgvector | 500 MB storage |
| LLM | Gemini 2.5 Flash | Project-level quotas |
| Embeddings | gemini-embedding-001 (768-dim) | Shared Gemini quota |

## Documentation

- **[Backend README](backend/README.md)** — Setup, API endpoints, Supabase guide, Render deployment
- **Phase 1:** Database schema + LLM prompts → `backend/db/` + `backend/src/prompts.js`
- **Phase 2:** Backend API → `backend/src/`
- **Phase 3:** Flutter app → `frontend/lib/`
- **Phase 4:** Keep-alive strategy → `backend/src/utils/keepalive.js`
