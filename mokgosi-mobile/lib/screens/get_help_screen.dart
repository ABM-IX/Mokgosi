import 'package:flutter/material.dart';
import '../config/l10n.dart';
import '../config/theme.dart';
import '../services/incident_api.dart';
import '../widgets/common.dart';
import 'calculator_disguise_screen.dart';

const _filters = <String, String>{
  'ALL': 'All',
  'POLICE': 'Police',
  'SHELTER': 'Shelter',
  'COUNSELLING': 'Counselling',
  'LEGAL': 'Legal help',
};
const _typeLabels = <String, String>{
  'POLICE': 'Police',
  'GBV_DESK': 'GBV desk',
  'SHELTER': 'Shelter',
  'COUNSELLING': 'Counselling',
  'LEGAL': 'Legal help',
  'HELPLINE': 'Helpline',
};

/// Support services, listed only once they have confirmed their details. No number is ever made up.
class GetHelpScreen extends StatefulWidget {
  const GetHelpScreen({super.key});

  @override
  State<GetHelpScreen> createState() => _GetHelpScreenState();
}

class _GetHelpScreenState extends State<GetHelpScreen> {
  List<Map<String, dynamic>> _referrals = [];
  bool _isLoading = true;
  String _selectedType = 'ALL';

  @override
  void initState() {
    super.initState();
    _loadReferrals();
  }

  Future<void> _loadReferrals() async {
    setState(() => _isLoading = true);
    final data = await IncidentApi.fetchVerifiedReferrals(type: _selectedType == 'ALL' ? null : _selectedType);
    if (mounted) {
      setState(() {
        _referrals = data;
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(MokgosiL10n.get('get_help')),
        actions: [
          HideAction(key: const Key('get_help_quick_exit'), label: MokgosiL10n.get('quick_exit'), onPressed: _quickExit),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: Row(
                children: _filters.entries
                    .map((e) => Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: ChoiceChip(
                            label: Text(e.value),
                            selected: _selectedType == e.key,
                            showCheckmark: false,
                            onSelected: (selected) {
                              if (selected) {
                                setState(() => _selectedType = e.key);
                                _loadReferrals();
                              }
                            },
                          ),
                        ))
                    .toList(),
              ),
            ),
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _referrals.isEmpty
                      ? _buildNotYetState()
                      : ListView.separated(
                          padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                          itemCount: _referrals.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 10),
                          itemBuilder: (ctx, idx) => _buildReferralCard(_referrals[idx]),
                        ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNotYetState() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      children: [
        Text(
          MokgosiL10n.get('referrals_verifying_notice'),
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        Text(
          MokgosiL10n.get('referrals_verifying_body'),
          style: const TextStyle(color: MokgosiColors.inkMuted, height: 1.5),
        ),
        const SizedBox(height: 16),
        const InfoNote(
          'No phone numbers are shown until the service itself confirms them. If you are in danger right now, contact the police.',
        ),
      ],
    );
  }

  Widget _buildReferralCard(Map<String, dynamic> item) {
    final name = item['name']?.toString() ?? 'Support service';
    final type = _typeLabels[item['type']] ?? 'Support';
    final hours = item['hours']?.toString();
    final phone = item['phone']?.toString();
    final languages = (item['languages'] as List?)?.map((l) => l == 'tn' ? 'Setswana' : 'English').join(', ');
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(name, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            Text(
              [type, if (hours != null && hours.isNotEmpty) hours, if (languages != null) languages].join(' · '),
              style: const TextStyle(color: MokgosiColors.inkMuted, fontSize: 13),
            ),
            const SizedBox(height: 12),
            if (phone != null && phone.isNotEmpty)
              OutlinedButton.icon(
                onPressed: () => showDialog<void>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: Text(name),
                    content: SelectableText(formatPhone(phone), style: const TextStyle(fontSize: 18)),
                    actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close'))],
                  ),
                ),
                icon: const Icon(Icons.call_outlined, size: 18),
                label: Text(formatPhone(phone)),
              )
            else
              const Text('Number not confirmed yet', style: TextStyle(color: MokgosiColors.inkFaint, fontSize: 13)),
          ],
        ),
      ),
    );
  }
}
