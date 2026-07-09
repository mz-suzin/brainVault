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
  mergePersonNotes,
} = require('../services/gemini');
const {
  insertMemory,
  hybridSearch,
  insertPerson,
  findPeopleByNames,
  linkMemoryToPeople,
  updatePerson,
  getPersonById,
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

    let isResubmitted = false;

    if (resolvedPeopleIds && tempExtraction) {
      // ───────────────────────────────────────────────────────────────────────
      // Path B: Resubmitted Memory (W/ Resolved Ambiguities)
      // ───────────────────────────────────────────────────────────────────────
      console.log('[ADD] Processing resubmitted resolved memory');
      isResubmitted = true;
      extraction = typeof tempExtraction === 'string' ? JSON.parse(tempExtraction) : tempExtraction;
      rawText = req.body.raw_text;
      sourceType = req.body.source_type;
      linkedPersonIds = Array.isArray(resolvedPeopleIds) ? resolvedPeopleIds : JSON.parse(resolvedPeopleIds);

      // Merge new facts for the resolved people profiles
      for (const id of linkedPersonIds) {
        try {
          const profile = await getPersonById(id);
          if (profile) {
            const details = (extraction.people_details || []).find((p) => p.name === profile.name);
            if (details) {
              const relation = details.relation !== 'other' ? details.relation : profile.relation;
              const mergedNotes = await mergePersonNotes(profile.notes, details.notes);
              await updatePerson(id, { relation, notes: mergedNotes });
            }
          }
        } catch (err) {
          console.error(`[ADD] Failed to merge notes during resubmit for ID "${id}":`, err.message);
        }
      }
    } else if (isConstructed) {
      // ───────────────────────────────────────────────────────────────────────
      // Path A: Structured "Construct a Memory" Ingestion
      // ───────────────────────────────────────────────────────────────────────
      sourceType = 'text';
      const description = req.body.description?.trim() || '';
      const location = req.body.location?.trim() || '';
      const eventDate = req.body.event_date;
      
      const peopleIds = Array.isArray(req.body.people_ids) 
        ? req.body.people_ids 
        : req.body.people_ids ? JSON.parse(req.body.people_ids) : [];
      const newPeople = Array.isArray(req.body.new_people) 
        ? req.body.new_people 
        : req.body.new_people ? JSON.parse(req.body.new_people) : [];

      // Save any new inline people profiles
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
            // If unique constraint triggers (person already exists), fetch them
            const matches = await findPeopleByNames([person.name.trim()]);
            if (matches.length > 0) linkedPersonIds.push(matches[0].id);
          }
        }
      }

      linkedPersonIds = [...new Set([...linkedPersonIds, ...peopleIds])];

      const explicitPeopleNames = [];
      for (const id of linkedPersonIds) {
        try {
          const profile = await getPersonById(id);
          if (profile) explicitPeopleNames.push(profile.name);
        } catch (e) {}
      }

      let locationText = location ? ` em ${location}` : '';
      let dateText = eventDate ? ` no dia ${eventDate}` : '';
      rawText = `${description}${locationText}${dateText}.`;
      
      let llmText = rawText;
      if (explicitPeopleNames.length > 0) {
        llmText += ` [Note: The user explicitly indicated that these people are involved in this memory: ${explicitPeopleNames.join(', ')}. Resolve pronouns like "we" or "nós" to include them.]`;
      }
      
      console.log(`[ADD] Processing constructed memory text via LLM: "${llmText.substring(0, 80)}..."`);
      extraction = await extractMemoryFromText(llmText, currentDate);

      // Honor the explicitly constructed date if provided
      if (eventDate) {
        extraction.event_date = eventDate;
        extraction.event_date_raw = eventDate;
      }
    } else {
      // ───────────────────────────────────────────────────────────────────────
      // Path C: Standard Ingestion (Raw Text / Audio)
      // ───────────────────────────────────────────────────────────────────────
      if (!textInput && !audioFile) {
        return res.status(400).json({ error: 'Please provide either a text memory or an audio recording.' });
      }

      if (audioFile) {
        sourceType = 'audio';
        console.log(`[ADD] Processing audio: ${audioFile.originalname}`);
        extraction = await extractMemoryFromAudio(audioFile.buffer, audioFile.mimetype, currentDate);
        rawText = extraction.raw_transcript || extraction.cleaned_text;
      } else {
        sourceType = 'text';
        rawText = textInput;
        console.log(`[ADD] Processing text: "${textInput.substring(0, 50)}..."`);
        extraction = await extractMemoryFromText(textInput, currentDate);
      }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // ── Name Conflict Resolution / Disambiguation (Paths A & C)
    // ─────────────────────────────────────────────────────────────────────────
    if (!isResubmitted) {
      const details = extraction.people_details || [];
      if (details.length > 0) {
        console.log(`[ADD] People mentioned by LLM: ${details.map((p) => p.name).join(', ')}`);
        
        const conflicts = [];
        const resolvedIds = [];

        for (const person of details) {
          const name = person.name;
          const candidates = await findPeopleByNames([name]);
          
          if (candidates.length === 0) {
            // Brand new person auto-creation
            console.log(`[ADD] Auto-creating profile for new person: "${name}"`);
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
            // One exact match -> merge facts
            const match = candidates[0];
            const relation = person.relation !== 'other' ? person.relation : match.relation;
            try {
              const mergedNotes = await mergePersonNotes(match.notes, person.notes);
              await updatePerson(match.id, { relation, notes: mergedNotes });
            } catch (err) {}
            resolvedIds.push(match.id);
          } else if (candidates.length > 1) {
            // Multiple candidates -> contextual deduction
            console.log(`[ADD] Ambiguity found for "${name}". Querying LLM...`);
            const resolution = await resolvePersonDisambiguation(rawText, name, candidates);
            
            if (resolution.resolved && resolution.resolved_id) {
              const match = candidates.find((c) => c.id === resolution.resolved_id);
              if (match) {
                const relation = person.relation !== 'other' ? person.relation : match.relation;
                try {
                  const mergedNotes = await mergePersonNotes(match.notes, person.notes);
                  await updatePerson(match.id, { relation, notes: mergedNotes });
                } catch (err) {}
              }
              resolvedIds.push(resolution.resolved_id);
            } else {
              conflicts.push({ name, candidates });
            }
          }
        }

        if (conflicts.length > 0) {
          return res.json({
            status: 'disambiguation_required',
            conflicts: conflicts,
            temp_payload: {
              raw_text: rawText,
              source_type: sourceType,
              extraction: extraction,
              already_resolved_ids: [...new Set([...linkedPersonIds, ...resolvedIds])],
            }
          });
        }

        // Merge LLM-resolved IDs with any pre-selected IDs from wizard
        linkedPersonIds = [...new Set([...linkedPersonIds, ...resolvedIds])];
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

    // Step 4: Synthesize a natural language answer from ALL context
    //         (even low-relevance matches can help the LLM)
    const answer = await synthesizeAnswer(trimmedQuestion, matches);

    // Step 5: Format source references for the client
    const allSources = matches.map((m) => ({
      id: m.id,
      event_date: m.event_date,
      subject: m.subject,
      tags: m.tags,
      summary: m.cleaned_text,
      raw_text: m.raw_text,
      created_at: m.created_at,
      relevance: Math.round((m.similarity_score || 0) * 100),
    }));

    // Step 6: Filter out low-relevance noise from source cards
    //   - Absolute floor: discard anything below 25% combined score
    //   - Relative gap: discard if less than 35% of the top result's score
    //   (This prevents unrelated memories from showing as "sources")
    const topRelevance = allSources.length > 0 ? allSources[0].relevance : 0;
    const relativeThreshold = Math.round(topRelevance * 0.35);
    const sources = allSources.filter(
      (s) => s.relevance >= 25 && s.relevance >= relativeThreshold
    );

    console.log(`[QUERY] Answered with ${sources.length}/${allSources.length} source(s) (filtered by relevance)`);

    return res.json({ answer, sources });
  } catch (err) {
    console.error('[QUERY] Error:', err.message);
    return res.status(500).json({ error: err.message });
  }
});

module.exports = router;
