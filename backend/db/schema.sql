-- ============================================================================
-- BrainVault — Database Schema
-- Run this in your Supabase SQL Editor (Dashboard → SQL Editor → New Query)
-- ============================================================================

-- ────────────────────────────────────────────────────────────────────────────
-- 1. Enable Required Extensions
-- ────────────────────────────────────────────────────────────────────────────

-- pgvector: Enables vector storage and similarity search
CREATE EXTENSION IF NOT EXISTS vector;

-- pg_trgm: Enables trigram-based fuzzy text matching
CREATE EXTENSION IF NOT EXISTS pg_trgm;

-- ────────────────────────────────────────────────────────────────────────────
-- 2. Create the Memories Table
-- ────────────────────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS memories (
  -- Primary key: auto-generated UUID
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),

  -- Timestamp of when the memory was ingested
  created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),

  -- LLM-extracted event date (nullable — some memories have no clear date)
  event_date      DATE,

  -- Original date expression from user input (e.g., "last summer", "March 2024")
  event_date_raw  TEXT,

  -- LLM-extracted category (e.g., "fitness", "travel", "work")
  subject         TEXT NOT NULL,

  -- LLM-extracted key entities as a PostgreSQL array
  tags            TEXT[] NOT NULL DEFAULT '{}',

  -- Original user input (text) or LLM transcript (audio)
  raw_text        TEXT NOT NULL,

  -- LLM-cleaned, normalized summary of the memory
  cleaned_text    TEXT NOT NULL,

  -- Input source: 'text' or 'audio'
  source_type     TEXT NOT NULL CHECK (source_type IN ('text', 'audio')),

  -- 768-dimensional embedding vector from gemini-embedding-001
  embedding       VECTOR(768) NOT NULL
);

-- ────────────────────────────────────────────────────────────────────────────
-- 3. Create Indexes for Hybrid Search Performance
-- ────────────────────────────────────────────────────────────────────────────

-- HNSW index for fast approximate nearest-neighbor vector search
-- Uses cosine distance operator for semantic similarity
CREATE INDEX IF NOT EXISTS idx_memories_embedding
  ON memories USING hnsw (embedding vector_cosine_ops);

-- GIN trigram index for fuzzy keyword search on cleaned_text
CREATE INDEX IF NOT EXISTS idx_memories_cleaned_text_trgm
  ON memories USING gin (cleaned_text gin_trgm_ops);

-- B-tree index for temporal range queries on event_date
CREATE INDEX IF NOT EXISTS idx_memories_event_date
  ON memories USING btree (event_date);

-- GIN index for efficient tag-based filtering
CREATE INDEX IF NOT EXISTS idx_memories_tags
  ON memories USING gin (tags);

-- B-tree index on created_at for chronological ordering
CREATE INDEX IF NOT EXISTS idx_memories_created_at
  ON memories USING btree (created_at DESC);

-- ────────────────────────────────────────────────────────────────────────────
-- 4. Set the trigram similarity threshold (for keyword matching)
-- ────────────────────────────────────────────────────────────────────────────

-- Lower threshold = more fuzzy matches (default is 0.3)
-- 0.15 allows partial word matching, good for memory queries
ALTER DATABASE postgres SET pg_trgm.similarity_threshold = 0.15;
