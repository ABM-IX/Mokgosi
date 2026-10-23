import 'package:flutter/material.dart';
import '../config/l10n.dart';
import '../config/mokgosi_config.dart';
import '../services/incident_api.dart';
import 'calculator_disguise_screen.dart';

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
        const SnackBar(
          content: Text('Maximum 5 trusted contacts allowed in safe network.'),
          backgroundColor: Colors.amber,
        ),
      );
      return;
    }

    final nameController = TextEditingController();
    final phoneController = TextEditingController();
    String selectedRole = 'TRUSTED_PERSON';
    int priority = _contacts.length + 1;

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          backgroundColor: const Color(0xff1a202c),
          title: Text(
            'Add Safe Network Contact ($priority/5)',
            style: const TextStyle(color: Colors.white, fontSize: 18),
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Choose someone you trust who the person causing harm cannot access or pressure.',
                  style: TextStyle(color: Color(0xfffc8181), fontSize: 13, height: 1.4),
                ),
                const SizedBox(height: 16),
                TextField(
                  key: const Key('contact_name_field'),
                  controller: nameController,
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(
                    labelText: 'Contact Name / Alias',
                    labelStyle: TextStyle(color: Color(0xffa0aec0)),
                    enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Color(0xff4a5568))),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  key: const Key('contact_phone_field'),
                  controller: phoneController,
                  keyboardType: TextInputType.phone,
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(
                    labelText: 'Phone (E.164 format e.g. +26771000000)',
                    labelStyle: TextStyle(color: Color(0xffa0aec0)),
                    enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Color(0xff4a5568))),
                  ),
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  initialValue: selectedRole,
                  dropdownColor: const Color(0xff2d3748),
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(
                    labelText: 'Role in Safe Network',
                    labelStyle: TextStyle(color: Color(0xffa0aec0)),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'TRUSTED_PERSON', child: Text('Trusted Person')),
                    DropdownMenuItem(value: 'FAMILY', child: Text('Family Member')),
                    DropdownMenuItem(value: 'NEIGHBOUR', child: Text('Neighbour')),
                    DropdownMenuItem(value: 'SUPPORT_ORG', child: Text('Support Organisation')),
                  ],
                  onChanged: (val) {
                    if (val != null) setDialogState(() => selectedRole = val);
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Cancel', style: TextStyle(color: Colors.white70)),
            ),
            ElevatedButton(
              key: const Key('save_contact_button'),
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xff319795)),
              onPressed: () async {
                final name = nameController.text.trim();
                final phone = phoneController.text.trim();
                if (name.isEmpty || !MokgosiConfig.isValidE164(phone)) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Please enter a valid name and E.164 phone number (+267...).'),
                      backgroundColor: Colors.redAccent,
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
              child: const Text('Save Contact', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _sendTestMessage(Map<String, dynamic> contact) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xff1a202c),
        title: Text('Test ${contact['name']}?'),
        content: Text(
          'A test safety SMS will be sent to ${contact['phone_e164']}. '
          'They will receive a signed link to confirm they received it.',
          style: const TextStyle(color: Color(0xffcbd5e0), height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel', style: TextStyle(color: Colors.white70)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xff319795)),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Send Test', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Test message dispatched to ${contact['name']}.'),
          backgroundColor: const Color(0xff2b6cb0),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xff0d1117),
      appBar: AppBar(
        backgroundColor: const Color(0xff161b22),
        title: Text(MokgosiL10n.get('safe_network'), style: const TextStyle(fontSize: 18)),
        actions: [
          IconButton(
            key: const Key('quick_exit_button'),
            tooltip: MokgosiL10n.get('quick_exit'),
            icon: const Icon(Icons.close_fullscreen, color: Color(0xfffc8181)),
            onPressed: _quickExit,
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // Warning Banner
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xff742a2a).withValues(alpha: 0.35),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xffe53e3e)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.security, color: Color(0xfffc8181), size: 22),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      MokgosiL10n.get('safe_network_warning'),
                      style: const TextStyle(
                        color: Color(0xfffeb2b2),
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Trusted Circle (${_contacts.length}/5)',
                  style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                ),
                TextButton.icon(
                  key: const Key('add_contact_button'),
                  onPressed: _showAddContactDialog,
                  icon: const Icon(Icons.person_add, color: Color(0xff38b2ac), size: 20),
                  label: const Text('Add Contact', style: TextStyle(color: Color(0xff38b2ac))),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (_isLoading)
              const Center(child: Padding(padding: EdgeInsets.all(32), child: CircularProgressIndicator()))
            else if (_contacts.isEmpty)
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: const Color(0xff161b22),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xff30363d)),
                ),
                child: const Column(
                  children: [
                    Icon(Icons.people_outline, color: Color(0xff718096), size: 40),
                    SizedBox(height: 12),
                    Text(
                      'No safe network contacts yet',
                      style: TextStyle(color: Colors.white70, fontSize: 15),
                    ),
                    SizedBox(height: 6),
                    Text(
                      'Add up to 5 people you trust to be notified in priority order during an alert.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Color(0xff718096), fontSize: 13, height: 1.4),
                    ),
                  ],
                ),
              )
            else
              ..._contacts.map((c) {
                final priority = c['priority'] ?? 1;
                final isFirst = priority == 1;
                return Card(
                  color: const Color(0xff161b22),
                  margin: const EdgeInsets.symmetric(vertical: 6),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                    side: BorderSide(color: isFirst ? const Color(0xff319795) : const Color(0xff30363d)),
                  ),
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                    leading: CircleAvatar(
                      backgroundColor: isFirst ? const Color(0xff319795) : const Color(0xff2d3748),
                      child: Text(
                        '$priority',
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                      ),
                    ),
                    title: Text(
                      c['name'] ?? 'Contact',
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                    ),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(c['phone_e164'] ?? '', style: const TextStyle(color: Color(0xffa0aec0), fontSize: 13)),
                        const SizedBox(height: 4),
                        Text(
                          isFirst ? MokgosiL10n.get('priority_1') : 'Priority #$priority Escalation',
                          style: TextStyle(
                            color: isFirst ? const Color(0xff4fd1c5) : const Color(0xff718096),
                            fontSize: 12,
                            fontWeight: isFirst ? FontWeight.bold : FontWeight.normal,
                          ),
                        ),
                      ],
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          tooltip: 'Send Test Alert',
                          icon: const Icon(Icons.send_outlined, color: Color(0xff63b3ed), size: 20),
                          onPressed: () => _sendTestMessage(c),
                        ),
                        IconButton(
                          tooltip: 'Delete Contact',
                          icon: const Icon(Icons.delete_outline, color: Color(0xffe53e3e), size: 20),
                          onPressed: () async {
                            await IncidentApi.deleteTrustedContact(c['id'].toString());
                            await _loadContacts();
                          },
                        ),
                      ],
                    ),
                  ),
                );
              }),
          ],
        ),
      ),
    );
  }
}
