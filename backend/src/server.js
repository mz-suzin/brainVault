/**
 * BrainVault — Main Server
 *
 * Minimal Express backend for the memory vault API.
 * Handles text and audio memory ingestion, hybrid semantic/keyword
 * search, and LLM-powered answer synthesis.
 */

require('dotenv').config();

const express = require('express');
const cors = require('cors');
const helmet = require('helmet');
const rateLimit = require('express-rate-limit');
const memoryRoutes = require('./routes/memory');
const { startKeepAlive } = require('./utils/keepalive');

const app = express();
const PORT = process.env.PORT || 3000;

// ─────────────────────────────────────────────────────────────────────────────
// Middleware
// ─────────────────────────────────────────────────────────────────────────────

// Security headers (XSS, MIME sniffing, etc.)
app.use(helmet());

// CORS — allow requests from any origin (mobile app sends from device)
app.use(cors());

// Parse JSON request bodies (for the /query endpoint)
app.use(express.json({ limit: '1mb' }));

// Parse URL-encoded bodies (for form text fields in multipart)
app.use(express.urlencoded({ extended: true }));

// Rate limiter — protect free-tier Gemini quota
// 30 requests per minute per IP (generous for a single user)
const limiter = rateLimit({
  windowMs: 60 * 1000,
  max: 30,
  standardHeaders: true,
  legacyHeaders: false,
  message: { error: 'Too many requests. Please wait a moment and try again.' },
});
app.use('/api/', limiter);

// ─────────────────────────────────────────────────────────────────────────────
// Routes
// ─────────────────────────────────────────────────────────────────────────────

// Health check — used by keep-alive pings and Render health monitoring
app.get('/api/health', (_req, res) => {
  res.json({
    status: 'ok',
    service: 'brainvault-api',
    timestamp: new Date().toISOString(),
  });
});

// Memory endpoints (add + query)
app.use('/api/memory', memoryRoutes);

// ─────────────────────────────────────────────────────────────────────────────
// Error Handling
// ─────────────────────────────────────────────────────────────────────────────

// 404 — Route not found
app.use((_req, res) => {
  res.status(404).json({ error: 'Endpoint not found' });
});

// Global error handler — catches unhandled errors in route handlers
// eslint-disable-next-line no-unused-vars
app.use((err, _req, res, _next) => {
  console.error(`[ERROR] ${err.stack || err.message}`);
  res.status(err.status || 500).json({
    error: process.env.NODE_ENV === 'production'
      ? 'Internal server error'
      : err.message,
  });
});

// ─────────────────────────────────────────────────────────────────────────────
// Start Server
// ─────────────────────────────────────────────────────────────────────────────

app.listen(PORT, () => {
  console.log(`🧠 BrainVault API running on port ${PORT}`);
  console.log(`   Health: http://localhost:${PORT}/api/health`);
  startKeepAlive(PORT);
});
