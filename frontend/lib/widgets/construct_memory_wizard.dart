/// BrainVault — Construct Memory Wizard Widget
///
/// A structured form allowing the user to manually compose a memory by:
/// - Selecting a date (Material 3 datepicker)
/// - Adding a location
/// - Selecting existing people (autocomplete chips) or adding new ones inline
/// - Writing the narrative description of the memory

import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../models/memory.dart';

class ConstructMemoryWizard extends StatefulWidget {
  const ConstructMemoryWizard({super.key});

  @override
  State<ConstructMemoryWizard> createState() => _ConstructMemoryWizardState();
}

class _ConstructMemoryWizardState extends State<ConstructMemoryWizard>
    with SingleTickerProviderStateMixin {
  final _descriptionController = TextEditingController();
  final _locationController = TextEditingController();
  
  DateTime _selectedDate = DateTime.now();
  bool _isLoading = false;
  bool _isFetchingPeople = false;

  // List of all people fetched from backend
  List<dynamic> _allPeople = [];

  // Selected people for the current memory
  final List<Map<String, dynamic>> _selectedPeople = [];

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

    _loadPeople();
  }

  @override
  void dispose() {
    _descriptionController.dispose();
    _locationController.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  /// Load people directory from the database
  Future<void> _loadPeople() async {
    setState(() => _isFetchingPeople = true);
    try {
      final list = await ApiService.getPeople();
      setState(() => _allPeople = list);
    } catch (_) {
      // Silently fail or fallback
    } finally {
      setState(() => _isFetchingPeople = false);
    }
  }

  /// Trigger Material 3 date picker
  Future<void> _selectDate(BuildContext context) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.dark(
              primary: Color(0xFF6C63FF),
              onPrimary: Colors.white,
              surface: Color(0xFF1A1A2E),
              onSurface: Color(0xFFE8E8F0),
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null && picked != _selectedDate) {
      setState(() {
        _selectedDate = picked;
      });
    }
  }

  /// Show dialog to add a new person profile inline
  void _showAddPersonDialog() {
    final nameCtrl = TextEditingController();
    final notesCtrl = TextEditingController();
    String selectedRelation = 'friend';
    bool dialogLoading = false;
    String? dialogError;

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: const Color(0xFF1A1A2E),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              title: const Text(
                'Add New Person',
                style: TextStyle(color: Color(0xFFE8E8F0), fontWeight: FontWeight.bold),
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: nameCtrl,
                      textCapitalization: TextCapitalization.words,
                      style: const TextStyle(color: Color(0xFFE8E8F0)),
                      decoration: InputDecoration(
                        labelText: 'Name',
                        labelStyle: const TextStyle(color: Colors.white60),
                        enabledBorder: UnderlineInputBorder(
                          borderSide: BorderSide(color: const Color(0xFF6C63FF).withValues(alpha: 0.3)),
                        ),
                        focusedBorder: const UnderlineInputBorder(
                          borderSide: BorderSide(color: Color(0xFF6C63FF)),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<String>(
                      initialValue: selectedRelation,
                      dropdownColor: const Color(0xFF1A1A2E),
                      style: const TextStyle(color: Color(0xFFE8E8F0)),
                      decoration: const InputDecoration(
                        labelText: 'Relationship',
                        labelStyle: TextStyle(color: Colors.white60),
                      ),
                      items: const [
                        DropdownMenuItem(value: 'friend', child: Text('Friend')),
                        DropdownMenuItem(value: 'close friend', child: Text('Close Friend')),
                        DropdownMenuItem(value: 'best friend', child: Text('Best Friend')),
                        DropdownMenuItem(value: 'family', child: Text('Family')),
                        DropdownMenuItem(value: 'colleague', child: Text('Colleague')),
                        DropdownMenuItem(value: 'enemy', child: Text('Enemy')),
                        DropdownMenuItem(value: 'other', child: Text('Other')),
                      ],
                      onChanged: (val) {
                        if (val != null) {
                          setDialogState(() => selectedRelation = val);
                        }
                      },
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: notesCtrl,
                      maxLines: 2,
                      textCapitalization: TextCapitalization.sentences,
                      style: const TextStyle(color: Color(0xFFE8E8F0)),
                      decoration: InputDecoration(
                        labelText: 'Facts/Notes',
                        labelStyle: const TextStyle(color: Colors.white60),
                        enabledBorder: UnderlineInputBorder(
                          borderSide: BorderSide(color: const Color(0xFF6C63FF).withValues(alpha: 0.3)),
                        ),
                        focusedBorder: const UnderlineInputBorder(
                          borderSide: BorderSide(color: Color(0xFF6C63FF)),
                        ),
                      ),
                    ),
                    if (dialogError != null) ...[
                      const SizedBox(height: 12),
                      Text(
                        dialogError!,
                        style: const TextStyle(color: Color(0xFFCF6679), fontSize: 13),
                      ),
                    ],
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: dialogLoading ? null : () => Navigator.pop(context),
                  child: const Text('Cancel', style: TextStyle(color: Colors.white54)),
                ),
                ElevatedButton(
                  onPressed: dialogLoading
                      ? null
                      : () async {
                          final name = nameCtrl.text.trim();
                          if (name.isEmpty) {
                            setDialogState(() => dialogError = 'Name is required.');
                            return;
                          }
                          setDialogState(() {
                            dialogLoading = true;
                            dialogError = null;
                          });

                          try {
                            final person = await ApiService.addPerson(
                              name,
                              selectedRelation,
                              notesCtrl.text.trim(),
                            );
                            await _loadPeople(); // refresh local list
                            setState(() {
                              _selectedPeople.add(person);
                            });
                            if (context.mounted) {
                              Navigator.pop(context);
                            }
                          } catch (e) {
                            setDialogState(() {
                              dialogLoading = false;
                              dialogError = e.toString().replaceFirst('Exception: ', '');
                            });
                          }
                        },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF6C63FF),
                    foregroundColor: Colors.white,
                  ),
                  child: dialogLoading
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Text('Add'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  /// Submit the constructed memory payload to backend
  Future<void> _saveMemory() async {
    final description = _descriptionController.text.trim();
    if (description.isEmpty) {
      _showSnackBar('❌ Please fill in the description.', isError: true);
      return;
    }

    setState(() => _isLoading = true);
    _pulseController.repeat(reverse: true);

    final payload = {
      'description': description,
      'location': _locationController.text.trim(),
      'event_date': _selectedDate.toIso8601String().split('T')[0],
      'people_ids': _selectedPeople.map((p) => p['id'] as String).toList(),
      'new_people': [], // new people are added inline, so they are already in DB
    };

    try {
      final memory = await ApiService.addConstructedMemory(payload);
      _onSaveComplete(memory);
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      _pulseController.stop();
      _pulseController.reset();
      _showSnackBar('❌ ${e.toString()}', isError: true);
    }
  }

  void _onSaveComplete(Memory memory) {
    if (!mounted) return;
    _descriptionController.clear();
    _locationController.clear();
    setState(() {
      _selectedPeople.clear();
      _selectedDate = DateTime.now();
      _isLoading = false;
    });
    _pulseController.stop();
    _pulseController.reset();
    _showSnackBar('✅ Memory constructed successfully!', isError: false);
  }

  void _showSnackBar(String message, {required bool isError}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: const TextStyle(fontWeight: FontWeight.w500)),
        backgroundColor: isError ? const Color(0xFFCF6679) : const Color(0xFF4CAF93),
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
          // Header
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFF6C63FF).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.architecture_rounded, color: Color(0xFF6C63FF), size: 20),
              ),
              const SizedBox(width: 12),
              const Text(
                'Construct Memory',
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

          // Date & Location Row
          Row(
            children: [
              // Date Button
              Expanded(
                child: InkWell(
                  onTap: _isLoading ? null : () => _selectDate(context),
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0F0F1A).withValues(alpha: 0.6),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.calendar_today_rounded, color: Color(0xFF6C63FF), size: 16),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            '${_selectedDate.day}/${_selectedDate.month}/${_selectedDate.year}',
                            style: const TextStyle(color: Color(0xFFE8E8F0), fontSize: 13),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              // Location Textfield
              Expanded(
                child: TextField(
                  controller: _locationController,
                  enabled: !_isLoading,
                  textCapitalization: TextCapitalization.words,
                  style: const TextStyle(color: Color(0xFFE8E8F0), fontSize: 13),
                  decoration: InputDecoration(
                    prefixIcon: const Icon(Icons.location_on_rounded, color: Color(0xFF6C63FF), size: 16),
                    filled: true,
                    fillColor: const Color(0xFF0F0F1A).withValues(alpha: 0.6),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // People selector autocomplete
          Row(
            children: [
              const Text(
                'People Involved',
                style: TextStyle(color: Color(0xFFE8E8F0), fontSize: 13, fontWeight: FontWeight.w600),
              ),
              const Spacer(),
              if (_isFetchingPeople)
                const SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 1.5))
              else
                IconButton(
                  onPressed: _isLoading ? null : _showAddPersonDialog,
                  icon: const Icon(Icons.person_add_alt_1_rounded, color: Color(0xFF4FC3F7), size: 18),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  tooltip: 'Create New Person Profile',
                ),
            ],
          ),
          const SizedBox(height: 6),

          // Autocomplete tag input field
          Autocomplete<Map<String, dynamic>>(
            optionsBuilder: (textEditingValue) {
              if (textEditingValue.text.isEmpty) {
                return const Iterable<Map<String, dynamic>>.empty();
              }
              return _allPeople.where((person) {
                final name = (person['name'] as String).toLowerCase();
                final query = textEditingValue.text.toLowerCase();
                final isAlreadySelected = _selectedPeople.any((p) => p['id'] == person['id']);
                return name.contains(query) && !isAlreadySelected;
              }).map((e) => Map<String, dynamic>.from(e));
            },
            displayStringForOption: (option) => option['name'] as String,
            onSelected: (selection) {
              setState(() {
                _selectedPeople.add(selection);
              });
            },
            fieldViewBuilder: (context, controller, focusNode, onEditingComplete) {
              return TextField(
                controller: controller,
                focusNode: focusNode,
                enabled: !_isLoading,
                style: const TextStyle(color: Color(0xFFE8E8F0), fontSize: 13),
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.search_rounded, size: 18),
                  filled: true,
                  fillColor: const Color(0xFF0F0F1A).withValues(alpha: 0.6),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                  contentPadding: const EdgeInsets.symmetric(vertical: 8),
                ),
              );
            },
            optionsViewBuilder: (context, onSelected, options) {
              return Align(
                alignment: Alignment.topLeft,
                child: Material(
                  color: const Color(0xFF1A1A2E),
                  borderRadius: BorderRadius.circular(12),
                  elevation: 8,
                  child: Container(
                    width: MediaQuery.of(context).size.width - 72,
                    constraints: const BoxConstraints(maxHeight: 200),
                    child: ListView.builder(
                      shrinkWrap: true,
                      padding: EdgeInsets.zero,
                      itemCount: options.length,
                      itemBuilder: (context, index) {
                        final option = options.elementAt(index);
                        return ListTile(
                          title: Text(option['name'], style: const TextStyle(color: Color(0xFFE8E8F0), fontSize: 13)),
                          subtitle: Text(option['relation'], style: TextStyle(color: const Color(0xFFE8E8F0).withValues(alpha: 0.4), fontSize: 11)),
                          onTap: () => onSelected(option),
                        );
                      },
                    ),
                  ),
                ),
              );
            },
          ),

          // Display selected chips
          if (_selectedPeople.isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _selectedPeople.map((person) {
                return InputChip(
                  label: Text('${person['name']} (${person['relation']})'),
                  labelStyle: const TextStyle(fontSize: 11, color: Color(0xFFE8E8F0)),
                  backgroundColor: const Color(0xFF6C63FF).withValues(alpha: 0.15),
                  deleteIconColor: const Color(0xFFFF4C6A),
                  onDeleted: () {
                    setState(() {
                      _selectedPeople.remove(person);
                    });
                  },
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  side: BorderSide(color: const Color(0xFF6C63FF).withValues(alpha: 0.3)),
                );
              }).toList(),
            ),
          ],
          const SizedBox(height: 14),

          // Description input
          const Text(
            'What happened?',
            style: TextStyle(color: Color(0xFFE8E8F0), fontSize: 13, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 6),
          TextField(
            controller: _descriptionController,
            maxLines: 3,
            minLines: 2,
            enabled: !_isLoading,
            textCapitalization: TextCapitalization.sentences,
            style: const TextStyle(color: Color(0xFFE8E8F0), fontSize: 13, height: 1.4),
            decoration: InputDecoration(
              filled: true,
              fillColor: const Color(0xFF0F0F1A).withValues(alpha: 0.6),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Color(0xFF6C63FF), width: 1.5),
              ),
              contentPadding: const EdgeInsets.all(12),
            ),
          ),
          const SizedBox(height: 14),

          // Save Button
          SizedBox(
            width: double.infinity,
            height: 44,
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
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.architecture_rounded, size: 18),
                label: Text(
                  _isLoading ? 'Constructing...' : 'Construct Memory',
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, letterSpacing: 0.5),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF6C63FF),
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: const Color(0xFF6C63FF).withValues(alpha: 0.6),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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
