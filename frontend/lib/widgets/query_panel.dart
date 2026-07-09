/// BrainVault — Query Panel Widget
///
/// A search bar for asking natural language questions about stored memories.
/// Displays the LLM-synthesized answer and expandable source memory cards
/// with relevance scores, creation dates, and raw/digested text toggle.

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
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
      
      _controller.clear();
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

  /// Successful query result with answer and source memory cards
  Widget _buildResult() {
    if (_result == null) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // LLM-synthesized organic answer
        Text(
          _result!.answer,
          style: const TextStyle(
            color: Color(0xFFE8E8F0),
            fontSize: 14,
            height: 1.6,
          ),
        ),

        // Source memory cards
        if (_result!.sources.isNotEmpty) ...[
          const SizedBox(height: 20),

          // Section divider
          Container(
            height: 1,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  const Color(0xFF4FC3F7).withValues(alpha: 0),
                  const Color(0xFF4FC3F7).withValues(alpha: 0.2),
                  const Color(0xFF6C63FF).withValues(alpha: 0.2),
                  const Color(0xFF6C63FF).withValues(alpha: 0),
                ],
              ),
            ),
          ),

          const SizedBox(height: 14),

          // Sources header
          Row(
            children: [
              Icon(
                Icons.hub_rounded,
                size: 14,
                color: const Color(0xFFE8E8F0).withValues(alpha: 0.4),
              ),
              const SizedBox(width: 6),
              Text(
                'Source Memories',
                style: TextStyle(
                  color: const Color(0xFFE8E8F0).withValues(alpha: 0.5),
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFF6C63FF).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  '${_result!.sources.length}',
                  style: TextStyle(
                    color: const Color(0xFF6C63FF).withValues(alpha: 0.8),
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 10),

          // Source cards list
          ...List.generate(
            _result!.sources.length,
            (i) => Padding(
              padding: EdgeInsets.only(
                bottom: i < _result!.sources.length - 1 ? 8 : 0,
              ),
              child: _SourceMemoryCard(source: _result!.sources[i]),
            ),
          ),
        ],
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Source Memory Card (Expandable)
// ─────────────────────────────────────────────────────────────────────────────

class _SourceMemoryCard extends StatefulWidget {
  final SourceMemory source;

  const _SourceMemoryCard({required this.source});

  @override
  State<_SourceMemoryCard> createState() => _SourceMemoryCardState();
}

class _SourceMemoryCardState extends State<_SourceMemoryCard>
    with SingleTickerProviderStateMixin {
  bool _isExpanded = false;
  bool _showRaw = false; // false = digested (summary), true = raw text

  late AnimationController _chevronController;
  late Animation<double> _chevronRotation;

  @override
  void initState() {
    super.initState();
    _chevronController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
    );
    _chevronRotation = Tween<double>(begin: 0.0, end: 0.5).animate(
      CurvedAnimation(parent: _chevronController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _chevronController.dispose();
    super.dispose();
  }

  void _toggleExpanded() {
    setState(() => _isExpanded = !_isExpanded);
    if (_isExpanded) {
      _chevronController.forward();
    } else {
      _chevronController.reverse();
    }
  }

  /// Get a subject-appropriate icon
  IconData _subjectIcon(String subject) {
    switch (subject.toLowerCase()) {
      case 'work':
        return Icons.work_rounded;
      case 'health':
        return Icons.favorite_rounded;
      case 'travel':
        return Icons.flight_rounded;
      case 'finance':
        return Icons.account_balance_wallet_rounded;
      case 'education':
        return Icons.school_rounded;
      case 'family':
        return Icons.family_restroom_rounded;
      case 'social':
        return Icons.people_rounded;
      case 'food':
        return Icons.restaurant_rounded;
      case 'entertainment':
        return Icons.movie_rounded;
      case 'sports':
        return Icons.sports_soccer_rounded;
      case 'shopping':
        return Icons.shopping_bag_rounded;
      case 'personal':
        return Icons.person_rounded;
      default:
        return Icons.memory_rounded;
    }
  }

  /// Get a relevance-based color
  Color _relevanceColor(int relevance) {
    if (relevance >= 70) return const Color(0xFF4CAF93);
    if (relevance >= 40) return const Color(0xFFFFB74D);
    return const Color(0xFFCF6679);
  }

  /// Format the creation date nicely (e.g., "June 8, 2026")
  String _formatDate(DateTime? date) {
    if (date == null) return '';
    return DateFormat('MMMM d, y').format(date.toLocal());
  }

  /// Format an event_date string (YYYY-MM-DD) as "June 8, 2026"
  String _formatEventDate(String? dateStr) {
    if (dateStr == null || dateStr.isEmpty) return '';
    final parsed = DateTime.tryParse(dateStr);
    if (parsed == null) return dateStr;
    return DateFormat('MMMM d, y').format(parsed);
  }

  @override
  Widget build(BuildContext context) {
    final source = widget.source;
    final relColor = _relevanceColor(source.relevance);

    return GestureDetector(
      onTap: _toggleExpanded,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeInOut,
        decoration: BoxDecoration(
          color: _isExpanded
              ? const Color(0xFF141425)
              : const Color(0xFF111120),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: _isExpanded
                ? const Color(0xFF6C63FF).withValues(alpha: 0.3)
                : const Color(0xFF4FC3F7).withValues(alpha: 0.08),
            width: 1,
          ),
          boxShadow: _isExpanded
              ? [
                  BoxShadow(
                    color: const Color(0xFF6C63FF).withValues(alpha: 0.08),
                    blurRadius: 12,
                    offset: const Offset(0, 2),
                  ),
                ]
              : [],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Collapsed header (always visible) ────────────────────
            Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Subject icon
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: const Color(0xFF6C63FF).withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      _subjectIcon(source.subject),
                      size: 16,
                      color: const Color(0xFF6C63FF).withValues(alpha: 0.7),
                    ),
                  ),
                  const SizedBox(width: 10),

                  // Summary preview + date
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          source.summary,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: const Color(0xFFE8E8F0)
                                .withValues(alpha: 0.75),
                            fontSize: 12.5,
                            height: 1.5,
                          ),
                        ),
                        if (source.createdAt != null) ...[
                          const SizedBox(height: 4),
                          Text(
                            _formatDate(source.createdAt),
                            style: TextStyle(
                              color: const Color(0xFFE8E8F0)
                                  .withValues(alpha: 0.3),
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),

                  // Relevance badge + chevron
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      // Relevance badge
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 7, vertical: 3),
                        decoration: BoxDecoration(
                          color: relColor.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: relColor.withValues(alpha: 0.3),
                            width: 0.5,
                          ),
                        ),
                        child: Text(
                          '${source.relevance}%',
                          style: TextStyle(
                            color: relColor,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      const SizedBox(height: 6),
                      // Expand chevron
                      RotationTransition(
                        turns: _chevronRotation,
                        child: Icon(
                          Icons.keyboard_arrow_down_rounded,
                          size: 18,
                          color: const Color(0xFFE8E8F0)
                              .withValues(alpha: 0.3),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            // ── Expanded content ─────────────────────────────────────
            AnimatedSize(
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeInOut,
              child: _isExpanded
                  ? _buildExpandedContent(source)
                  : const SizedBox.shrink(),
            ),
          ],
        ),
      ),
    );
  }

  /// Expanded card content with raw/digested toggle and tags
  Widget _buildExpandedContent(SourceMemory source) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Divider
        Container(
          height: 1,
          margin: const EdgeInsets.symmetric(horizontal: 12),
          color: const Color(0xFFE8E8F0).withValues(alpha: 0.06),
        ),

        Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Raw / Digested toggle ──────────────────────────────
              Row(
                children: [
                  _buildViewToggle(
                    label: 'Digested',
                    icon: Icons.auto_awesome_rounded,
                    isActive: !_showRaw,
                    onTap: () => setState(() => _showRaw = false),
                  ),
                  const SizedBox(width: 6),
                  _buildViewToggle(
                    label: 'Raw',
                    icon: Icons.text_snippet_rounded,
                    isActive: _showRaw,
                    onTap: () => setState(() => _showRaw = true),
                  ),
                ],
              ),

              const SizedBox(height: 10),

              // ── Memory text content ────────────────────────────────
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                child: Container(
                  key: ValueKey(_showRaw ? 'raw' : 'digested'),
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0A0A14).withValues(alpha: 0.6),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: const Color(0xFFE8E8F0).withValues(alpha: 0.04),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Label
                      Text(
                        _showRaw ? 'Original Input' : 'AI-Processed',
                        style: TextStyle(
                          color: _showRaw
                              ? const Color(0xFFFFB74D).withValues(alpha: 0.6)
                              : const Color(0xFF4FC3F7).withValues(alpha: 0.6),
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.5,
                        ),
                      ),
                      const SizedBox(height: 6),
                      // Text
                      Text(
                        _showRaw ? source.rawText : source.summary,
                        style: TextStyle(
                          color: const Color(0xFFE8E8F0)
                              .withValues(alpha: 0.8),
                          fontSize: 12.5,
                          height: 1.6,
                          fontStyle:
                              _showRaw ? FontStyle.italic : FontStyle.normal,
                        ),
                      ),
                    ],
                  ),
                ),
              ),



              // ── Metadata row ───────────────────────────────────────
              const SizedBox(height: 10),
              Row(
                children: [
                  // Subject chip
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 7, vertical: 3),
                    decoration: BoxDecoration(
                      color: const Color(0xFF6C63FF).withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          _subjectIcon(source.subject),
                          size: 10,
                          color: const Color(0xFF6C63FF)
                              .withValues(alpha: 0.7),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          source.subject,
                          style: TextStyle(
                            color: const Color(0xFF6C63FF)
                                .withValues(alpha: 0.7),
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),

                  const Spacer(),

                  // Event date if available
                  if (source.eventDate != null)
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.event_rounded,
                          size: 11,
                          color: const Color(0xFFE8E8F0)
                              .withValues(alpha: 0.3),
                        ),
                        const SizedBox(width: 3),
                        Text(
                          _formatEventDate(source.eventDate),
                          style: TextStyle(
                            color: const Color(0xFFE8E8F0)
                                .withValues(alpha: 0.3),
                            fontSize: 10,
                          ),
                        ),
                      ],
                    ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// Small toggle pill button for the Raw/Digested switch
  Widget _buildViewToggle({
    required String label,
    required IconData icon,
    required bool isActive,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
        decoration: BoxDecoration(
          color: isActive
              ? const Color(0xFF6C63FF).withValues(alpha: 0.2)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isActive
                ? const Color(0xFF6C63FF).withValues(alpha: 0.4)
                : const Color(0xFFE8E8F0).withValues(alpha: 0.1),
            width: 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 12,
              color: isActive
                  ? const Color(0xFF6C63FF)
                  : const Color(0xFFE8E8F0).withValues(alpha: 0.3),
            ),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                color: isActive
                    ? const Color(0xFF6C63FF)
                    : const Color(0xFFE8E8F0).withValues(alpha: 0.3),
                fontSize: 11,
                fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
