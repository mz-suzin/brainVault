/// BrainVault — Home Screen
///
/// Single-activity layout with three vertically stacked sections:
/// 1. Memory Input (text entry)
/// 2. Audio Recorder (voice memo)
/// 3. Query Panel (search + results terminal)

import 'package:flutter/material.dart';
import '../widgets/memory_input.dart';
import '../widgets/audio_recorder.dart';
import '../widgets/construct_memory_wizard.dart';
import '../widgets/disambiguation_dialog.dart';
import '../widgets/query_panel.dart';
import '../services/api_service.dart';

/// Represents the current reachability state of the backend.
enum BackendStatus { checking, online, offline }

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with TickerProviderStateMixin {
  // Active input panel mode: 'type' | 'record' | 'construct'
  String _activeInputMode = 'type';

  // Backend connectivity status for the status indicator dot
  BackendStatus _backendStatus = BackendStatus.checking;

  // Pulse animation controller for the "checking" state
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;
  @override
  void initState() {
    super.initState();

    // Set up the pulse animation for the "checking" state
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);

    _pulseAnimation = Tween<double>(begin: 0.4, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    // Kick off health check — result updates the dot color
    _checkBackendStatus();
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  /// Calls the health endpoint and updates [_backendStatus].
  Future<void> _checkBackendStatus() async {
    final isOnline = await ApiService.checkHealth();
    if (!mounted) return;
    setState(() {
      _backendStatus = isOnline ? BackendStatus.online : BackendStatus.offline;
    });
    if (isOnline) _pulseController.stop();
  }

  /// Builds the animated status dot shown in the app header.
  Widget _buildStatusDot() {
    Color dotColor;
    String tooltip;

    switch (_backendStatus) {
      case BackendStatus.checking:
        dotColor = const Color(0xFFFFB74D); // amber while checking
        tooltip = 'Connecting to server…';
        break;
      case BackendStatus.online:
        dotColor = const Color(0xFF4CAF93); // green when online
        tooltip = 'Server online';
        break;
      case BackendStatus.offline:
        dotColor = const Color(0xFFCF6679); // red when offline
        tooltip = 'Server offline';
        break;
    }

    final dot = Container(
      width: 10,
      height: 10,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: dotColor,
        boxShadow: [
          BoxShadow(
            color: dotColor.withValues(alpha: 0.6),
            blurRadius: 6,
            spreadRadius: 1,
          ),
        ],
      ),
    );

    return Tooltip(
      message: tooltip,
      child: _backendStatus == BackendStatus.checking
          ? AnimatedBuilder(
              animation: _pulseAnimation,
              builder: (_, __) => Opacity(
                opacity: _pulseAnimation.value,
                child: dot,
              ),
            )
          : dot,
    );
  }

  /// Open bottom sheet dialog when duplicate names require manual selection

  void _showDisambiguationSheet(
    List<dynamic> conflicts,
    Map<String, dynamic> tempPayload,
  ) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: DisambiguationDialog(
          conflicts: conflicts,
          tempPayload: tempPayload,
          onResolved: (memory) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  '✅  Memory saved! (${memory.subject})',
                  style: const TextStyle(fontWeight: FontWeight.w500),
                ),
                backgroundColor: const Color(0xFF4CAF93),
                behavior: SnackBarBehavior.floating,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                margin: const EdgeInsets.all(16),
              ),
            );
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0F),
      body: SafeArea(
        child: CustomScrollView(
          physics: const BouncingScrollPhysics(),
          slivers: [
            // ── App Header ───────────────────────────────────────────
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 24, 24, 8),
                child: Row(
                  children: [
                    // Brain icon with gradient background
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(14),
                        gradient: const LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            Color(0xFF6C63FF),
                            Color(0xFF4FC3F7),
                          ],
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF6C63FF)
                                .withValues(alpha: 0.3),
                            blurRadius: 12,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: const Center(
                        child: Text('🧠', style: TextStyle(fontSize: 22)),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'BrainVault',
                          style: TextStyle(
                            color: Color(0xFFE8E8F0),
                            fontSize: 22,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -0.5,
                          ),
                        ),
                        Text(
                          'Your external memory',
                          style: TextStyle(
                            color: const Color(0xFFE8E8F0)
                                .withValues(alpha: 0.4),
                            fontSize: 13,
                            fontWeight: FontWeight.w400,
                          ),
                        ),
                      ],
                    ),
                    const Spacer(),
                    _buildStatusDot(),
                  ],

                ),
              ),
            ),

            // ── Input Mode Selector Bar ──────────────────────────────
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 12, 24, 6),
                child: Container(
                  height: 48,
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1A1A2E).withValues(alpha: 0.7),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: const Color(0xFF6C63FF).withValues(alpha: 0.1),
                    ),
                  ),
                  child: Row(
                    children: [
                      _buildToggleButton('type', 'Type', Icons.edit_note_rounded),
                      _buildToggleButton('record', 'Record', Icons.mic_rounded),
                      _buildToggleButton('construct', 'Construct', Icons.architecture_rounded),
                    ],
                  ),
                ),
              ),
            ),

            // ── Gradient divider ─────────────────────────────────────
            SliverToBoxAdapter(
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                child: Container(
                  height: 1,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        const Color(0xFF6C63FF).withValues(alpha: 0),
                        const Color(0xFF6C63FF).withValues(alpha: 0.3),
                        const Color(0xFF4FC3F7).withValues(alpha: 0.3),
                        const Color(0xFF4FC3F7).withValues(alpha: 0),
                      ],
                    ),
                  ),
                ),
              ),
            ),

            // ── Active Input Panel ───────────────────────────────────
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 300),
                  transitionBuilder: (Widget child, Animation<double> animation) {
                    return FadeTransition(
                      opacity: animation,
                      child: SlideTransition(
                        position: Tween<Offset>(
                          begin: const Offset(0.0, 0.05),
                          end: Offset.zero,
                        ).animate(animation),
                        child: child,
                      ),
                    );
                  },
                  child: _buildActiveInputWidget(),
                ),
              ),
            ),

            // ── Query Panel ──────────────────────────────────────────
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.fromLTRB(16, 10, 16, 32),
                child: QueryPanel(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Create a toggle button for the Input Mode Selector Bar
  Widget _buildToggleButton(String mode, String label, IconData icon) {
    final isSelected = _activeInputMode == mode;
    return Expanded(
      child: GestureDetector(
        onTap: () {
          setState(() {
            _activeInputMode = mode;
          });
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            gradient: isSelected
                ? const LinearGradient(
                    colors: [Color(0xFF6C63FF), Color(0xFF5A52E0)],
                  )
                : null,
          ),
          child: Center(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  icon,
                  size: 16,
                  color: isSelected
                      ? Colors.white
                      : const Color(0xFFE8E8F0).withValues(alpha: 0.4),
                ),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                    color: isSelected
                      ? Colors.white
                      : const Color(0xFFE8E8F0).withValues(alpha: 0.4),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Return the widget corresponding to the selected mode
  Widget _buildActiveInputWidget() {
    switch (_activeInputMode) {
      case 'type':
        return MemoryInput(
          key: const ValueKey('type'),
          onDisambiguationRequired: _showDisambiguationSheet,
        );
      case 'record':
        return AudioRecorderWidget(
          key: const ValueKey('record'),
          onDisambiguationRequired: _showDisambiguationSheet,
        );
      case 'construct':
        return const ConstructMemoryWizard(
          key: ValueKey('construct'),
        );
      default:
        return const SizedBox.shrink();
    }
  }
}
