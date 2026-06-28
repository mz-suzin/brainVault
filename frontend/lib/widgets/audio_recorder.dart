/// BrainVault — Audio Recorder Widget
///
/// A tactile microphone button that handles:
/// - Runtime RECORD_AUDIO permission via permission_handler
/// - Local audio recording (M4A/AAC via `record` package)
/// - Automatic upload on stop via multipart/form-data
/// - Pulsing + ripple animations during recording
/// - Loading state during upload + LLM processing

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:record/record.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import '../services/api_service.dart';

class AudioRecorderWidget extends StatefulWidget {
  const AudioRecorderWidget({super.key});

  @override
  State<AudioRecorderWidget> createState() => _AudioRecorderWidgetState();
}

class _AudioRecorderWidgetState extends State<AudioRecorderWidget>
    with TickerProviderStateMixin {
  final _recorder = AudioRecorder();

  bool _isRecording = false;
  bool _isUploading = false;
  Duration _recordingDuration = Duration.zero;
  Timer? _durationTimer;

  // Animations
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;
  late AnimationController _rippleController;
  late Animation<double> _rippleAnimation;

  @override
  void initState() {
    super.initState();

    // Pulsing glow for the mic button during recording
    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 1200),
      vsync: this,
    );
    _pulseAnimation = Tween<double>(begin: 0.9, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    // Expanding ripple ring around the mic button
    _rippleController = AnimationController(
      duration: const Duration(milliseconds: 2000),
      vsync: this,
    );
    _rippleAnimation = Tween<double>(begin: 1.0, end: 1.8).animate(
      CurvedAnimation(parent: _rippleController, curve: Curves.easeOut),
    );
  }

  @override
  void dispose() {
    _durationTimer?.cancel();
    _pulseController.dispose();
    _rippleController.dispose();
    _recorder.dispose();
    super.dispose();
  }

  /// Format duration as MM:SS
  String _formatDuration(Duration d) {
    final minutes = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  /// Handle microphone button tap: toggle recording on/off
  Future<void> _onMicPressed() async {
    if (_isUploading) return;

    if (_isRecording) {
      await _stopRecording();
    } else {
      await _startRecording();
    }
  }

  /// Request permission and begin recording audio
  Future<void> _startRecording() async {
    // Request microphone permission via permission_handler
    final status = await Permission.microphone.request();
    if (!status.isGranted) {
      if (!mounted) return;
      _showSnackBar('🎤 Microphone permission is required to record audio.');
      return;
    }

    // Verify recorder availability
    if (!await _recorder.hasPermission()) {
      if (!mounted) return;
      _showSnackBar('🎤 Unable to access the microphone.');
      return;
    }

    // Generate a unique temp file path for the recording
    final tempDir = await getTemporaryDirectory();
    final filePath =
        '${tempDir.path}/brainvault_${DateTime.now().millisecondsSinceEpoch}.m4a';

    // Start recording in M4A/AAC format (Android native, Gemini-compatible)
    await _recorder.start(
      const RecordConfig(
        encoder: AudioEncoder.aacLc,
        sampleRate: 44100,
        bitRate: 128000,
      ),
      path: filePath,
    );

    setState(() {
      _isRecording = true;
      _recordingDuration = Duration.zero;
    });

    // Start the duration counter (updates every second)
    _durationTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) {
        setState(() {
          _recordingDuration += const Duration(seconds: 1);
        });
      }
    });

    // Start visual animations
    _pulseController.repeat(reverse: true);
    _rippleController.repeat();
  }

  /// Stop recording and automatically upload the audio file
  Future<void> _stopRecording() async {
    // Stop animations & duration timer
    _durationTimer?.cancel();
    _pulseController.stop();
    _pulseController.reset();
    _rippleController.stop();
    _rippleController.reset();

    final path = await _recorder.stop();

    setState(() {
      _isRecording = false;
      _isUploading = true;
    });

    if (path == null) {
      setState(() => _isUploading = false);
      _showSnackBar('❌ Recording failed — no audio captured.');
      return;
    }

    // Upload the recorded audio to the backend
    try {
      final memory = await ApiService.addAudioMemory(path);
      if (!mounted) return;
      _showSnackBar('✅ Audio memory saved! (${memory.subject})',
          isError: false);
    } on ApiException catch (e) {
      if (!mounted) return;
      _showSnackBar('❌ ${e.message}');
    } catch (e) {
      if (!mounted) return;
      _showSnackBar('❌ Upload failed. Please try again.');
    } finally {
      if (mounted) {
        setState(() {
          _isUploading = false;
          _recordingDuration = Duration.zero;
        });
      }
    }
  }

  void _showSnackBar(String message, {bool isError = true}) {
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
    final accentColor =
        _isRecording ? const Color(0xFFFF4C6A) : const Color(0xFF6C63FF);

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 20),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A2E).withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: accentColor.withValues(alpha: 0.2),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: accentColor.withValues(alpha: 0.05),
            blurRadius: 20,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          // ── Section header ──────────────────────────────────────────
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: accentColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(Icons.mic_rounded, color: accentColor, size: 20),
              ),
              const SizedBox(width: 12),
              Text(
                _isRecording
                    ? 'Recording...'
                    : _isUploading
                        ? 'Processing audio...'
                        : 'Voice Memo',
                style: const TextStyle(
                  color: Color(0xFFE8E8F0),
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.3,
                ),
              ),
              const Spacer(),
              // Duration badge (visible during and after recording)
              if (_isRecording || _recordingDuration > Duration.zero)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFF4C6A).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    _formatDuration(_recordingDuration),
                    style: const TextStyle(
                      color: Color(0xFFFF4C6A),
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 24),

          // ── Microphone button with ripple animation ─────────────────
          Stack(
            alignment: Alignment.center,
            children: [
              // Expanding ripple ring (visible during recording)
              if (_isRecording)
                AnimatedBuilder(
                  animation: _rippleAnimation,
                  builder: (context, _) {
                    return Container(
                      width: 80 * _rippleAnimation.value,
                      height: 80 * _rippleAnimation.value,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: const Color(0xFFFF4C6A).withValues(
                            alpha: (1 -
                                    (_rippleAnimation.value - 1.0) / 0.8)
                                .clamp(0.0, 0.4),
                          ),
                          width: 2,
                        ),
                      ),
                    );
                  },
                ),

              // Main mic button with pulse
              AnimatedBuilder(
                animation: _pulseAnimation,
                builder: (context, child) {
                  return Transform.scale(
                    scale: _isRecording ? _pulseAnimation.value : 1.0,
                    child: child,
                  );
                },
                child: GestureDetector(
                  onTap: _onMicPressed,
                  child: Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: _isRecording
                            ? [
                                const Color(0xFFFF4C6A),
                                const Color(0xFFFF2D55),
                              ]
                            : _isUploading
                                ? [
                                    const Color(0xFF4A4A5A),
                                    const Color(0xFF3A3A4A),
                                  ]
                                : [
                                    const Color(0xFF6C63FF),
                                    const Color(0xFF5A52E0),
                                  ],
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: accentColor.withValues(alpha: 0.4),
                          blurRadius: 16,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: _isUploading
                        ? const Center(
                            child: SizedBox(
                              width: 28,
                              height: 28,
                              child: CircularProgressIndicator(
                                color: Colors.white,
                                strokeWidth: 2.5,
                              ),
                            ),
                          )
                        : Icon(
                            _isRecording
                                ? Icons.stop_rounded
                                : Icons.mic_rounded,
                            color: Colors.white,
                            size: 32,
                          ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Hint text
          Text(
            _isRecording
                ? 'Tap to stop recording'
                : _isUploading
                    ? 'Transcribing & extracting...'
                    : 'Tap to record a voice memo',
            style: TextStyle(
              color: const Color(0xFFE8E8F0).withValues(alpha: 0.4),
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }
}
