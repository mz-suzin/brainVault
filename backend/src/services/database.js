/**
 * BrainVault — Database Service
 *
 * Handles all Supabase/PostgreSQL interactions:
 * - Memory insertion with embedding vectors
 * - Hybrid search (semantic + keyword) via RPC function
 * - Health ping to prevent Supabase free-tier inactivity pause
 */

const { createClient } = require('@supabase/supabase-js');

// ─────────────────────────────────────────────────────────────────────────────
// Initialize Supabase Client
// ─────────────────────────────────────────────────────────────────────────────

// Initialize Supabase Client using the Secret Key (formerly service_role key)
// This is safe because the backend is the only client — the key is never exposed to the frontend.
const supabaseSecretKey = process.env.SUPABASE_SECRET_KEY || process.env.SUPABASE_SERVICE_KEY;

const supabase = createClient(
  process.env.SUPABASE_URL,
  supabaseSecretKey
);

// ─────────────────────────────────────────────────────────────────────────────
// Memory Operations
// ─────────────────────────────────────────────────────────────────────────────

/**
 * Insert a new memory record into the database.
 *
 * @param {Object} memoryData
 * @param {string|null} memoryData.event_date - Extracted date (YYYY-MM-DD) or null
 * @param {string|null} memoryData.event_date_raw - Original date expression or null
 * @param {string} memoryData.subject - LLM-extracted category
 * @param {string[]} memoryData.tags - LLM-extracted entity tags
 * @param {string} memoryData.raw_text - Original user input or transcript
 * @param {string} memoryData.cleaned_text - LLM-cleaned summary
 * @param {string} memoryData.source_type - 'text' or 'audio'
 * @param {number[]} memoryData.embedding - 768-dim vector from gemini-embedding-001
 * @returns {Promise<Object>} The inserted memory record (id, created_at, event_date, subject, tags)
 */
async function insertMemory(memoryData) {
  // Format the embedding as a pgvector-compatible string: [0.1,0.2,...]
  const embeddingStr = `[${memoryData.embedding.join(',')}]`;

  const { data, error } = await supabase
    .from('memories')
    .insert({
      event_date: memoryData.event_date,
      event_date_raw: memoryData.event_date_raw,
      subject: memoryData.subject,
      tags: memoryData.tags,
      raw_text: memoryData.raw_text,
      cleaned_text: memoryData.cleaned_text,
      source_type: memoryData.source_type,
      embedding: embeddingStr,
    })
    .select('id, created_at, event_date, subject, tags, cleaned_text')
    .single();

  if (error) {
    console.error('[DB] Insert error:', error.message);
    throw new Error(`Database insert failed: ${error.message}`);
  }

  return data;
}

/**
 * Perform hybrid search combining semantic vector similarity and keyword matching.
 * Calls the `hybrid_search` PostgreSQL function deployed via search_function.sql.
 *
 * @param {number[]} queryEmbedding - 768-dim embedding of the query
 * @param {string} queryText - Original query text for trigram keyword matching
 * @param {number} [limit=5] - Maximum number of results to return
 * @returns {Promise<Object[]>} Array of matched memory records with similarity_score
 */
async function hybridSearch(queryEmbedding, queryText, limit = 5) {
  const embeddingStr = `[${queryEmbedding.join(',')}]`;

  const { data, error } = await supabase.rpc('hybrid_search', {
    query_embedding: embeddingStr,
    query_text: queryText,
    match_limit: limit,
  });

  if (error) {
    console.error('[DB] Hybrid search error:', error.message);
    throw new Error(`Database search failed: ${error.message}`);
  }

  return data || [];
}

/**
 * Lightweight health ping to keep the Supabase free-tier project active.
 * Supabase pauses free projects after 1 week of inactivity.
 * This function performs a trivial SELECT to register activity.
 *
 * @returns {Promise<boolean>} True if the database is reachable, false otherwise
 */
async function ping() {
  try {
    const { error } = await supabase
      .from('memories')
      .select('id')
      .limit(1);
    return !error;
  } catch {
    return false;
  }
}

module.exports = {
  insertMemory,
  hybridSearch,
  ping,
};
