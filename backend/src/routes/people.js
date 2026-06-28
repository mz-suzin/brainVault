/**
 * BrainVault — People Routes
 *
 * GET  /api/people - Get list of all registered people profiles
 * POST /api/people - Add a new person profile to the directory
 */

const express = require('express');
const { getAllPeople, insertPerson } = require('../services/database');

const router = express.Router();

// ── GET /api/people ─────────────────────────────────────────────────────────
router.get('/', async (_req, res) => {
  try {
    const people = await getAllPeople();
    return res.json(people);
  } catch (err) {
    console.error('[PEOPLE] Fetch error:', err.message);
    return res.status(500).json({ error: err.message });
  }
});

// ── POST /api/people ────────────────────────────────────────────────────────
router.post('/', async (req, res) => {
  try {
    const { name, relation, notes } = req.body;

    if (!name?.trim() || !relation?.trim()) {
      return res.status(400).json({
        error: 'Please provide both a name and a relationship type.',
      });
    }

    const newPerson = await insertPerson({
      name: name.trim(),
      relation: relation.trim(),
      notes: notes ? notes.trim() : '',
    });

    console.log(`[PEOPLE] Profile created: ${newPerson.name} (${newPerson.relation})`);

    return res.status(201).json(newPerson);
  } catch (err) {
    console.error('[PEOPLE] Create error:', err.message);
    return res.status(500).json({ error: err.message });
  }
});

module.exports = router;
