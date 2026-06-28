-- ============================================================================
-- BrainVault — Hybrid Search Function
-- Deploy via Supabase SQL Editor AFTER running schema.sql
--
-- This function combines:
--   1. Semantic search (pgvector cosine similarity on embeddings)
--   2. Keyword search  (pg_trgm trigram similarity on cleaned_text)
-- Results are scored with configurable weights and merged.
-- ============================================================================

CREATE OR REPLACE FUNCTION hybrid_search(
  query_embedding VECTOR(768),  -- The query's embedding vector
  query_text      TEXT,          -- The raw query text for keyword matching
  match_limit     INT DEFAULT 5, -- Max results to return
  semantic_weight FLOAT DEFAULT 0.7, -- Weight for vector similarity (0-1)
  keyword_weight  FLOAT DEFAULT 0.3  -- Weight for keyword similarity (0-1)
)
RETURNS TABLE (
  id               UUID,
  created_at       TIMESTAMPTZ,
  event_date       DATE,
  event_date_raw   TEXT,
  subject          TEXT,
  tags             TEXT[],
  raw_text         TEXT,
  cleaned_text     TEXT,
  source_type      TEXT,
  similarity_score FLOAT
)
LANGUAGE plpgsql
AS $$
BEGIN
  RETURN QUERY

  -- Step 1: Get top candidates from semantic (vector) search
  WITH semantic AS (
    SELECT
      m.id,
      -- Cosine similarity = 1 - cosine distance
      1 - (m.embedding <=> query_embedding) AS semantic_sim
    FROM memories m
    ORDER BY m.embedding <=> query_embedding
    LIMIT match_limit * 3  -- Over-fetch to allow merging
  ),

  -- Step 2: Get top candidates from keyword (trigram) search
  keyword AS (
    SELECT
      m.id,
      similarity(m.cleaned_text, query_text) AS keyword_sim
    FROM memories m
    WHERE
      query_text IS NOT NULL
      AND query_text != ''
      AND m.cleaned_text % query_text  -- % operator uses pg_trgm.similarity_threshold
    LIMIT match_limit * 3
  ),

  -- Step 3: Merge results with weighted scoring
  combined AS (
    SELECT
      COALESCE(s.id, k.id) AS id,
      (COALESCE(s.semantic_sim, 0) * semantic_weight) +
      (COALESCE(k.keyword_sim, 0) * keyword_weight) AS combined_score
    FROM semantic s
    FULL OUTER JOIN keyword k ON s.id = k.id
  )

  -- Step 4: Join back to memories table for full record data
  SELECT
    m.id,
    m.created_at,
    m.event_date,
    m.event_date_raw,
    m.subject,
    m.tags,
    m.raw_text,
    m.cleaned_text,
    m.source_type,
    c.combined_score::FLOAT AS similarity_score
  FROM combined c
  JOIN memories m ON m.id = c.id
  ORDER BY c.combined_score DESC
  LIMIT match_limit;

END;
$$;
