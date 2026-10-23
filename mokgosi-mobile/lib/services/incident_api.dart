import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';
import '../config/mokgosi_config.dart';

class IncidentApi {
  static Future<Map<String, dynamic>> trigger(String trigger, {double impactG = 1}) async {
    if (MokgosiConfig.deviceApiKey.isEmpty) {
      throw StateError('Device API key is not configured.');
    }
    final uri = Uri.parse('${MokgosiConfig.apiBase}/api/v1/incidents/trigger');
    final requestBody = <String, dynamic>{
      'user_id': 'MOKGOSI_DEMO_USER',
      'trigger_type': trigger,
      'lat': -24.6560,
      'lng': 25.9090,
      'impact_g_force': impactG,
      'client_event_id': const Uuid().v4(),
    };
    if (MokgosiConfig.trustedContactPhone.isNotEmpty) {
      requestBody['trusted_contact_phone'] = MokgosiConfig.trustedContactPhone;
    }
    final response = await http.post(uri, headers: {
      'Content-Type': 'application/json',
      'X-Device-Key': MokgosiConfig.deviceApiKey,
    }, body: jsonEncode(requestBody)).timeout(const Duration(seconds: 5));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError('Alert request failed (HTTP ${response.statusCode}).');
    }
    final payload = jsonDecode(response.body) as Map<String, dynamic>;
    return payload;
  }
}
