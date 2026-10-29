import 'package:flutter/material.dart';
import '../config/l10n.dart';
import '../config/mokgosi_config.dart';
import '../config/theme.dart';
import '../services/incident_api.dart';
import '../widgets/common.dart';
import 'calculator_disguise_screen.dart';

const _roleLabels = <String, String>{
  'TRUSTED_PERSON': 'Trusted friend',
  'FAMILY': 'Family',
  'NEIGHBOUR': 'Neighbour',
  'SUPPORT_ORG': 'Support organisation',
};

class SafeNetworkScreen extends StatefulWidget {
  const SafeNetworkScreen({super.key, this.userId = 'MOKGOSI_DEMO_USER'});

  final String userId;

  @override
  State<SafeNetworkScreen> createState() => _SafeNetworkScreenState();
}

class _SafeNetworkScreenState extends State<SafeNetworkScreen> {
  List<Map<String, dynamic>> _contacts = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadContacts();
  }

  Future<void> _loadContacts() async {
    setState(() => _isLoading = true);
    final list = await IncidentApi.fetchTrustedContacts(widget.userId);
    if (mounted) {
      setState(() {
        _contacts = list;
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

  Future<void> _showAddContactDialog() async {
    if (_contacts.length >= 5) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('You can have up to 5 trusted contacts. Remove one to add someone new.')),
      );
      return;
    }

    final nameController = TextEditingController();
    final phoneController = TextEditingController();
    String selectedRole = 'TRUSTED_PERSON';
    final priority = _contacts.length + 1;

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Add a trusted contact'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  priority == 1 ? 'They will be messaged first.' : 'They will be number $priority in the order.',
                  style: const TextStyle(color: MokgosiColors.inkMuted),
                ),
                const SizedBox(height: 16),
                TextField(
                  key: const Key('contact_name_field'),
                  controller: nameController,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(labelText: 'Name'),
                ),
                const SizedBox(height: 12),
                TextField(
                  key: const Key('contact_phone_field'),
                  controller: phoneController,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(labelText: 'Mobile number', hintText: '+267 7X XXX XXX'),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: selectedRole,
                  decoration: const InputDecoration(labelText: 'Who are they to you?'),
                  items: _roleLabels.entries
                      .map((e) => DropdownMenuItem(value: e.key, child: Text(e.value)))
                      .toList(),
                  onChanged: (val) {
                    if (val != null) setDialogState(() => selectedRole = val);
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Cancel')),
            FilledButton(
              key: const Key('save_contact_button'),
              onPressed: () async {
                final name = nameController.text.trim();
                final phone = phoneController.text.replaceAll(' ', '').trim();
                if (name.isEmpty || !MokgosiConfig.isValidE164(phone)) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Add a name, and a number that starts with + and the country code, like +267 71 234 567.'),
                    ),
                  );
                  return;
                }
                Navigator.of(ctx).pop();
                await IncidentApi.addTrustedContact(
                  userId: widget.userId,
                  name: name,
                  phone: phone,
                  role: selectedRole,
                  priority: priority,
                );
                await _loadContacts();
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _removeContact(Map<String, dynamic> contact) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Remove ${contact['name'] ?? 'this contact'}?'),
        content: const Text('They will no longer be told when you raise an alert.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: MokgosiColors.danger),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await IncidentApi.deleteTrustedContact(contact['id'].toString());
      await _loadContacts();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(MokgosiL10n.get('safe_network')),
        actions: [
          HideAction(key: const Key('quick_exit_button'), label: MokgosiL10n.get('quick_exit'), onPressed: _quickExit),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
          children: [
            InfoNote(MokgosiL10n.get('safe_network_warning'), tone: NoteTone.warning),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${_contacts.length} of 5 added',
                    style: const TextStyle(color: MokgosiColors.inkMuted),
                  ),
                ),
                TextButton.icon(
                  key: const Key('add_contact_button'),
                  onPressed: _showAddContactDialog,
                  icon: const Icon(Icons.add, size: 20),
                  label: const Text('Add contact'),
                ),
              ],
            ),
            const SizedBox(height: 4),
            if (_isLoading)
              const Padding(padding: EdgeInsets.all(32), child: Center(child: CircularProgressIndicator()))
            else if (_contacts.isEmpty)
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('No trusted contacts yet', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                      SizedBox(height: 6),
                      Text(
                        'Add up to five people. When you raise an alert they are messaged one at a time, in the order you choose, until someone replies.',
                        style: TextStyle(color: MokgosiColors.inkMuted, height: 1.4),
                      ),
                    ],
                  ),
                ),
              )
            else
              Card(
                clipBehavior: Clip.antiAlias,
                child: Column(
                  children: [
                    for (var i = 0; i < _contacts.length; i++) ...[
                      if (i > 0) const Divider(indent: 72),
                      _contactTile(_contacts[i]),
                    ],
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _contactTile(Map<String, dynamic> c) {
    final priority = c['priority'] ?? 1;
    final role = _roleLabels[c['role']] ?? 'Trusted contact';
    final order = priority == 1 ? MokgosiL10n.get('priority_1') : 'Number $priority';
    return ListTile(
      contentPadding: const EdgeInsets.fromLTRB(16, 6, 8, 6),
      leading: CircleAvatar(
        backgroundColor: priority == 1 ? MokgosiColors.accent : MokgosiColors.surfaceMuted,
        foregroundColor: priority == 1 ? Colors.white : MokgosiColors.ink,
        child: Text('$priority'),
      ),
      title: Text(c['name'] ?? 'Contact', style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Text('$role · ${formatPhone(c['phone_e164']?.toString())}\n$order'),
      isThreeLine: true,
      trailing: IconButton(
        tooltip: 'Remove',
        icon: const Icon(Icons.delete_outline),
        onPressed: () => _removeContact(c),
      ),
    );
  }
}
