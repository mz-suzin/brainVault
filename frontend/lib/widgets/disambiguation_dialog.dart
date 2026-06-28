/// BrainVault — Disambiguation Bottom Sheet
///
/// Displayed when the backend returns a name conflict (e.g., multiple Johns).
/// Prompts the user to select the correct profile.

import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../models/memory.dart';

class DisambiguationDialog extends StatefulWidget {
  final List<dynamic> conflicts;
  final Map<String, dynamic> tempPayload;
  final Function(Memory) onResolved;

  const DisambiguationDialog({
    super.key,
    required this.conflicts,
    required this.tempPayload,
    required this.onResolved,
  });

  @override
  State<DisambiguationDialog> createState() => _DisambiguationDialogState();
}

class _DisambiguationDialogState extends State<DisambiguationDialog> {
  // Store resolved ID selection per name conflict
  // Format: { "John": "selected-uuid" }
  final Map<String, String> _selections = {};
  bool _isSaving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    // Default select first candidate for each conflict
    for (var conflict in widget.conflicts) {
      final name = conflict['name'] as String;
      final candidates = conflict['candidates'] as List<dynamic>;
      if (candidates.isNotEmpty) {
        _selections[name] = candidates[0]['id'] as String;
      }
    }
  }

  Future<void> _submitResolution() async {
    final List<String> resolvedIds = [];

    // Combine manual selections
    _selections.forEach((_, value) {
      resolvedIds.add(value);
    });

    // Combine previously resolved IDs from the initial pass
    final alreadyResolved = widget.tempPayload['already_resolved_ids'] as List<dynamic>?;
    if (alreadyResolved != null) {
      resolvedIds.addAll(alreadyResolved.map((e) => e.toString()));
    }

    setState(() {
      _isSaving = true;
      _error = null;
    });

    try {
      final memory = await ApiService.resolveMemoryConflict(
        resolvedIds,
        widget.tempPayload,
      );
      widget.onResolved(memory);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      setState(() {
        _isSaving = false;
        _error = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
      decoration: const BoxDecoration(
        color: Color(0xFF0F0F1A),
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(24),
          topRight: Radius.circular(24),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Drag handle
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: const Color(0xFFE8E8F0).withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 20),

          // Header
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFB300).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.help_outline_rounded,
                  color: Color(0xFFFFB300),
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              const Text(
                'Resolve Name Conflict',
                style: TextStyle(
                  color: Color(0xFFE8E8F0),
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'We found multiple people matching the name(s) in your memory. Please select the correct profile:',
            style: TextStyle(
              color: const Color(0xFFE8E8F0).withValues(alpha: 0.5),
              fontSize: 14,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 20),

          // Conflicts List
          Flexible(
            child: SingleChildScrollView(
              child: Column(
                children: widget.conflicts.map<Widget>((conflict) {
                  final name = conflict['name'] as String;
                  final candidates = conflict['candidates'] as List<dynamic>;

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8.0),
                        child: Text(
                          'Who is "$name"?',
                          style: const TextStyle(
                            color: Color(0xFF4FC3F7),
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      ...candidates.map<Widget>((candidate) {
                        final id = candidate['id'] as String;
                        final relation = candidate['relation'] as String;
                        final notes = candidate['notes'] as String? ?? '';

                        return Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          decoration: BoxDecoration(
                            color: const Color(0xFF1A1A2E).withValues(alpha: 0.5),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: _selections[name] == id
                                  ? const Color(0xFF6C63FF)
                                  : const Color(0xFF6C63FF).withValues(alpha: 0.1),
                              width: 1,
                            ),
                          ),
                          child: RadioListTile<String>(
                            value: id,
                            groupValue: _selections[name],
                            onChanged: _isSaving
                                ? null
                                : (val) {
                                    setState(() {
                                      if (val != null) _selections[name] = val;
                                    });
                                  },
                            activeColor: const Color(0xFF6C63FF),
                            title: Text(
                              '$name ($relation)',
                              style: const TextStyle(
                                color: Color(0xFFE8E8F0),
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            subtitle: notes.isNotEmpty
                                ? Text(
                                    notes,
                                    style: TextStyle(
                                      color: const Color(0xFFE8E8F0).withValues(alpha: 0.4),
                                      fontSize: 12,
                                    ),
                                  )
                                : null,
                          ),
                        );
                      }),
                      const SizedBox(height: 12),
                    ],
                  );
                }).toList(),
              ),
            ),
          ),

          if (_error != null) ...[
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                _error!,
                style: const TextStyle(color: Color(0xFFCF6679), fontSize: 13),
              ),
            ),
          ],
          const SizedBox(height: 16),

          // Confirm button
          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton(
              onPressed: _isSaving ? null : _submitResolution,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF6C63FF),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                elevation: 0,
              ),
              child: _isSaving
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Text(
                      'Confirm Selection',
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}
