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
 * (high demand / model overloaded), or falls back to gemini-3.1-flash-lite on 429 Quota Exhausted.
 */
async function callWithRetry(fn, defaultModel = null, retries = 4, delay = 1500) {
  let currentModel = defaultModel;
  for (let i = 0; i < retries; i++) {
    try {
      return await (defaultModel ? fn(currentModel) : fn());
    } catch (err) {
      // Normalise the error message — the Gemini SDK sometimes wraps the
      // API error inside a JSON string or a nested error.status object.
      const errMsg = err.message || '';
      let errCode = err.status || err.code || 0;

      // Try to extract status code from a JSON-stringified error body
      if (!errCode && errMsg.includes('{')) {
        try {
          const parsed = JSON.parse(errMsg.replace(/^[^{]*/, ''));
          errCode = parsed?.error?.code || parsed?.code || 0;
        } catch (_) {}
      }

      // ── 429 Quota Exhausted: fall back to flash-lite ─────────────────────
      const isQuota =
        errCode === 429 ||
        errMsg.includes('429') ||
        errMsg.toLowerCase().includes('quota');

      if (isQuota) {
        if (currentModel === FLASH_MODEL) {
          console.warn(`[GEMINI] 429 Quota Exhausted for ${FLASH_MODEL}. Falling back to gemini-2.0-flash-lite...`);
          currentModel = 'gemini-2.0-flash-lite';
          continue;
        } else {
          throw err;
        }
      }

      // ── 503 / UNAVAILABLE: exponential back-off ──────────────────────────
      const isTransient =
        errCode === 503 ||
        errMsg.includes('503') ||
        errMsg.toLowerCase().includes('high demand') ||
        errMsg.toLowerCase().includes('unavailable') ||
        errMsg.toLowerCase().includes('overloaded');

      if (isTransient && i < retries - 1) {
        const wait = delay * Math.pow(2, i);
        console.warn(`[GEMINI] 503 High Demand — retrying in ${wait}ms (attempt ${i + 1}/${retries})...`);
        await new Promise((resolve) => setTimeout(resolve, wait));
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
  const response = await callWithRetry((model) =>
    ai.models.generateContent({
      model: model,
      contents: [
        {
          role: 'user',
          parts: [{ text: EXTRACTION_USER_TEMPLATE(currentDate) + text }],
        },
      ],
      config: {
        systemInstruction: EXTRACTION_SYSTEM_PROMPT,
        temperature: 0.1, // Low temp for deterministic, structured output
        maxOutputTokens: 2048, // Increased to prevent truncation of large extractions
      },
    })
  , FLASH_MODEL);

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

  const response = await callWithRetry((model) =>
    ai.models.generateContent({
      model: model,
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
        maxOutputTokens: 2048, // Increased to prevent truncation of large extractions
      },
    })
  , FLASH_MODEL);

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
  const response = await callWithRetry((model) =>
    ai.models.generateContent({
      model: model,
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
  , FLASH_MODEL);

  return response.text;
}

/**
 * Deduce which specific database profile (candidate) is referred to in a memory mention.
 * Uses Gemini to evaluate context clues against relation type and notes.
 *
 * @param {string} memoryText - Original memory description / transcript
 * @param {string} name - Name being disambiguated (e.g. "John")
 * @param {Object[]} candidates - Array of duplicate database profiles: { id, name, relation, notes }
 * @returns {Promise<Object>} { resolved: boolean, resolved_id: string|null, reasoning: string }
 */
async function resolvePersonDisambiguation(memoryText, name, candidates) {
  const systemInstruction = `You are a name resolution assistant.
The user wrote a memory that mentions the name "${name}".
There are multiple people in the database with this name.
Your task is to review the memory context and candidates, and decide if one candidate matches.

RULES:
1. If the memory context matches a candidate's relation or notes, resolve to that candidate.
   - Example: Memory mentions "meeting about projects" -> links "John (Colleague, notes: Software Developer)"
   - Example: Memory mentions "having Sunday family dinner" -> links "John (Family, notes: My brother)"
2. If there are no clear contextual clues, set "resolved" to false and "resolved_id" to null.
3. Be conservative: only resolve if you have reasonable confidence (e.g. > 0.8). If it could be either, do not resolve.
4. Return ONLY valid JSON matching the schema. No explanations, no markdown fences.`;

  const userContent = `Memory text: "${memoryText}"

Candidates:
${candidates.map((c, i) => `${i + 1}. ID: "${c.id}" | Name: "${c.name}" | Relation: "${c.relation}" | Notes: "${c.notes}"`).join('\n')}

Respond with this exact JSON structure:
{
  "resolved": true or false,
  "resolved_id": "matching-uuid-string" or null,
  "reasoning": "brief explanation of your decision"
}`;

  try {
    const response = await callWithRetry((model) =>
      ai.models.generateContent({
        model: model,
        contents: [{ role: 'user', parts: [{ text: userContent }] }],
        config: {
          systemInstruction,
          temperature: 0.1, // low temperature for logical matching
          maxOutputTokens: 512,
        },
      })
    , FLASH_MODEL);

    let cleaned = response.text.trim();
    if (cleaned.startsWith('```')) {
      cleaned = cleaned.replace(/^```(?:json)?\s*\n?/, '').replace(/\n?```\s*$/, '');
    }

    const result = JSON.parse(cleaned);
    return {
      resolved: !!result.resolved && !!result.resolved_id,
      resolved_id: result.resolved_id || null,
      reasoning: result.reasoning || '',
    };
  } catch (err) {
    console.error('[GEMINI] Disambiguation deduction failed:', err.message);
    return { resolved: false, resolved_id: null, reasoning: err.message };
  }
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

  // ── Attempt 1: Parse as-is ────────────────────────────────────────────────
  try {
    return normalizeExtraction(JSON.parse(cleaned));
  } catch (_) {}

  // ── Attempt 2: Repair truncated JSON ─────────────────────────────────────
  // The LLM may have been cut off mid-string due to token limits. We close
  // any open strings and then close unclosed braces/brackets.
  try {
    const repaired = repairTruncatedJson(cleaned);
    console.warn('[GEMINI] JSON was truncated — used repaired version');
    return normalizeExtraction(JSON.parse(repaired));
  } catch (err) {
    console.error('[GEMINI] Failed to parse extraction response even after repair:', rawText);
    throw new Error(`LLM returned invalid JSON: ${err.message}`);
  }
}

/**
 * Best-effort repair of a JSON string that was cut off mid-generation.
 * Closes any unterminated string literal, then closes unclosed arrays/objects.
 */
function repairTruncatedJson(str) {
  let s = str.trimEnd();
  let inString = false;
  let result = '';
  
  // Pass 1: escape literal newlines/tabs inside strings and close unterminated strings
  for (let i = 0; i < s.length; i++) {
    const ch = s[i];
    if (ch === '\\' && inString) {
      result += s[i] + (s[i + 1] || '');
      i++;
      continue;
    }
    if (ch === '"') inString = !inString;
    
    if (inString && ch === '\n') {
      result += '\\n';
    } else if (inString && ch === '\r') {
      result += '\\r';
    } else if (inString && ch === '\t') {
      result += '\\t';
    } else {
      result += ch;
    }
  }
  if (inString) result += '"';

  // Pass 2: Close unclosed arrays and objects
  result = result.replace(/,\s*$/, '');
  const stack = [];
  inString = false;
  for (let j = 0; j < result.length; j++) {
    const ch = result[j];
    if (ch === '\\' && inString) { j++; continue; }
    if (ch === '"') { inString = !inString; continue; }
    if (inString) continue;
    
    if (ch === '{') stack.push('}');
    else if (ch === '[') stack.push(']');
    else if (ch === '}' || ch === ']') stack.pop();
  }
  
  while (stack.length) result += stack.pop();
  return result;
}

/**
 * Validate required fields and normalize an extraction result object.
 */
function normalizeExtraction(parsed) {
  if (!parsed.subject || !parsed.cleaned_text) {
    throw new Error('LLM response missing required fields: subject, cleaned_text');
  }
  return {
    event_date: parsed.event_date || null,
    event_date_raw: parsed.event_date_raw || null,
    subject: parsed.subject.toLowerCase().trim(),
    tags: Array.isArray(parsed.tags)
      ? parsed.tags.map((t) => String(t).toLowerCase().trim()).filter(Boolean)
      : [],
    people_details: Array.isArray(parsed.people_details)
      ? parsed.people_details.map((p) => ({
          name: String(p.name || '').trim(),
          relation: String(p.relation || 'other').toLowerCase().trim(),
          notes: String(p.notes || '').trim(),
        })).filter((p) => p.name.length > 0)
      : [],
    raw_transcript: parsed.raw_transcript ? parsed.raw_transcript.trim() : null,
    cleaned_text: parsed.cleaned_text.trim(),
  };
}

/**
 * Merge existing person profile facts with newly extracted facts into a single, cohesive, non-redundant note.
 *
 * @param {string} existingNotes - Current notes in DB
 * @param {string} newNotes - Newly extracted notes from memory
 * @returns {Promise<string>} Cleaned, merged notes
 */
async function mergePersonNotes(existingNotes, newNotes) {
  if (!existingNotes || !existingNotes.trim()) return newNotes ? newNotes.trim() : '';
  if (!newNotes || !newNotes.trim()) return existingNotes ? existingNotes.trim() : '';

  const systemInstruction = `You are a facts aggregator. 
Combine the "Existing Profile Notes" and the "New Facts" about a person into a single, unified, coherent summary.

RULES:
1. Preserve ALL unique, non-redundant factual details from both inputs (e.g. nicknames, relations, interests, specific memories, dates). Never discard a unique fact.
2. Remove any duplicate, overlapping, or redundant facts.
3. If there is a direct contradiction, favor the "New Facts".
4. Write in a neutral, third-person descriptive tone.
5. Do NOT set artificial length limits. The notes can be as long as necessary to capture all unique facts, but keep the writing concise and direct.
6. Organize the facts cleanly using short, clear sentences. Do NOT output JSON or explanations, just the plain text notes.`;

  const userContent = `Existing Profile Notes: "${existingNotes}"
New Facts: "${newNotes}"`;

  try {
    const response = await callWithRetry((model) =>
      ai.models.generateContent({
        model: model,
        contents: [{ role: 'user', parts: [{ text: userContent }] }],
        config: {
          systemInstruction,
          temperature: 0.2, // low temperature for clean aggregation
          maxOutputTokens: 256,
        },
      })
    , FLASH_MODEL);
    return response.text.trim();
  } catch (err) {
    console.error('[GEMINI] Merging notes failed:', err.message);
    // Fallback: Concatenate with a semicolon
    return `${existingNotes.trim()}; ${newNotes.trim()}`;
  }
}

module.exports = {
  extractMemoryFromText,
  extractMemoryFromAudio,
  generateEmbedding,
  synthesizeAnswer,
  resolvePersonDisambiguation,
  mergePersonNotes,
};
