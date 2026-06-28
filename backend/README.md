# BrainVault — Backend

API and server-side logic for BrainVault, built with Node.js/Express.

## Architecture

```
backend/
├── db/
│   ├── schema.sql              # PostgreSQL table + index definitions
│   └── search_function.sql     # Hybrid search RPC function
├── src/
│   ├── server.js               # Express app entry point
│   ├── prompts.js              # LLM prompt templates
│   ├── routes/
│   │   └── memory.js           # /api/memory/add & /api/memory/query
│   ├── services/
│   │   ├── gemini.js           # Gemini 2.5 Flash + embedding API
│   │   └── database.js         # Supabase PostgreSQL client
│   └── utils/
│       └── keepalive.js        # Free-tier keep-alive cron
├── .env.example                # Environment variable template
└── package.json
```

## Quick Start (Local Development)

### 1. Prerequisites
- Node.js ≥ 20
- A [Supabase](https://supabase.com) project (free tier)
- A [Google AI Studio](https://aistudio.google.com) API key (free tier)

### 2. Supabase Setup

> **First time?** Follow these steps to create your Supabase project:

1. Go to [supabase.com](https://supabase.com) and sign up / log in
2. Click **"New Project"** → choose a name (e.g., `brainvault`) and set a database password
3. Wait for the project to provision (~2 minutes)
4. Go to **SQL Editor** (left sidebar) → click **"New Query"**
5. Paste the contents of [`db/schema.sql`](db/schema.sql) → click **"Run"**
6. Create another new query → paste [`db/search_function.sql`](db/search_function.sql) → click **"Run"**
7. Go to **Project Settings** → **API** and copy:
   - **Project URL** → this is your `SUPABASE_URL`
   - **service_role key** (under "Project API keys") → this is your `SUPABASE_SERVICE_KEY`

> ⚠️ **Use the `service_role` key**, not the `anon` key. The service role key bypasses Row Level Security, which is needed since the backend is the only client.

### 3. Google AI Studio Setup

1. Go to [aistudio.google.com/apikey](https://aistudio.google.com/apikey)
2. Click **"Create API Key"** → copy the key
3. This is your `GEMINI_API_KEY`

### 4. Configure Environment

```bash
cp .env.example .env
```

Fill in your `.env`:
```env
GEMINI_API_KEY=your_key_here
SUPABASE_URL=https://xxxx.supabase.co
SUPABASE_SERVICE_KEY=eyJhbGci...
PORT=3000
NODE_ENV=development
```

### 5. Install & Run

```bash
npm install
npm run dev
```

The server starts on `http://localhost:3000`. Test it:
```bash
curl http://localhost:3000/api/health
```

## API Endpoints

### `GET /api/health`
Health check. Returns `{ status: "ok" }`.

### `POST /api/memory/add`
Ingest a new memory.

**Text input:**
```bash
curl -X POST http://localhost:3000/api/memory/add \
  -H "Content-Type: application/json" \
  -d '{"text": "I ran my first marathon in São Paulo on March 15, 2024. Finished in 4:32:15."}'
```

**Audio input:**
```bash
curl -X POST http://localhost:3000/api/memory/add \
  -F "audio=@recording.m4a"
```

### `POST /api/memory/query`
Query memories with natural language.

```bash
curl -X POST http://localhost:3000/api/memory/query \
  -H "Content-Type: application/json" \
  -d '{"question": "When did I run my first marathon?"}'
```

## Deployment to Render (Free Tier)

1. Push this repo to GitHub
2. Go to [render.com](https://render.com) → **New Web Service**
3. Connect your GitHub repo
4. Configure:
   - **Root Directory:** `backend`
   - **Build Command:** `npm install`
   - **Start Command:** `node src/server.js`
   - **Instance Type:** Free
5. Add environment variables: `GEMINI_API_KEY`, `SUPABASE_URL`, `SUPABASE_SERVICE_KEY`, `NODE_ENV=production`
6. Deploy!

The keep-alive cron (every 14 min) auto-starts in production to prevent container spin-down.
