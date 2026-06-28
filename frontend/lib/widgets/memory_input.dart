/// BrainVault — Memory Input Widget
///
/// A text area with a "Save Memory" button for typed memory entries.
/// Shows loading state during backend roundtrip and success/error feedback.

import 'package:flutter/material.dart';
import '../services/api_service.dart';

class MemoryInput extends StatefulWidget {
  const MemoryInput({super.key});

  @override
  State<MemoryInput> createState() => _MemoryInputState();
}

class _MemoryInputState extends State<MemoryInput>
    with SingleTickerProviderStateMixin {
  final _controller = TextEditingController();
  bool _isLoading = false;

  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    );
    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.04).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  Future<void> _saveMemory() async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;

    setState(() => _isLoading = true);
    _pulseController.repeat(reverse: true);

    try {
      final memory = await ApiService.addTextMemory(text);
      if (!mounted) return;

      _controller.clear();
      _showSnackBar(
        '✅  Memory saved! (${memory.subject})',
        isError: false,
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      _showSnackBar('❌  ${e.message}', isError: true);
    } catch (e) {
      if (!mounted) return;
      _showSnackBar(
          '❌  Something went wrong. Please try again.', isError: true);
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
        _pulseController.stop();
        _pulseController.reset();
      }
    }
  }

  void _showSnackBar(String message, {required bool isError}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: const TextStyle(fontWeight: FontWeight.w500),
        ),
        backgroundColor:
            isError ? const Color(0xFFCF6679) : const Color(0xFF4CAF93),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(16),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A2E).withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: const Color(0xFF6C63FF).withValues(alpha: 0.2),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF6C63FF).withValues(alpha: 0.05),
            blurRadius: 20,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Section header
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFF6C63FF).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.edit_note_rounded,
                  color: Color(0xFF6C63FF),
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              const Text(
                'New Memory',
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

          // Text input area
          TextField(
            controller: _controller,
            maxLines: 4,
            minLines: 3,
            enabled: !_isLoading,
            style: const TextStyle(
              color: Color(0xFFE8E8F0),
              fontSize: 15,
              height: 1.5,
            ),
            decoration: InputDecoration(
              hintText: 'What happened today? Tell your brain...',
              hintStyle: TextStyle(
                color: const Color(0xFFE8E8F0).withValues(alpha: 0.3),
                fontSize: 15,
              ),
              filled: true,
              fillColor: const Color(0xFF0F0F1A).withValues(alpha: 0.6),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide.none,
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(
                  color: Color(0xFF6C63FF),
                  width: 1.5,
                ),
              ),
              contentPadding: const EdgeInsets.all(16),
            ),
          ),
          const SizedBox(height: 14),

          // Save button with pulse animation during loading
          SizedBox(
            width: double.infinity,
            height: 48,
            child: AnimatedBuilder(
              animation: _pulseAnimation,
              builder: (context, child) {
                return Transform.scale(
                  scale: _isLoading ? _pulseAnimation.value : 1.0,
                  child: child,
                );
              },
              child: ElevatedButton.icon(
                onPressed: _isLoading ? null : _saveMemory,
                icon: _isLoading
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.save_rounded, size: 20),
                label: Text(
                  _isLoading ? 'Saving...' : 'Save Memory',
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.5,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF6C63FF),
                  foregroundColor: Colors.white,
                  disabledBackgroundColor:
                      const Color(0xFF6C63FF).withValues(alpha: 0.6),
                  disabledForegroundColor: Colors.white70,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  elevation: 0,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
