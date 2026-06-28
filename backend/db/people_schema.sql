-- ============================================================================
-- BrainVault — Database Migration: People Directory & Relational Linking
-- Run this in your Supabase SQL Editor (Dashboard → SQL Editor → New Query)
-- ============================================================================

-- ────────────────────────────────────────────────────────────────────────────
-- 1. Create the People Table
-- ────────────────────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS people (
  -- Primary key
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  
  -- Name of the person (case-insensitive checks can be done at application level)
  name        TEXT NOT NULL,
  
  -- Relationship type (e.g. friend, family, colleague, enemy, best friend)
  relation    TEXT NOT NULL,
  
  -- Key notes/memories/facts about this person
  notes       TEXT NOT NULL DEFAULT '',
  
  -- Date created
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),

  -- Ensure we don't have exact duplicate profiles with the same name + relation
  CONSTRAINT unique_name_relation UNIQUE (name, relation)
);

-- Index by name for fast lookup during name disambiguation checks
CREATE INDEX IF NOT EXISTS idx_people_name ON people (name);

-- ────────────────────────────────────────────────────────────────────────────
-- 2. Create the Memory-People Join Table (Many-to-Many)
-- ────────────────────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS memory_people (
  -- Link to memory (cascades delete so deleting memory auto-removes link)
  memory_id   UUID REFERENCES memories(id) ON DELETE CASCADE,
  
  -- Link to person (cascades delete so deleting person profile auto-removes link)
  person_id   UUID REFERENCES people(id) ON DELETE CASCADE,
  
  -- Primary composite key
  PRIMARY KEY (memory_id, person_id)
);

-- Index the foreign keys for fast join query execution
CREATE INDEX IF NOT EXISTS idx_memory_people_memory_id ON memory_people (memory_id);
CREATE INDEX IF NOT EXISTS idx_memory_people_person_id ON memory_people (person_id);
