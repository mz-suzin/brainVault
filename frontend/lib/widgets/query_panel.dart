/// BrainVault — Query Panel Widget
///
/// A search bar for asking natural language questions about stored memories.
/// Displays the LLM-synthesized answer and source memory references
/// in a scrollable dark terminal-style output area.

import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../models/memory.dart';

class QueryPanel extends StatefulWidget {
  const QueryPanel({super.key});

  @override
  State<QueryPanel> createState() => _QueryPanelState();
}

class _QueryPanelState extends State<QueryPanel> {
  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  bool _isLoading = false;
  QueryResult? _result;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _submitQuery() async {
    final question = _controller.text.trim();
    if (question.isEmpty) return;

    setState(() {
      _isLoading = true;
      _error = null;
      _result = null;
    });

    try {
      final result = await ApiService.queryMemories(question);
      if (!mounted) return;
      setState(() => _result = result);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _error = e.message);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = 'Something went wrong. Please try again.');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A2E).withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: const Color(0xFF4FC3F7).withValues(alpha: 0.2),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF4FC3F7).withValues(alpha: 0.05),
            blurRadius: 20,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Section header ──────────────────────────────────────────
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFF4FC3F7).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.psychology_rounded,
                  color: Color(0xFF4FC3F7),
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              const Text(
                'Ask Your Brain',
                style: TextStyle(
                  color: Color(0xFFE8E8F0),
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.3,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // ── Search input + send button ──────────────────────────────
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _controller,
                  enabled: !_isLoading,
                  onSubmitted: (_) => _submitQuery(),
                  textCapitalization: TextCapitalization.sentences,
                  style: const TextStyle(
                    color: Color(0xFFE8E8F0),
                    fontSize: 15,
                  ),
                  decoration: InputDecoration(
                    filled: true,
                    fillColor:
                        const Color(0xFF0F0F1A).withValues(alpha: 0.6),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide.none,
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: const BorderSide(
                        color: Color(0xFF4FC3F7),
                        width: 1.5,
                      ),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 14,
                    ),
                    prefixIcon: Icon(
                      Icons.search_rounded,
                      color: const Color(0xFFE8E8F0).withValues(alpha: 0.3),
                      size: 20,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              SizedBox(
                height: 48,
                width: 48,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _submitQuery,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF4FC3F7),
                    foregroundColor: Colors.white,
                    disabledBackgroundColor:
                        const Color(0xFF4FC3F7).withValues(alpha: 0.4),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    padding: EdgeInsets.zero,
                    elevation: 0,
                  ),
                  child: _isLoading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.send_rounded, size: 20),
                ),
              ),
            ],
          ),

          // ── Output area (results / loading / error) ────────────────
          if (_isLoading || _result != null || _error != null) ...[
            const SizedBox(height: 16),
            _buildOutputArea(),
          ],
        ],
      ),
    );
  }

  /// Terminal-style output container
  Widget _buildOutputArea() {
    return Container(
      constraints: const BoxConstraints(maxHeight: 300),
      decoration: BoxDecoration(
        color: const Color(0xFF0A0A14),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: const Color(0xFF4FC3F7).withValues(alpha: 0.1),
          width: 1,
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: SingleChildScrollView(
          controller: _scrollController,
          padding: const EdgeInsets.all(16),
          child: _isLoading
              ? _buildLoadingIndicator()
              : _error != null
                  ? _buildError()
                  : _buildResult(),
        ),
      ),
    );
  }

  /// Skeleton loading with spinning indicator
  Widget _buildLoadingIndicator() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: const Color(0xFF4FC3F7).withValues(alpha: 0.7),
              ),
            ),
            const SizedBox(width: 10),
            Text(
              'Searching your memories...',
              style: TextStyle(
                color: const Color(0xFF4FC3F7).withValues(alpha: 0.7),
                fontSize: 13,
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        // Skeleton placeholder lines
        ...List.generate(
          3,
          (i) => Padding(
            padding: EdgeInsets.only(bottom: 8, right: i * 40.0),
            child: Container(
              height: 12,
              decoration: BoxDecoration(
                color: const Color(0xFF1A1A2E).withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// Error display
  Widget _buildError() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(Icons.error_outline, color: Color(0xFFCF6679), size: 18),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            _error!,
            style: const TextStyle(
              color: Color(0xFFCF6679),
              fontSize: 14,
              height: 1.5,
            ),
          ),
        ),
      ],
    );
  }

  /// Successful query result with answer and source cards
  Widget _buildResult() {
    if (_result == null) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // LLM-synthesized answer
        Text(
          _result!.answer,
          style: const TextStyle(
            color: Color(0xFFE8E8F0),
            fontSize: 14,
            height: 1.6,
          ),
        ),

        // Source memory references
        if (_result!.sources.isNotEmpty) ...[
          const SizedBox(height: 16),
          Divider(
            color: const Color(0xFFE8E8F0).withValues(alpha: 0.1),
            height: 1,
          ),
          const SizedBox(height: 12),
          Text(
            'Sources',
            style: TextStyle(
              color: const Color(0xFF4FC3F7).withValues(alpha: 0.7),
              fontSize: 12,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 8),
          ...(_result!.sources.map(_buildSourceCard)),
        ],
      ],
    );
  }

  /// Individual source memory card
  Widget _buildSourceCard(SourceMemory source) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: const Color(0xFF1A1A2E).withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: const Color(0xFF4FC3F7).withValues(alpha: 0.1),
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Relevance percentage badge
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: const Color(0xFF4FC3F7).withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                '${source.relevance}%',
                style: const TextStyle(
                  color: Color(0xFF4FC3F7),
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Date + subject label
                  Text(
                    '${source.eventDate ?? 'Unknown date'} · ${source.subject}',
                    style: TextStyle(
                      color: const Color(0xFFE8E8F0).withValues(alpha: 0.6),
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  // Memory summary
                  Text(
                    source.summary,
                    style: TextStyle(
                      color: const Color(0xFFE8E8F0).withValues(alpha: 0.8),
                      fontSize: 12,
                      height: 1.4,
                    ),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
