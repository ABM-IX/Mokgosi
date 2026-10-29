import 'dart:convert';
import 'package:flutter/material.dart';
import '../config/l10n.dart';
import '../config/mokgosi_config.dart';
import '../config/theme.dart';
import '../services/incident_api.dart';
import '../widgets/common.dart';
import 'calculator_disguise_screen.dart';

const _kindLabels = <String, String>{'NOTE': 'Note', 'AUDIO': 'Recording', 'PHOTO': 'Photo'};
const _recipientLabels = <String, String>{
  'LEGAL': 'Lawyer or legal aid',
  'POLICE': 'Police',
  'COUNSELLOR': 'Counsellor',
  'OTHER': 'Someone else',
};

/// The private journal: notes the person writes, kept on the phone, signed when backed up, and
/// shared only as a link they create for someone they choose.
class EvidenceScreen extends StatefulWidget {
  const EvidenceScreen({
    super.key,
    this.userId = 'MOKGOSI_DEMO_USER',
    this.allowSampleCaptures = MokgosiConfig.demoMode,
  });

  final String userId;

  /// Audio and photo capture are not built yet. In demo builds these buttons add clearly
  /// labelled placeholder entries; real builds hide them rather than pretend to record.
  final bool allowSampleCaptures;

  @override
  State<EvidenceScreen> createState() => _EvidenceScreenState();
}

class _EvidenceScreenState extends State<EvidenceScreen> {
  List<Map<String, dynamic>> _entries = [];
  bool _isLoading = true;
  bool _isScreenDimmed = false;
  final Set<String> _selectedEntryIds = {};
  final List<Map<String, dynamic>> _shareHistory = [];

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
        title: const Text('Write a note'),
        content: TextField(
          key: const Key('note_input_field'),
          controller: noteController,
          maxLines: 5,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(hintText: 'What happened, when and where, and who saw it'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            key: const Key('save_note_button'),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (shouldSave == true && noteController.text.trim().isNotEmpty) {
      final text = noteController.text.trim();
      await IncidentApi.storeEvidenceEntry(
        userId: widget.userId,
        kind: 'NOTE',
        notes: text,
        fileBytes: utf8.encode(text),
        filename: 'note_${DateTime.now().millisecondsSinceEpoch}.txt',
      );
      await _loadEntries();
    }
  }

  Future<void> _addSample(String kind) async {
    final isAudio = kind == 'AUDIO';
    await IncidentApi.storeEvidenceEntry(
      userId: widget.userId,
      kind: kind,
      notes: isAudio ? 'Sample recording (demo, no real audio)' : 'Sample photo (demo, no real picture)',
      fileBytes: utf8.encode('MOKGOSI_DEMO_SAMPLE_${kind}_${DateTime.now().toIso8601String()}'),
      filename: '${isAudio ? 'audio' : 'photo'}_${DateTime.now().millisecondsSinceEpoch}.${isAudio ? 'wav' : 'jpg'}',
    );
    await _loadEntries();
  }

  Future<void> _deleteEntry(String entryId) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete this entry?'),
        content: const Text('It will be removed from this phone and from the backup.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            key: const Key('confirm_delete_entry'),
            style: FilledButton.styleFrom(backgroundColor: MokgosiColors.danger),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
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
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Choose at least one entry to share.')));
      return;
    }

    String recipientType = 'LEGAL';
    final notesController = TextEditingController();
    final count = _selectedEntryIds.length;

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text(count == 1 ? 'Share 1 entry' : 'Share $count entries'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'You will get a link to a signed file with the entries you chose. Anyone with the link can download it for 2 hours, so send it only to the person it is for.',
                  style: TextStyle(color: MokgosiColors.inkMuted, height: 1.4),
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  initialValue: recipientType,
                  decoration: const InputDecoration(labelText: 'Who is it for?'),
                  items: _recipientLabels.entries
                      .map((e) => DropdownMenuItem(value: e.key, child: Text(e.value)))
                      .toList(),
                  onChanged: (val) {
                    if (val != null) setDialogState(() => recipientType = val);
                  },
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: notesController,
                  decoration: const InputDecoration(labelText: 'A note for them (optional)'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            FilledButton(
              key: const Key('generate_bundle_button'),
              onPressed: () async {
                Navigator.pop(ctx);
                final res = await IncidentApi.shareEvidenceBundle(
                  userId: widget.userId,
                  entryIds: _selectedEntryIds.toList(),
                  recipientType: recipientType,
                  notes: notesController.text.trim().isNotEmpty ? notesController.text.trim() : null,
                );
                if (!mounted) return;
                if (res == null) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('The link could not be created. Check your connection and try again.')),
                  );
                  return;
                }
                setState(() {
                  _shareHistory.add({
                    'when': DateTime.now().toUtc().toIso8601String(),
                    'recipient': recipientType,
                    'count': _selectedEntryIds.length,
                  });
                  _selectedEntryIds.clear();
                });
                _showBundleLinkModal(res['download_url']?.toString() ?? '', recipientType);
              },
              child: const Text('Create link'),
            ),
          ],
        ),
      ),
    );
  }

  void _showBundleLinkModal(String downloadPath, String recipient) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Link ready'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('For: ${_recipientLabels[recipient] ?? recipient}'),
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: MokgosiColors.surfaceMuted,
                borderRadius: BorderRadius.circular(8),
              ),
              child: SelectableText('${MokgosiConfig.apiBase}$downloadPath', style: const TextStyle(fontSize: 13)),
            ),
            const SizedBox(height: 10),
            const Text(
              'The link stops working after 2 hours, and every download is recorded.',
              style: TextStyle(color: MokgosiColors.inkMuted, fontSize: 13),
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
          alignment: Alignment.bottomCenter,
          padding: const EdgeInsets.only(bottom: 48),
          child: const Text('Tap to return', style: TextStyle(color: Colors.white24, fontSize: 12)),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(MokgosiL10n.get('evidence_vault')),
        actions: [
          IconButton(
            tooltip: 'Dim the screen',
            icon: const Icon(Icons.dark_mode_outlined),
            onPressed: () => setState(() => _isScreenDimmed = true),
          ),
          HideAction(key: const Key('evidence_quick_exit'), label: MokgosiL10n.get('quick_exit'), onPressed: _quickExit),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'Write down what happened, when, and who was there. Entries stay private unless you choose to share them.',
                    style: TextStyle(color: MokgosiColors.inkMuted, height: 1.4),
                  ),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    key: const Key('btn_write_note'),
                    onPressed: _captureNote,
                    icon: const Icon(Icons.edit_outlined),
                    label: const Text('Write a note'),
                  ),
                  if (widget.allowSampleCaptures) ...[
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            key: const Key('btn_record_audio'),
                            onPressed: () => _addSample('AUDIO'),
                            child: const Text('Sample recording'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: OutlinedButton(
                            key: const Key('btn_take_photo'),
                            onPressed: () => _addSample('PHOTO'),
                            child: const Text('Sample photo'),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'Demo only: these add placeholder entries. Recording and photos are not built yet.',
                      style: TextStyle(color: MokgosiColors.inkFaint, fontSize: 12),
                    ),
                  ],
                ],
              ),
            ),
            if (_selectedEntryIds.isNotEmpty)
              Container(
                padding: const EdgeInsets.fromLTRB(16, 6, 12, 6),
                color: MokgosiColors.accentSoft,
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${_selectedEntryIds.length} selected',
                        style: const TextStyle(color: MokgosiColors.accent, fontWeight: FontWeight.w600),
                      ),
                    ),
                    FilledButton(
                      key: const Key('share_selected_button'),
                      style: FilledButton.styleFrom(minimumSize: const Size(0, 40)),
                      onPressed: _showShareBundleDialog,
                      child: const Text('Share'),
                    ),
                  ],
                ),
              ),
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _entries.isEmpty
                      ? const Padding(
                          padding: EdgeInsets.all(32),
                          child: Text(
                            'Nothing here yet. Your notes will appear here, newest first.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: MokgosiColors.inkFaint, height: 1.5),
                          ),
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                          itemCount: _entries.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 8),
                          itemBuilder: (ctx, idx) => _entryCard(_entries[idx]),
                        ),
            ),
            if (_shareHistory.isNotEmpty)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                decoration: const BoxDecoration(
                  color: MokgosiColors.surface,
                  border: Border(top: BorderSide(color: MokgosiColors.border)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SectionLabel('Shared'),
                    ..._shareHistory.map((log) {
                      final n = log['count'] as int;
                      final who = (_recipientLabels[log['recipient']] ?? 'someone').toLowerCase();
                      return Text(
                        'Shared ${n == 1 ? '1 entry' : '$n entries'} with $who · ${formatWhen(log['when'] as String)}',
                        style: const TextStyle(color: MokgosiColors.inkMuted, fontSize: 13),
                      );
                    }),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _entryCard(Map<String, dynamic> entry) {
    final id = entry['id']?.toString() ?? '';
    final kind = entry['kind']?.toString() ?? 'NOTE';
    final backedUp = entry['manifest_id'] != null || entry['is_synced'] == true;
    final selected = _selectedEntryIds.contains(id);
    final notes = entry['notes']?.toString() ?? '';
    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: selected ? MokgosiColors.accent : MokgosiColors.border, width: selected ? 1.5 : 1),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.fromLTRB(4, 6, 4, 6),
        leading: Checkbox(
          value: selected,
          onChanged: (val) => setState(() {
            if (val == true) {
              _selectedEntryIds.add(id);
            } else {
              _selectedEntryIds.remove(id);
            }
          }),
        ),
        title: Row(
          children: [
            Text(_kindLabels[kind] ?? kind, style: const TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(width: 8),
            Text(
              backedUp ? 'Backed up and signed' : 'Only on this phone',
              style: TextStyle(color: backedUp ? MokgosiColors.success : MokgosiColors.inkFaint, fontSize: 12),
            ),
          ],
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (notes.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(notes, style: const TextStyle(color: MokgosiColors.ink, fontSize: 14)),
              ),
            const SizedBox(height: 4),
            Text(formatWhen(entry['captured_at_utc']?.toString()), style: const TextStyle(fontSize: 12)),
          ],
        ),
        trailing: IconButton(
          tooltip: 'Delete',
          icon: const Icon(Icons.delete_outline),
          onPressed: () => _deleteEntry(id),
        ),
      ),
    );
  }
}
