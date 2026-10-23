import 'dart:convert';
import 'package:flutter/material.dart';
import '../config/l10n.dart';
import '../services/incident_api.dart';
import 'calculator_disguise_screen.dart';

class EvidenceScreen extends StatefulWidget {
  const EvidenceScreen({super.key, this.userId = 'MOKGOSI_DEMO_USER'});

  final String userId;

  @override
  State<EvidenceScreen> createState() => _EvidenceScreenState();
}

class _EvidenceScreenState extends State<EvidenceScreen> {
  List<Map<String, dynamic>> _entries = [];
  bool _isLoading = true;
  bool _isScreenDimmed = false;
  final Set<String> _selectedEntryIds = {};
  final List<Map<String, dynamic>> _shareAuditLog = [];

  @override
  void initState() {
    super.initState();
    _loadEntries();
  }

  Future<void> _loadEntries() async {
    setState(() => _isLoading = true);
    final list = await IncidentApi.fetchEvidenceEntries(widget.userId);
    if (mounted) {
      setState(() {
        _entries = list;
        _isLoading = false;
      });
    }
  }

  void _quickExit() {
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute<void>(builder: (_) => const CalculatorDisguiseScreen()),
      (route) => false,
    );
  }

  Future<void> _captureNote() async {
    final noteController = TextEditingController();
    final shouldSave = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xff161b22),
        title: const Text('Add Documented Note', style: TextStyle(color: Colors.white, fontSize: 18)),
        content: TextField(
          key: const Key('note_input_field'),
          controller: noteController,
          maxLines: 4,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
            hintText: 'Record facts, dates, witnesses, or incidents...',
            hintStyle: TextStyle(color: Color(0xff718096)),
            enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: Color(0xff30363d))),
            focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: Color(0xff319795))),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(
            key: const Key('save_note_button'),
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xff319795)),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Save Note', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (shouldSave == true && noteController.text.trim().isNotEmpty) {
      final text = noteController.text.trim();
      final bytes = utf8.encode(text);
      await IncidentApi.storeEvidenceEntry(
        userId: widget.userId,
        kind: 'NOTE',
        notes: text,
        fileBytes: bytes,
        filename: 'note_${DateTime.now().millisecondsSinceEpoch}.txt',
      );
      await _loadEntries();
    }
  }

  Future<void> _captureAudio() async {
    // Silent capture: simulated 10-second consenting audio clip
    final bytes = utf8.encode('SURVIVOR_AUDIO_SAMPLE_${DateTime.now().toIso8601String()}');
    await IncidentApi.storeEvidenceEntry(
      userId: widget.userId,
      kind: 'AUDIO',
      notes: 'Ambient acoustic capture (10s)',
      fileBytes: bytes,
      filename: 'audio_${DateTime.now().millisecondsSinceEpoch}.wav',
    );
    await _loadEntries();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Audio clip captured silently and secured in local vault.'),
          backgroundColor: Color(0xff2b6cb0),
        ),
      );
    }
  }

  Future<void> _capturePhoto() async {
    // Silent capture: simulated camera capture without shutter sound or flash preview
    final bytes = utf8.encode('SURVIVOR_PHOTO_SAMPLE_${DateTime.now().toIso8601String()}');
    await IncidentApi.storeEvidenceEntry(
      userId: widget.userId,
      kind: 'PHOTO',
      notes: 'Documentary photograph captured silently',
      fileBytes: bytes,
      filename: 'photo_${DateTime.now().millisecondsSinceEpoch}.jpg',
    );
    await _loadEntries();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Photo captured silently and encrypted in vault.'),
          backgroundColor: Color(0xff2b6cb0),
        ),
      );
    }
  }

  Future<void> _deleteEntry(String entryId) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xff161b22),
        title: const Text('Delete Evidence Entry?', style: TextStyle(color: Color(0xfffc8181))),
        content: const Text(
          'This will remove the entry from your phone. You can also request removal of server-backed copies.',
          style: TextStyle(color: Color(0xffcbd5e0), fontSize: 13, height: 1.4),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(
            key: const Key('confirm_delete_entry'),
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xffe53e3e)),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete Entry', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await IncidentApi.deleteEvidenceEntry(entryId, hardDelete: true, userId: widget.userId);
      await _loadEntries();
    }
  }

  Future<void> _showShareBundleDialog() async {
    if (_selectedEntryIds.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Select at least one evidence entry to share.'), backgroundColor: Colors.amber),
      );
      return;
    }

    String recipientType = 'LEGAL';
    final notesController = TextEditingController();

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          backgroundColor: const Color(0xff161b22),
          title: Text(
            'Share Case Bundle (${_selectedEntryIds.length} items)',
            style: const TextStyle(color: Colors.white, fontSize: 18),
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'What leaves your phone: A cryptographically signed ZIP containing the selected evidence, SHA-256 manifests, and a verification script for legal admissibility.',
                  style: TextStyle(color: Color(0xffcbd5e0), fontSize: 12, height: 1.4),
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  initialValue: recipientType,
                  dropdownColor: const Color(0xff21262d),
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(labelText: 'Recipient Type', labelStyle: TextStyle(color: Color(0xffa0aec0))),
                  items: const [
                    DropdownMenuItem(value: 'LEGAL', child: Text('Legal Aid / Attorney')),
                    DropdownMenuItem(value: 'POLICE', child: Text('Police GBV Desk')),
                    DropdownMenuItem(value: 'COUNSELLOR', child: Text('Licensed Counsellor')),
                    DropdownMenuItem(value: 'OTHER', child: Text('Other Trusted Party')),
                  ],
                  onChanged: (val) {
                    if (val != null) setDialogState(() => recipientType = val);
                  },
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: notesController,
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(
                    labelText: 'Confidential Notes for Bundle (optional)',
                    labelStyle: TextStyle(color: Color(0xffa0aec0)),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            ElevatedButton(
              key: const Key('generate_bundle_button'),
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xff319795)),
              onPressed: () async {
                Navigator.pop(ctx);
                final res = await IncidentApi.shareEvidenceBundle(
                  userId: widget.userId,
                  entryIds: _selectedEntryIds.toList(),
                  recipientType: recipientType,
                  notes: notesController.text.trim().isNotEmpty ? notesController.text.trim() : null,
                );
                if (res != null && mounted) {
                  final now = DateTime.now().toLocal().toString().split('.')[0];
                  setState(() {
                    _shareAuditLog.add({
                      'date': now,
                      'recipient': recipientType,
                      'count': _selectedEntryIds.length,
                      'url': res['download_url'] ?? '',
                    });
                    _selectedEntryIds.clear();
                  });
                  _showBundleLinkModal(res['download_url'] ?? '', recipientType);
                }
              },
              child: const Text('Generate Bundle', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }

  void _showBundleLinkModal(String downloadUrl, String recipient) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xff161b22),
        title: const Text('Case Bundle Ready', style: TextStyle(color: Color(0xff4fd1c5))),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Sealed bundle prepared for $recipient.', style: const TextStyle(color: Colors.white)),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(10),
              color: const Color(0xff0d1117),
              child: SelectableText(
                '${IncidentApi.httpClient.toString().contains("Mock") ? "https://mokgosi.org" : "https://api.mokgosi.bw"}$downloadUrl',
                style: const TextStyle(color: Color(0xff81e6d9), fontSize: 12),
              ),
            ),
            const SizedBox(height: 10),
            const Text(
              'Link expires automatically in 2 hours. Access is recorded in your audit log.',
              style: TextStyle(color: Color(0xffa0aec0), fontSize: 11),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Done')),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isScreenDimmed) {
      return GestureDetector(
        onTap: () => setState(() => _isScreenDimmed = false),
        child: Container(
          color: Colors.black,
          alignment: Alignment.center,
          child: const Text('Screen Dimmed — Tap anywhere to restore', style: TextStyle(color: Colors.white24, fontSize: 12)),
        ),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xff0d1117),
      appBar: AppBar(
        backgroundColor: const Color(0xff161b22),
        title: Text(MokgosiL10n.get('evidence_vault'), style: const TextStyle(fontSize: 18)),
        actions: [
          IconButton(
            tooltip: 'Dim Screen (Stealth Mode)',
            icon: const Icon(Icons.brightness_2_outlined, color: Color(0xffcbd5e0)),
            onPressed: () => setState(() => _isScreenDimmed = true),
          ),
          IconButton(
            key: const Key('evidence_quick_exit'),
            tooltip: MokgosiL10n.get('quick_exit'),
            icon: const Icon(Icons.close_fullscreen, color: Color(0xfffc8181)),
            onPressed: _quickExit,
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Quick Capture Action Bar
            Container(
              padding: const EdgeInsets.all(14),
              color: const Color(0xff161b22),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Silent Evidence Capture (Survivor-Owned)',
                    style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          key: const Key('btn_record_audio'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xff2d3748),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 10),
                          ),
                          onPressed: _captureAudio,
                          icon: const Icon(Icons.mic, size: 18, color: Color(0xff4fd1c5)),
                          label: const Text('Record Audio', style: TextStyle(fontSize: 12)),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: ElevatedButton.icon(
                          key: const Key('btn_take_photo'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xff2d3748),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 10),
                          ),
                          onPressed: _capturePhoto,
                          icon: const Icon(Icons.camera_alt, size: 18, color: Color(0xff63b3ed)),
                          label: const Text('Take Photo', style: TextStyle(fontSize: 12)),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: ElevatedButton.icon(
                          key: const Key('btn_write_note'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xff2d3748),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 10),
                          ),
                          onPressed: _captureNote,
                          icon: const Icon(Icons.note_add, size: 18, color: Color(0xfff6ad55)),
                          label: const Text('Write Note', style: TextStyle(fontSize: 12)),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            // Multi-select Share Bar
            if (_selectedEntryIds.isNotEmpty)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                color: const Color(0xff234e52),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '${_selectedEntryIds.length} entries selected',
                      style: const TextStyle(color: Color(0xff81e6d9), fontWeight: FontWeight.bold),
                    ),
                    ElevatedButton.icon(
                      key: const Key('share_selected_button'),
                      style: ElevatedButton.styleFrom(backgroundColor: const Color(0xff319795)),
                      onPressed: _showShareBundleDialog,
                      icon: const Icon(Icons.share, size: 16, color: Colors.white),
                      label: const Text('Create Case Bundle', style: TextStyle(color: Colors.white, fontSize: 12)),
                    ),
                  ],
                ),
              ),
            // Timeline
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _entries.isEmpty
                      ? const Center(
                          child: Text(
                            'No evidence entries recorded yet.\nUse the quick buttons above to capture silent notes, audio, or photos.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Color(0xff718096), height: 1.5),
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.all(16),
                          itemCount: _entries.length,
                          itemBuilder: (ctx, idx) {
                            final entry = _entries[idx];
                            final id = entry['id']?.toString() ?? '';
                            final kind = entry['kind'] ?? 'NOTE';
                            final capturedUtc = entry['captured_at_utc'] ?? '';
                            final isSynced = entry['manifest_id'] != null || entry['is_synced'] == true;
                            final isSelected = _selectedEntryIds.contains(id);

                            return Card(
                              color: const Color(0xff161b22),
                              margin: const EdgeInsets.only(bottom: 10),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                                side: BorderSide(
                                  color: isSelected ? const Color(0xff319795) : const Color(0xff30363d),
                                  width: isSelected ? 2 : 1,
                                ),
                              ),
                              child: ListTile(
                                leading: Checkbox(
                                  value: isSelected,
                                  activeColor: const Color(0xff319795),
                                  onChanged: (val) {
                                    setState(() {
                                      if (val == true) {
                                        _selectedEntryIds.add(id);
                                      } else {
                                        _selectedEntryIds.remove(id);
                                      }
                                    });
                                  },
                                ),
                                title: Row(
                                  children: [
                                    Text(
                                      kind,
                                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                                    ),
                                    const SizedBox(width: 8),
                                    if (isSynced)
                                      const Row(
                                        children: [
                                          Icon(Icons.check_circle, color: Color(0xff48bb78), size: 14),
                                          SizedBox(width: 4),
                                          Text('Backed up & signed', style: TextStyle(color: Color(0xff48bb78), fontSize: 11)),
                                        ],
                                      )
                                    else
                                      const Row(
                                        children: [
                                          Icon(Icons.phone_android, color: Color(0xffcbd5e0), size: 14),
                                          SizedBox(width: 4),
                                          Text('Saved on this phone', style: TextStyle(color: Color(0xffa0aec0), fontSize: 11)),
                                        ],
                                      ),
                                  ],
                                ),
                                subtitle: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    if (entry['notes'] != null && entry['notes'].toString().isNotEmpty)
                                      Padding(
                                        padding: const EdgeInsets.only(top: 4),
                                        child: Text(
                                          entry['notes'].toString(),
                                          style: const TextStyle(color: Color(0xffcbd5e0), fontSize: 12),
                                        ),
                                      ),
                                    const SizedBox(height: 4),
                                    Text(
                                      capturedUtc.split('.')[0].replaceFirst('T', ' '),
                                      style: const TextStyle(color: Color(0xff718096), fontSize: 11),
                                    ),
                                  ],
                                ),
                                trailing: IconButton(
                                  icon: const Icon(Icons.delete_outline, color: Color(0xffe53e3e), size: 20),
                                  onPressed: () => _deleteEntry(id),
                                ),
                              ),
                            );
                          },
                        ),
            ),
            // Audit Log footer
            if (_shareAuditLog.isNotEmpty)
              Container(
                padding: const EdgeInsets.all(12),
                color: const Color(0xff161b22),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Case Bundle Sharing History', style: TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 6),
                    ..._shareAuditLog.map((log) => Text(
                          'Shared ${log['count']} items with ${log['recipient']} on ${log['date']}',
                          style: const TextStyle(color: Color(0xff81e6d9), fontSize: 11),
                        )),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
