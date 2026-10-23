import 'package:flutter/material.dart';
import '../config/l10n.dart';
import '../services/incident_api.dart';
import 'calculator_disguise_screen.dart';

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
    final data = await IncidentApi.fetchVerifiedReferrals(
      type: _selectedType == 'ALL' ? null : _selectedType,
    );
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
      backgroundColor: const Color(0xff0d1117),
      appBar: AppBar(
        backgroundColor: const Color(0xff161b22),
        title: Text(MokgosiL10n.get('get_help'), style: const TextStyle(fontSize: 18)),
        actions: [
          IconButton(
            key: const Key('get_help_quick_exit'),
            tooltip: MokgosiL10n.get('quick_exit'),
            icon: const Icon(Icons.close_fullscreen, color: Color(0xfffc8181)),
            onPressed: _quickExit,
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Filter bar
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              color: const Color(0xff161b22),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    _filterChip('ALL', 'All Services'),
                    const SizedBox(width: 8),
                    _filterChip('POLICE', 'Police GBV Desk'),
                    const SizedBox(width: 8),
                    _filterChip('SHELTER', 'Emergency Shelter'),
                    const SizedBox(width: 8),
                    _filterChip('COUNSELLING', 'Counselling'),
                    const SizedBox(width: 8),
                    _filterChip('LEGAL', 'Legal Aid'),
                  ],
                ),
              ),
            ),
            // Content
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _referrals.isEmpty
                      ? _buildEmptyVerifiedState()
                      : ListView.builder(
                          padding: const EdgeInsets.all(16),
                          itemCount: _referrals.length,
                          itemBuilder: (ctx, idx) {
                            final ref = _referrals[idx];
                            return _buildReferralCard(ref);
                          },
                        ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _filterChip(String type, String label) {
    final isSelected = _selectedType == type;
    return ChoiceChip(
      label: Text(label, style: TextStyle(color: isSelected ? Colors.white : Colors.white70, fontSize: 12)),
      selected: isSelected,
      selectedColor: const Color(0xff319795),
      backgroundColor: const Color(0xff21262d),
      onSelected: (selected) {
        if (selected) {
          setState(() => _selectedType = type);
          _loadReferrals();
        }
      },
    );
  }

  Widget _buildEmptyVerifiedState() {
    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.verified_user_outlined, size: 54, color: Color(0xff718096)),
          const SizedBox(height: 16),
          Text(
            MokgosiL10n.get('referrals_verifying_notice'),
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            MokgosiL10n.get('referrals_verifying_body'),
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Color(0xffa0aec0),
              fontSize: 13,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xff161b22),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xff30363d)),
            ),
            child: const Row(
              children: [
                Icon(Icons.info_outline, color: Color(0xff4fd1c5), size: 20),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'No fake contact numbers are ever shown. Partner directory updates will appear automatically once formally verified with service providers.',
                    style: TextStyle(color: Color(0xffcbd5e0), fontSize: 12, height: 1.4),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildReferralCard(Map<String, dynamic> item) {
    final name = item['name'] ?? 'Support Service';
    final type = item['type'] ?? 'SUPPORT';
    final hours = item['hours'] ?? 'Hours unlisted';
    final phone = item['phone'];
    final languages = (item['languages'] as List?)?.join(', ') ?? 'English, Setswana';

    return Card(
      color: const Color(0xff161b22),
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: const BorderSide(color: Color(0xff30363d)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    name,
                    style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xff234e52),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    type,
                    style: const TextStyle(color: Color(0xff81e6d9), fontSize: 10, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                const Icon(Icons.access_time, size: 14, color: Color(0xffa0aec0)),
                const SizedBox(width: 6),
                Text(hours, style: const TextStyle(color: Color(0xffa0aec0), fontSize: 12)),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                const Icon(Icons.language, size: 14, color: Color(0xffa0aec0)),
                const SizedBox(width: 6),
                Text(languages, style: const TextStyle(color: Color(0xffa0aec0), fontSize: 12)),
              ],
            ),
            const SizedBox(height: 12),
            if (phone != null && phone.toString().isNotEmpty)
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xff319795),
                  foregroundColor: Colors.white,
                  minimumSize: const Size.fromHeight(38),
                ),
                onPressed: () {
                  // In demo, shows dialog with confirmed phone number
                  showDialog<void>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      backgroundColor: const Color(0xff1a202c),
                      title: Text('Call $name?'),
                      content: Text('Dial verified number: $phone'),
                      actions: [
                        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close')),
                      ],
                    ),
                  );
                },
                icon: const Icon(Icons.call, size: 16),
                label: Text('Call $phone'),
              )
            else
              const Text(
                'Phone number pending official verification',
                style: TextStyle(color: Color(0xffe2e8f0), fontSize: 12, fontStyle: FontStyle.italic),
              ),
          ],
        ),
      ),
    );
  }
}
