/**
 * BrainVault — Gemini AI Service
 *
 * Handles all interactions with Google's Gemini API:
 * - Structured memory extraction from text input
 * - Structured memory extraction from audio input (multimodal)
 * - Text embedding generation (768-dim via gemini-embedding-001)
 * - Natural language answer synthesis from retrieved context
 */

const { GoogleGenAI } = require('@google/genai');
const {
  EXTRACTION_SYSTEM_PROMPT,
  EXTRACTION_USER_TEMPLATE,
  SYNTHESIS_SYSTEM_PROMPT,
  SYNTHESIS_USER_TEMPLATE,
} = require('../prompts');

// ─────────────────────────────────────────────────────────────────────────────
// Initialize Gemini Client
// ─────────────────────────────────────────────────────────────────────────────

const ai = new GoogleGenAI({ apiKey: process.env.GEMINI_API_KEY });

/** Model used for text understanding, extraction, and synthesis */
const FLASH_MODEL = 'gemini-2.5-flash';

/** Model used for generating 768-dimensional text embeddings */
const EMBEDDING_MODEL = 'gemini-embedding-001';

// ─────────────────────────────────────────────────────────────────────────────
// Retry Helper for Free-Tier Spikes
// ─────────────────────────────────────────────────────────────────────────────

/**
 * Executes a function and retries it if it encounters a transient 503 error
 * (high demand / model overloaded), using a simple backoff delay.
 */
async function callWithRetry(fn, retries = 3, delay = 1000) {
  for (let i = 0; i < retries; i++) {
    try {
      return await fn();
    } catch (err) {
      const errMsg = err.message || '';
      const isTransient =
        err.status === 503 ||
        errMsg.includes('503') ||
        errMsg.includes('high demand') ||
        errMsg.includes('UNAVAILABLE') ||
        errMsg.includes('overloaded');

      if (isTransient && i < retries - 1) {
        console.warn(`[GEMINI] 503 High Demand, retrying in ${delay}ms... (Attempt ${i + 1}/${retries})`);
        await new Promise((resolve) => setTimeout(resolve, delay));
        delay *= 2; // Exponential backoff
        continue;
      }
      throw err;
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Memory Extraction
// ─────────────────────────────────────────────────────────────────────────────

/**
 * Extract structured metadata from a text memory input.
 *
 * @param {string} text - The user's raw text input
 * @param {string} currentDate - ISO date string (YYYY-MM-DD) for relative date resolution
 * @returns {Promise<Object>} Parsed JSON: { event_date, event_date_raw, subject, tags, cleaned_text }
 */
async function extractMemoryFromText(text, currentDate) {
  const response = await callWithRetry(() =>
    ai.models.generateContent({
      model: FLASH_MODEL,
      contents: [
        {
          role: 'user',
          parts: [{ text: EXTRACTION_USER_TEMPLATE(currentDate) + text }],
        },
      ],
      config: {
        systemInstruction: EXTRACTION_SYSTEM_PROMPT,
        temperature: 0.1, // Low temp for deterministic, structured output
        maxOutputTokens: 1024,
      },
    })
  );

  return parseExtractionResponse(response.text);
}

/**
 * Extract structured metadata from an audio memory input.
 * Gemini 2.5 Flash natively processes audio — no separate STT pipeline needed.
 * The model simultaneously transcribes the audio and extracts metadata in one pass.
 *
 * @param {Buffer} audioBuffer - Raw audio file bytes
 * @param {string} mimeType - Audio MIME type (e.g., 'audio/mp4', 'audio/mpeg')
 * @param {string} currentDate - ISO date string (YYYY-MM-DD)
 * @returns {Promise<Object>} Parsed JSON: { event_date, event_date_raw, subject, tags, cleaned_text }
 */
async function extractMemoryFromAudio(audioBuffer, mimeType, currentDate) {
  const base64Audio = audioBuffer.toString('base64');

  const response = await callWithRetry(() =>
    ai.models.generateContent({
      model: FLASH_MODEL,
      contents: [
        {
          role: 'user',
          parts: [
            // Audio part: inline base64-encoded audio data
            {
              inlineData: {
                mimeType: mimeType,
                data: base64Audio,
              },
            },
            // Text instruction: tells the model to transcribe + extract
            {
              text:
                EXTRACTION_USER_TEMPLATE(currentDate) +
                '[Audio input — transcribe the audio above and extract memory metadata from the transcript]',
            },
          ],
        },
      ],
      config: {
        systemInstruction: EXTRACTION_SYSTEM_PROMPT,
        temperature: 0.1,
        maxOutputTokens: 1024,
      },
    })
  );

  return parseExtractionResponse(response.text);
}

// ─────────────────────────────────────────────────────────────────────────────
// Embedding Generation
// ─────────────────────────────────────────────────────────────────────────────

/**
 * Generate a 768-dimensional embedding vector for the given text.
 * Uses gemini-embedding-001 for stable, production-grade embeddings.
 *
 * @param {string} text - Text to embed
 * @returns {Promise<number[]>} Array of 768 floating-point values
 */
async function generateEmbedding(text) {
  const result = await callWithRetry(() =>
    ai.models.embedContent({
      model: EMBEDDING_MODEL,
      contents: text,
      config: {
        outputDimensionality: 768,
      },
    })
  );

  return result.embeddings[0].values;
}

// ─────────────────────────────────────────────────────────────────────────────
// Answer Synthesis
// ─────────────────────────────────────────────────────────────────────────────

/**
 * Synthesize a natural language answer from retrieved memory context.
 * Called during the retrieval flow after hybrid search finds relevant memories.
 *
 * @param {string} question - The user's natural language question
 * @param {Object[]} memories - Array of matched memory records from hybrid search
 * @returns {Promise<string>} Natural language answer grounded in the provided context
 */
async function synthesizeAnswer(question, memories) {
  const response = await callWithRetry(() =>
    ai.models.generateContent({
      model: FLASH_MODEL,
      contents: [
        {
          role: 'user',
          parts: [{ text: SYNTHESIS_USER_TEMPLATE(question, memories) }],
        },
      ],
      config: {
        systemInstruction: SYNTHESIS_SYSTEM_PROMPT,
        temperature: 0.3, // Slightly creative for natural-sounding answers
        maxOutputTokens: 2048,
      },
    })
  );

  return response.text;
}

// ─────────────────────────────────────────────────────────────────────────────
// Response Parsing
// ─────────────────────────────────────────────────────────────────────────────

/**
 * Parse the LLM's extraction response, handling potential markdown code fences
 * that the model might include despite instructions not to.
 *
 * @param {string} rawText - Raw response text from Gemini
 * @returns {Object} Validated extraction result
 * @throws {Error} If the response is not valid JSON or missing required fields
 */
function parseExtractionResponse(rawText) {
  let cleaned = rawText.trim();

  // Strip markdown code fences if present (```json ... ``` or ``` ... ```)
  if (cleaned.startsWith('```')) {
    cleaned = cleaned
      .replace(/^```(?:json)?\s*\n?/, '')
      .replace(/\n?```\s*$/, '');
  }

  try {
    const parsed = JSON.parse(cleaned);

    // Validate required fields exist
    if (!parsed.subject || !parsed.cleaned_text) {
      throw new Error('LLM response missing required fields: subject, cleaned_text');
    }

    // Normalize and return
    return {
      event_date: parsed.event_date || null,
      event_date_raw: parsed.event_date_raw || null,
      subject: parsed.subject.toLowerCase().trim(),
      tags: Array.isArray(parsed.tags)
        ? parsed.tags.map((t) => String(t).toLowerCase().trim()).filter(Boolean)
        : [],
      raw_transcript: parsed.raw_transcript ? parsed.raw_transcript.trim() : null,
      cleaned_text: parsed.cleaned_text.trim(),
    };
  } catch (err) {
    console.error('[GEMINI] Failed to parse extraction response:', rawText);
    throw new Error(`LLM returned invalid JSON: ${err.message}`);
  }
}

module.exports = {
  extractMemoryFromText,
  extractMemoryFromAudio,
  generateEmbedding,
  synthesizeAnswer,
};
