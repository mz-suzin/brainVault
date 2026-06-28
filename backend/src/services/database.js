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

// ─────────────────────────────────────────────────────────────────────────────
// People Directory Operations
// ─────────────────────────────────────────────────────────────────────────────

/**
 * Fetch all registered people profiles from the database, sorted alphabetically.
 *
 * @returns {Promise<Object[]>} Array of { id, name, relation, notes, created_at }
 */
async function getAllPeople() {
  const { data, error } = await supabase
    .from('people')
    .select('id, name, relation, notes, created_at')
    .order('name', { ascending: true });

  if (error) {
    console.error('[DB] getAllPeople error:', error.message);
    throw new Error(`Database fetch failed: ${error.message}`);
  }

  return data || [];
}

/**
 * Insert a new person profile into the database.
 *
 * @param {Object} personData
 * @param {string} personData.name - Person's name
 * @param {string} personData.relation - E.g. friend, family, enemy
 * @param {string} [personData.notes] - Key details
 * @returns {Promise<Object>} The newly created person record
 */
async function insertPerson(personData) {
  const { data, error } = await supabase
    .from('people')
    .insert({
      name: personData.name,
      relation: personData.relation,
      notes: personData.notes || '',
    })
    .select('id, name, relation, notes, created_at')
    .single();

  if (error) {
    console.error('[DB] insertPerson error:', error.message);
    throw new Error(`Failed to create person: ${error.message}`);
  }

  return data;
}

/**
 * Find existing people profiles matching a list of names.
 * Used for auto-linking matches during ingestion.
 *
 * @param {string[]} names - List of names to search for (case-insensitive)
 * @returns {Promise<Object[]>} Array of matching people rows
 */
async function findPeopleByNames(names) {
  if (!names || names.length === 0) return [];

  // Match names using simple case-insensitive matching
  const { data, error } = await supabase
    .from('people')
    .select('id, name, relation, notes')
    .in('name', names);

  if (error) {
    console.error('[DB] findPeopleByNames error:', error.message);
    throw new Error(`Database search failed: ${error.message}`);
  }

  return data || [];
}

/**
 * Link a memory to multiple people profiles via the many-to-many join table.
 *
 * @param {string} memoryId - UUID of the memory
 * @param {string[]} personIds - UUID list of the people involved
 * @returns {Promise<void>}
 */
async function linkMemoryToPeople(memoryId, personIds) {
  if (!personIds || personIds.length === 0) return;

  const joinRows = personIds.map((pid) => ({
    memory_id: memoryId,
    person_id: pid,
  }));

  const { error } = await supabase
    .from('memory_people')
    .insert(joinRows);

  if (error) {
    console.error('[DB] linkMemoryToPeople error:', error.message);
    throw new Error(`Failed to link memory to people: ${error.message}`);
  }
}

/**
 * Update an existing person profile's relation and notes.
 *
 * @param {string} id - UUID of the person
 * @param {Object} updateData
 * @param {string} [updateData.relation] - Relationship type
 * @param {string} [updateData.notes] - Consolidated notes
 * @returns {Promise<Object>} The updated person record
 */
async function updatePerson(id, updateData) {
  const fields = {};
  if (updateData.relation) fields.relation = updateData.relation;
  if (updateData.notes !== undefined) fields.notes = updateData.notes;

  const { data, error } = await supabase
    .from('people')
    .update(fields)
    .eq('id', id)
    .select('id, name, relation, notes, created_at')
    .single();

  if (error) {
    console.error('[DB] updatePerson error:', error.message);
    throw new Error(`Failed to update person: ${error.message}`);
  }

  return data;
}

/**
 * Fetch a single person profile by UUID.
 *
 * @param {string} id - UUID of the person
 * @returns {Promise<Object|null>} The person record or null
 */
async function getPersonById(id) {
  const { data, error } = await supabase
    .from('people')
    .select('id, name, relation, notes')
    .eq('id', id)
    .single();

  if (error) {
    if (error.code === 'PGRST116') return null; // Row not found
    console.error('[DB] getPersonById error:', error.message);
    throw new Error(`Failed to fetch person by ID: ${error.message}`);
  }

  return data;
}

module.exports = {
  insertMemory,
  hybridSearch,
  ping,
  getAllPeople,
  insertPerson,
  findPeopleByNames,
  linkMemoryToPeople,
  updatePerson,
  getPersonById,
};
