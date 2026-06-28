/// BrainVault — Home Screen
///
/// Single-activity layout with three vertically stacked sections:
/// 1. Memory Input (text entry)
/// 2. Audio Recorder (voice memo)
/// 3. Query Panel (search + results terminal)

import 'package:flutter/material.dart';
import '../widgets/memory_input.dart';
import '../widgets/audio_recorder.dart';
import '../widgets/query_panel.dart';
import '../services/api_service.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  @override
  void initState() {
    super.initState();
    // Pre-warm the backend container on app launch (fire-and-forget).
    // This triggers the Render free-tier container to wake up before
    // the user finishes composing their first input.
    ApiService.prewarm();
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
                  ],
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

            // ── Section 1: Text Memory Input ─────────────────────────
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.fromLTRB(16, 8, 16, 10),
                child: MemoryInput(),
              ),
            ),

            // ── Section 2: Audio Recorder ────────────────────────────
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                child: AudioRecorderWidget(),
              ),
            ),

            // ── Section 3: Query Panel ───────────────────────────────
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
}
