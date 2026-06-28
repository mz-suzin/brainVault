/**
 * BrainVault — Memory Routes
 *
 * POST /api/memory/add   — Ingest a new memory (text or audio file)
 * POST /api/memory/query — Query stored memories with natural language
 */

const express = require('express');
const multer = require('multer');
const {
  extractMemoryFromText,
  extractMemoryFromAudio,
  generateEmbedding,
  synthesizeAnswer,
  resolvePersonDisambiguation,
} = require('../services/gemini');
const {
  insertMemory,
  hybridSearch,
  insertPerson,
  findPeopleByNames,
  linkMemoryToPeople,
} = require('../services/database');

const router = express.Router();

// ─────────────────────────────────────────────────────────────────────────────
// Multer Configuration (Audio File Upload)
// ─────────────────────────────────────────────────────────────────────────────

// Store uploaded audio files in memory (Buffer) — no disk needed
// 10 MB limit is generous for voice memos (1 min M4A ≈ 500 KB)
const upload = multer({
  storage: multer.memoryStorage(),
  limits: { fileSize: 10 * 1024 * 1024 },
  fileFilter: (_req, file, cb) => {
    // Accept common audio MIME types that Gemini supports
    const allowedTypes = [
      'audio/mp4',       // M4A container
      'audio/x-m4a',     // M4A alternate MIME
      'audio/m4a',       // M4A alternate MIME
      'audio/mpeg',      // MP3
      'audio/wav',       // WAV
      'audio/x-wav',     // WAV alternate MIME
      'audio/webm',      // WebM audio
      'audio/ogg',       // OGG audio
      'audio/aac',       // Raw AAC
    ];

    const isAllowedMime = allowedTypes.includes(file.mimetype);

    // Fallback: If generic mimetype, check file extension
    let isAllowedExtension = false;
    if (!isAllowedMime && file.mimetype === 'application/octet-stream') {
      const ext = file.originalname.split('.').pop().toLowerCase();
      const extToMime = {
        'm4a': 'audio/m4a',
        'mp3': 'audio/mpeg',
        'wav': 'audio/wav',
        'webm': 'audio/webm',
        'ogg': 'audio/ogg',
        'aac': 'audio/aac'
      };
      
      if (extToMime[ext]) {
        file.mimetype = extToMime[ext]; // Normalize the mimetype for Gemini
        isAllowedExtension = true;
      }
    }

    if (isAllowedMime || isAllowedExtension) {
      cb(null, true);
    } else {
      cb(new Error(`Unsupported audio format: ${file.mimetype}. Accepted: M4A, MP3, WAV, WebM, OGG`));
    }
  },
});

// ─────────────────────────────────────────────────────────────────────────────
// POST /api/memory/add
// ─────────────────────────────────────────────────────────────────────────────
//
// Accepts multipart/form-data with either:
//   - A "text" field (string) — for typed text memories
//   - An "audio" file field — for recorded audio memories
//
// Flow:
//   1. Validate input (text xor audio)
//   2. Send to Gemini for structured extraction
//   3. Generate 768-dim embedding
//   4. Persist to Supabase
//   5. Return saved memory metadata
// ─────────────────────────────────────────────────────────────────────────────

router.post('/add', upload.single('audio'), async (req, res) => {
  try {
    const textInput = req.body?.text?.trim();
    const audioFile = req.file;

    // ── Check if this is a constructed memory payload ───────────────────────
    const isConstructed = req.body?.description !== undefined;
    
    // ── Check if this is a resubmit with resolved name choices ────────────────
    const resolvedPeopleIds = req.body?.resolved_people_ids; // Array of UUIDs
    const tempExtraction = req.body?.temp_extraction; // Extracted JSON from first pass

    let extraction;
    let rawText;
    let sourceType;
    let linkedPersonIds = [];

    const currentDate = new Date().toISOString().split('T')[0]; // YYYY-MM-DD

    if (isConstructed) {
      // ───────────────────────────────────────────────────────────────────────
      // Path A: Structured "Construct a Memory" Ingestion
      // ───────────────────────────────────────────────────────────────────────
      sourceType = 'text';
      const description = req.body.description?.trim() || '';
      const location = req.body.location?.trim() || '';
      const eventDate = req.body.event_date;
      
      // Parse lists from body (usually sent as JSON strings or arrays)
      const peopleIds = Array.isArray(req.body.people_ids) 
        ? req.body.people_ids 
        : req.body.people_ids ? JSON.parse(req.body.people_ids) : [];
      const newPeople = Array.isArray(req.body.new_people) 
        ? req.body.new_people 
        : req.body.new_people ? JSON.parse(req.body.new_people) : [];

      console.log(`[ADD] Processing constructed memory: "${description.substring(0, 50)}..."`);

      // 1. Save any new inline people profiles
      for (const person of newPeople) {
        if (person.name?.trim()) {
          try {
            const created = await insertPerson({
              name: person.name.trim(),
              relation: person.relation || 'other',
              notes: person.notes || '',
            });
            linkedPersonIds.push(created.id);
          } catch (err) {
            // If unique constraint triggers (person already exists), we fetch them
            console.log(`[ADD] Person "${person.name}" already exists, fetching profile.`);
            const matches = await findPeopleByNames([person.name.trim()]);
            if (matches.length > 0) {
              linkedPersonIds.push(matches[0].id);
            }
          }
        }
      }

      // Merge with already selected people IDs
      linkedPersonIds = [...new Set([...linkedPersonIds, ...peopleIds])];

      // 2. Formulate rich text narrative description for embedding
      let locationText = location ? ` at ${location}` : '';
      let dateText = eventDate ? ` on ${eventDate}` : '';
      rawText = `Constructed Memory: ${description}${locationText}${dateText}.`;
      
      // Build a clean summary
      extraction = {
        event_date: eventDate || null,
        event_date_raw: eventDate || null,
        subject: req.body.subject?.trim() || 'milestone',
        tags: Array.isArray(req.body.tags) ? req.body.tags : [],
        cleaned_text: `${description}${locationText}.`,
      };

    } else if (resolvedPeopleIds && tempExtraction) {
      // ───────────────────────────────────────────────────────────────────────
      // Path B: Resubmitted Memory (W/ Resolved Ambiguities)
      // ───────────────────────────────────────────────────────────────────────
      console.log('[ADD] Processing resubmitted resolved memory');
      extraction = typeof tempExtraction === 'string' ? JSON.parse(tempExtraction) : tempExtraction;
      rawText = req.body.raw_text;
      sourceType = req.body.source_type;
      linkedPersonIds = Array.isArray(resolvedPeopleIds) ? resolvedPeopleIds : JSON.parse(resolvedPeopleIds);

    } else {
      // ───────────────────────────────────────────────────────────────────────
      // Path C: Standard Ingestion (Raw Text / Audio)
      // ───────────────────────────────────────────────────────────────────────
      if (!textInput && !audioFile) {
        return res.status(400).json({
          error: 'Please provide either a text memory or an audio recording.',
        });
      }

      if (audioFile) {
        sourceType = 'audio';
        console.log(`[ADD] Processing audio: ${audioFile.originalname} (${audioFile.mimetype}, ${audioFile.size} bytes)`);
        extraction = await extractMemoryFromAudio(audioFile.buffer, audioFile.mimetype, currentDate);
        rawText = extraction.raw_transcript || extraction.cleaned_text;
      } else {
        sourceType = 'text';
        rawText = textInput;
        console.log(`[ADD] Processing text: "${textInput.substring(0, 80)}..."`);
        extraction = await extractMemoryFromText(textInput, currentDate);
      }

      // ── Name Conflict Resolution / Disambiguation ──
      const details = extraction.people_details || [];
      if (details.length > 0) {
        console.log(`[ADD] People mentioned by LLM: ${details.map((p) => p.name).join(', ')}`);
        
        const conflicts = [];
        const resolvedIds = [];

        for (const person of details) {
          const name = person.name;
          const candidates = await findPeopleByNames([name]);
          
          if (candidates.length === 0) {
            // 0 matches -> This is a brand new person! Auto-create their profile.
            console.log(`[ADD] Creating profile automatically for new person: "${name}" (${person.relation})`);
            try {
              const created = await insertPerson({
                name: name,
                relation: person.relation || 'other',
                notes: person.notes || `Mentioned in memory: "${rawText.substring(0, 60)}..."`,
              });
              resolvedIds.push(created.id);
            } catch (err) {
              console.error(`[ADD] Auto-creation failed for "${name}":`, err.message);
            }
          } else if (candidates.length === 1) {
            // One exact match -> link automatically
            resolvedIds.push(candidates[0].id);
          } else if (candidates.length > 1) {
            // Multiple candidates -> Try contextual deduction via Gemini
            console.log(`[ADD] Ambiguity found for "${name}". ${candidates.length} candidates. Querying LLM...`);
            const resolution = await resolvePersonDisambiguation(rawText, name, candidates);
            
            if (resolution.resolved && resolution.resolved_id) {
              console.log(`[ADD] LLM successfully resolved "${name}" to ID: ${resolution.resolved_id}`);
              resolvedIds.push(resolution.resolved_id);
            } else {
              // LLM is unsure -> add to conflict list for interactive fallback
              console.log(`[ADD] LLM unable to resolve "${name}" confidently. Fallback to interactive.`);
              conflicts.push({ name, candidates });
            }
          }
        }

        // If there are conflicts we cannot resolve, halt execution and return them to the client
        if (conflicts.length > 0) {
          return res.json({
            status: 'disambiguation_required',
            conflicts: conflicts,
            temp_payload: {
              raw_text: rawText,
              source_type: sourceType,
              extraction: extraction,
              already_resolved_ids: resolvedIds,
            }
          });
        }

        linkedPersonIds = resolvedIds;
      }
    }

    // ───────────────────────────────────────────────────────────────────────
    // Step 3 & 4: Generate Embedding & Commit to Supabase
    // ───────────────────────────────────────────────────────────────────────
    const embedding = await generateEmbedding(extraction.cleaned_text);

    // Save core memory row
    const savedMemory = await insertMemory({
      ...extraction,
      raw_text: rawText,
      source_type: sourceType,
      embedding,
    });

    // Write relations in the join table
    if (linkedPersonIds.length > 0) {
      await linkMemoryToPeople(savedMemory.id, linkedPersonIds);
      console.log(`[ADD] Relational links written: ${linkedPersonIds.length} person/people connected.`);
    }

    console.log(`[ADD] Memory saved: ${savedMemory.id} (${sourceType}, subject: ${savedMemory.subject})`);

    return res.status(201).json({
      success: true,
      memory: savedMemory,
    });
  } catch (err) {
    console.error('[ADD] Error:', err.message);
    return res.status(500).json({ error: err.message });
  }
});

// ─────────────────────────────────────────────────────────────────────────────
// POST /api/memory/query
// ─────────────────────────────────────────────────────────────────────────────
//
// Body: { "question": "When did I run my first marathon?" }
//
// Flow:
//   1. Generate embedding for the question
//   2. Hybrid search (vector + keyword) against the DB
//   3. Pass matched memories as context to Gemini
//   4. Return synthesized answer + source references
// ─────────────────────────────────────────────────────────────────────────────

router.post('/query', async (req, res) => {
  try {
    const { question } = req.body;

    if (!question?.trim()) {
      return res.status(400).json({
        error: 'Please provide a question.',
      });
    }

    const trimmedQuestion = question.trim();
    console.log(`[QUERY] "${trimmedQuestion}"`);

    // Step 1: Embed the question for semantic search
    const queryEmbedding = await generateEmbedding(trimmedQuestion);

    // Step 2: Hybrid search — semantic + keyword, top 5 results
    const matches = await hybridSearch(queryEmbedding, trimmedQuestion, 5);

    // Step 3: Handle empty results
    if (matches.length === 0) {
      return res.json({
        answer:
          "I don't have any memories that match your question yet. " +
          'Try adding some memories first!',
        sources: [],
      });
    }

    // Step 4: Synthesize a natural language answer from context
    const answer = await synthesizeAnswer(trimmedQuestion, matches);

    // Step 5: Format source references for the client
    const sources = matches.map((m) => ({
      id: m.id,
      event_date: m.event_date,
      subject: m.subject,
      tags: m.tags,
      summary: m.cleaned_text,
      relevance: Math.round((m.similarity_score || 0) * 100),
    }));

    console.log(`[QUERY] Answered with ${sources.length} source(s)`);

    return res.json({ answer, sources });
  } catch (err) {
    console.error('[QUERY] Error:', err.message);
    return res.status(500).json({ error: err.message });
  }
});

module.exports = router;
