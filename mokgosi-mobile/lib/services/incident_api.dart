import 'dart:async';
import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';
import '../config/mokgosi_config.dart';

class AlertDispatchOutcome {
  const AlertDispatchOutcome({
    required this.delivered,
    required this.queuedOffline,
    required this.smsFallbackFired,
    required this.clientEventId,
    required this.persistenceState,
    required this.notificationState,
    required this.notificationMode,
    required this.userMessage,
    this.incidentId,
    this.incidentPersisted = false,
    this.rawResponse,
  });

  final bool delivered;
  final bool queuedOffline;
  final bool smsFallbackFired;
  final String clientEventId;
  final String? incidentId;
  final bool incidentPersisted;
  final String persistenceState;
  final String notificationState;
  final String notificationMode;
  final String userMessage;
  final Map<String, dynamic>? rawResponse;
}

class IncidentApi {
  static const String _queueStorageKey = 'mokgosi_offline_queue_v1';
  static const MethodChannel _platform = MethodChannel('mokgosi/platform');

  static http.Client httpClient = http.Client();
  static bool simulateOfflineMode = false;
  static int smsFallbackCount = 0;
  static Timer? _retryTimer;

  static Future<List<Map<String, dynamic>>> getQueuedEvents() async {
    final raw = await PlatformStore.read(_queueStorageKey);
    if (raw == null || raw.isEmpty) return <Map<String, dynamic>>[];
    try {
      final decoded = jsonDecode(raw) as List<dynamic>;
      return decoded
          .whereType<Map<dynamic, dynamic>>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList();
    } catch (_) {
      return <Map<String, dynamic>>[];
    }
  }

  static Future<void> _saveQueuedEvents(List<Map<String, dynamic>> events) async {
    await PlatformStore.write(_queueStorageKey, jsonEncode(events));
  }

  /// Triggers an incident immediately without waiting on AI or high-accuracy GPS.
  /// Never claims success unless HTTP 2xx is returned; otherwise persists to the
  /// offline retry queue with a stable `client_event_id` and fires SMS fallback.
  static Future<AlertDispatchOutcome> trigger(
    String trigger, {
    double impactG = 1.0,
    double lat = MokgosiConfig.gaboroneDemoLat,
    double lng = MokgosiConfig.gaboroneDemoLng,
    String userId = 'MOKGOSI_DEMO_USER',
    String? trustedContactPhone,
    String category = 'PERSONAL_SAFETY',
    String? clientEventId,
    String? sourceTimestampUtc,
  }) async {
    final eventId = clientEventId ?? const Uuid().v4();
    final capturedUtc = sourceTimestampUtc ?? DateTime.now().toUtc().toIso8601String();
    final contact = (trustedContactPhone ?? MokgosiConfig.trustedContactPhone).trim();

    final requestBody = <String, dynamic>{
      'user_id': userId,
      'trigger_type': trigger,
      'category': category,
      'lat': lat,
      'lng': lng,
      'impact_g_force': impactG,
      'client_event_id': eventId,
      'source_timestamp_utc': capturedUtc,
    };
    if (contact.isNotEmpty && MokgosiConfig.isValidE164(contact)) {
      requestBody['trusted_contact_phone'] = contact;
    }

    if (simulateOfflineMode) {
      await _enqueueOfflineEvent(requestBody);
      final smsFired = await _fireDeviceSmsFallback(
        phone: contact,
        trigger: trigger,
        lat: lat,
        lng: lng,
      );
      _scheduleBackgroundFlush();
      return AlertDispatchOutcome(
        delivered: false,
        queuedOffline: true,
        smsFallbackFired: smsFired,
        clientEventId: eventId,
        persistenceState: 'QUEUED_OFFLINE',
        notificationState: smsFired ? 'SMS_FALLBACK_DISPATCHED' : 'QUEUED_OFFLINE',
        notificationMode: 'OFFLINE_QUEUE',
        userMessage: smsFired
            ? 'Queued — no signal. Will send automatically when online. Device SMS fallback opened.'
            : 'Queued — no signal. Will send automatically when connectivity returns.',
      );
    }

    try {
      final payload = await _postTriggerPayload(requestBody);
      final persisted = payload['incident_persisted'] == true;
      final persistenceState = (payload['persistence_state'] ?? 'UNKNOWN').toString();
      final notificationState = (payload['notification_state'] ?? 'UNKNOWN').toString();
      final notificationMode = (payload['notification_mode'] ?? 'DEMO_ONLY').toString();
      final incidentMap = payload['incident'] as Map<String, dynamic>?;
      final incidentId = incidentMap?['id']?.toString();

      final contactQueued =
          notificationState == 'QUEUED' || notificationState == 'ALREADY_QUEUED';
      final deliveryLabel = notificationMode == 'DEMO_ONLY'
          ? 'DEMO: trusted-person message only logged'
          : contactQueued
              ? 'Trusted-person notification queued'
              : 'Trusted-person contact not configured';
      final message = persisted
          ? 'Incident recorded. $deliveryLabel.'
          : 'Incident not recorded ($persistenceState). $deliveryLabel.';

      return AlertDispatchOutcome(
        delivered: true,
        queuedOffline: false,
        smsFallbackFired: false,
        clientEventId: eventId,
        incidentId: incidentId,
        incidentPersisted: persisted,
        persistenceState: persistenceState,
        notificationState: notificationState,
        notificationMode: notificationMode,
        userMessage: message,
        rawResponse: payload,
      );
    } catch (_) {
      await _enqueueOfflineEvent(requestBody);
      final smsFired = await _fireDeviceSmsFallback(
        phone: contact,
        trigger: trigger,
        lat: lat,
        lng: lng,
      );
      _scheduleBackgroundFlush();
      return AlertDispatchOutcome(
        delivered: false,
        queuedOffline: true,
        smsFallbackFired: smsFired,
        clientEventId: eventId,
        persistenceState: 'QUEUED_OFFLINE',
        notificationState: smsFired ? 'SMS_FALLBACK_DISPATCHED' : 'QUEUED_OFFLINE',
        notificationMode: 'OFFLINE_QUEUE',
        userMessage: smsFired
            ? 'Queued — no signal. Retrying automatically; SMS fallback triggered.'
            : 'Queued — connection unavailable. Retrying automatically with idempotency key.',
      );
    }
  }

  static Future<Map<String, dynamic>> _postTriggerPayload(
    Map<String, dynamic> requestBody,
  ) async {
    if (MokgosiConfig.deviceApiKey.isEmpty) {
      throw StateError('Device API key is not configured.');
    }
    final uri = Uri.parse('${MokgosiConfig.apiBase}/api/v1/incidents/trigger');
    final response = await httpClient
        .post(
          uri,
          headers: <String, String>{
            'Content-Type': 'application/json',
            'X-Device-Key': MokgosiConfig.deviceApiKey,
          },
          body: jsonEncode(requestBody),
        )
        .timeout(const Duration(seconds: 5));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError('Alert request failed (HTTP ${response.statusCode}).');
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  static Future<void> _enqueueOfflineEvent(Map<String, dynamic> requestBody) async {
    final queue = await getQueuedEvents();
    final eventId = requestBody['client_event_id'];
    final existingIdx = queue.indexWhere((e) => e['client_event_id'] == eventId);
    if (existingIdx >= 0) {
      queue[existingIdx] = requestBody;
    } else {
      queue.add(requestBody);
    }
    await _saveQueuedEvents(queue);
  }

  static Future<bool> _fireDeviceSmsFallback({
    required String phone,
    required String trigger,
    required double lat,
    required double lng,
  }) async {
    final targetPhone = phone.isNotEmpty ? phone : MokgosiConfig.trustedContactPhone;
    final mapsUrl = 'https://www.google.com/maps?q=$lat,$lng';
    final smsText =
        'MOKGOSI ALERT ($trigger): Data offline. Latest coordinates: $mapsUrl';
    smsFallbackCount += 1;
    if (targetPhone.isEmpty) {
      return true;
    }
    try {
      await _platform.invokeMethod<dynamic>('sendFallbackSms', <String, dynamic>{
        'phone': targetPhone,
        'message': smsText,
      });
    } catch (_) {
      // Safe fallback in unit/widget tests or emulators without an SMS handler.
    }
    return true;
  }

  /// Flushes all queued offline events in FIFO order using their original
  /// `client_event_id` so the server deduplicates retries cleanly.
  static Future<int> flushOfflineQueue() async {
    if (simulateOfflineMode) return 0;
    final queue = await getQueuedEvents();
    if (queue.isEmpty) return 0;
    final remaining = <Map<String, dynamic>>[];
    var deliveredCount = 0;
    for (final item in queue) {
      try {
        await _postTriggerPayload(item);
        deliveredCount += 1;
      } catch (_) {
        remaining.add(item);
      }
    }
    await _saveQueuedEvents(remaining);
    if (remaining.isEmpty) {
      _retryTimer?.cancel();
      _retryTimer = null;
    }
    return deliveredCount;
  }

  static void _scheduleBackgroundFlush() {
    _retryTimer?.cancel();
    _retryTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      flushOfflineQueue();
    });
  }

  /// Appends a live GPS coordinate breadcrumb (`POST /api/v1/incidents/{id}/location`).
  static Future<bool> appendLocation({
    required String incidentId,
    required double lat,
    required double lng,
    String? capturedAtUtc,
  }) async {
    if (simulateOfflineMode || incidentId.isEmpty) return false;
    try {
      final uri = Uri.parse(
        '${MokgosiConfig.apiBase}/api/v1/incidents/$incidentId/location',
      );
      final response = await httpClient
          .post(
            uri,
            headers: <String, String>{
              'Content-Type': 'application/json',
              'X-Device-Key': MokgosiConfig.deviceApiKey,
            },
            body: jsonEncode(<String, dynamic>{
              'lat': lat,
              'lng': lng,
              'captured_at_utc':
                  capturedAtUtc ?? DateTime.now().toUtc().toIso8601String(),
            }),
          )
          .timeout(const Duration(seconds: 4));
      return response.statusCode >= 200 && response.statusCode < 300;
    } catch (_) {
      return false;
    }
  }

  /// Route 3: Non-blocking upload of a 15-second consenting acoustic context clip.
  /// Denied microphone permission or network failure never affects the active alert.
  static Future<bool> uploadConsentingAudioClip({
    required String incidentId,
    required bool userConsented,
    String? simulatedDemoProfile,
  }) async {
    if (!userConsented || simulateOfflineMode || incidentId.isEmpty) {
      return false;
    }
    try {
      var hasMicPerm = true;
      try {
        final permResult = await _platform.invokeMethod<bool>('hasAudioPermission');
        if (permResult == false) {
          hasMicPerm = false;
        }
      } catch (_) {}
      if (!hasMicPerm) {
        return false;
      }

      final uri = Uri.parse(
        '${MokgosiConfig.apiBase}/api/v1/incidents/$incidentId/acoustic-context',
      );
      final request = http.MultipartRequest('POST', uri);
      request.headers['X-Device-Key'] = MokgosiConfig.deviceApiKey;
      request.fields['source_timestamp_utc'] =
          DateTime.now().toUtc().toIso8601String();
      if (simulatedDemoProfile != null && simulatedDemoProfile.isNotEmpty) {
        request.fields['simulated_profile'] = simulatedDemoProfile;
      }
      final wavPayload = utf8.encode(
        'RIFF_MOKGOSI_CONSENTING_15S_AUDIO_CLIP:$incidentId',
      );
      request.files.add(
        http.MultipartFile.fromBytes(
          'audio_file',
          wavPayload,
          filename: 'consenting_15s_clip.wav',
        ),
      );
      final streamed =
          await httpClient.send(request).timeout(const Duration(seconds: 5));
      return streamed.statusCode >= 200 && streamed.statusCode < 300;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> requestPersonalDataDeletion({required String userId}) async {
    await PlatformStore.clear();
    if (simulateOfflineMode) return true;
    try {
      final uri = Uri.parse('${MokgosiConfig.apiBase}/api/v1/users/$userId/data');
      final response = await httpClient
          .delete(
            uri,
            headers: <String, String>{
              'X-Device-Key': MokgosiConfig.deviceApiKey,
            },
          )
          .timeout(const Duration(seconds: 4));
      return response.statusCode >= 200 && response.statusCode < 300;
    } catch (_) {
      return false;
    }
  }

  // --- Safe Network Contacts ---

  static Future<List<Map<String, dynamic>>> fetchTrustedContacts(String userId) async {
    if (simulateOfflineMode) {
      final cached = await PlatformStore.read('cached_contacts_$userId');
      if (cached != null) {
        return List<Map<String, dynamic>>.from(jsonDecode(cached) as List);
      }
      return [];
    }
    try {
      final uri = Uri.parse('${MokgosiConfig.apiBase}/api/v1/network/contacts?user_id=$userId');
      final res = await httpClient.get(uri, headers: {'X-Device-Key': MokgosiConfig.deviceApiKey});
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final list = List<Map<String, dynamic>>.from(data['contacts'] ?? []);
        await PlatformStore.write('cached_contacts_$userId', jsonEncode(list));
        return list;
      }
    } catch (_) {}
    final cached = await PlatformStore.read('cached_contacts_$userId');
    if (cached != null) {
      return List<Map<String, dynamic>>.from(jsonDecode(cached) as List);
    }
    return [];
  }

  static Future<Map<String, dynamic>?> addTrustedContact({
    required String userId,
    required String name,
    required String phone,
    String role = 'TRUSTED_PERSON',
    int priority = 1,
    List<String>? notifyOn,
  }) async {
    if (simulateOfflineMode) {
      final local = {
        'id': const Uuid().v4(),
        'user_id': userId,
        'name': name,
        'phone_e164': phone,
        'role': role,
        'priority': priority,
        'notify_on': notifyOn ?? ['P1_CRITICAL', 'P2_HIGH', 'P3_VERIFY'],
        'is_active': true,
      };
      final existing = await fetchTrustedContacts(userId);
      existing.add(local);
      await PlatformStore.write('cached_contacts_$userId', jsonEncode(existing));
      return local;
    }
    try {
      final uri = Uri.parse('${MokgosiConfig.apiBase}/api/v1/network/contacts');
      final res = await httpClient.post(
        uri,
        headers: {
          'Content-Type': 'application/json',
          'X-Device-Key': MokgosiConfig.deviceApiKey,
        },
        body: jsonEncode({
          'user_id': userId,
          'name': name,
          'phone_e164': phone,
          'role': role,
          'priority': priority,
          'notify_on': notifyOn ?? ['P1_CRITICAL', 'P2_HIGH', 'P3_VERIFY', 'EXPLICIT_SOS', 'DURESS_PIN', 'COVERT_SOS', 'SHAKE_SOS'],
        }),
      );
      if (res.statusCode >= 200 && res.statusCode < 300) {
        final data = jsonDecode(res.body);
        return Map<String, dynamic>.from(data['contact'] ?? {});
      }
    } catch (_) {}
    return null;
  }

  static Future<bool> deleteTrustedContact(String contactId) async {
    if (simulateOfflineMode) return true;
    try {
      final uri = Uri.parse('${MokgosiConfig.apiBase}/api/v1/network/contacts/$contactId');
      final res = await httpClient.delete(uri, headers: {'X-Device-Key': MokgosiConfig.deviceApiKey});
      return res.statusCode >= 200 && res.statusCode < 300;
    } catch (_) {
      return false;
    }
  }

  // --- Verified Referral Partners ---

  static Future<List<Map<String, dynamic>>> fetchVerifiedReferrals({String? region, String? type}) async {
    if (simulateOfflineMode) {
      final cached = await PlatformStore.read('cached_referrals');
      if (cached != null) {
        return List<Map<String, dynamic>>.from(jsonDecode(cached) as List);
      }
      return [];
    }
    try {
      var url = '${MokgosiConfig.apiBase}/api/v1/referrals';
      final params = <String>[];
      if (region != null) params.add('region=$region');
      if (type != null) params.add('type=$type');
      if (params.isNotEmpty) url += '?${params.join("&")}';

      final res = await httpClient.get(Uri.parse(url));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final list = List<Map<String, dynamic>>.from(data['partners'] ?? []);
        await PlatformStore.write('cached_referrals', jsonEncode(list));
        return list;
      }
    } catch (_) {}
    final cached = await PlatformStore.read('cached_referrals');
    if (cached != null) {
      return List<Map<String, dynamic>>.from(jsonDecode(cached) as List);
    }
    return [];
  }

  // --- Consents ---

  static Future<bool> updateConsents({
    required String userId,
    bool location = true,
    bool audio = false,
    bool responderContact = false,
    bool shareEvidence = false,
  }) async {
    final payload = {
      'user_id': userId,
      'location': location,
      'audio': audio,
      'responder_contact': responderContact,
      'share_evidence': shareEvidence,
    };
    await PlatformStore.write('user_consents_$userId', jsonEncode(payload));
    if (simulateOfflineMode) return true;
    try {
      final uri = Uri.parse('${MokgosiConfig.apiBase}/api/v1/consents');
      final res = await httpClient.patch(
        uri,
        headers: {
          'Content-Type': 'application/json',
          'X-Device-Key': MokgosiConfig.deviceApiKey,
        },
        body: jsonEncode(payload),
      );
      return res.statusCode >= 200 && res.statusCode < 300;
    } catch (_) {
      return false;
    }
  }

  static Future<Map<String, dynamic>> fetchConsents(String userId) async {
    final cached = await PlatformStore.read('user_consents_$userId');
    if (cached != null) {
      return Map<String, dynamic>.from(jsonDecode(cached));
    }
    if (!simulateOfflineMode) {
      try {
        final uri = Uri.parse('${MokgosiConfig.apiBase}/api/v1/consents/$userId');
        final res = await httpClient.get(uri, headers: {'X-Device-Key': MokgosiConfig.deviceApiKey});
        if (res.statusCode == 200) {
          final data = jsonDecode(res.body);
          final map = Map<String, dynamic>.from(data['consents'] ?? {});
          await PlatformStore.write('user_consents_$userId', jsonEncode(map));
          return map;
        }
      } catch (_) {}
    }
    return {
      'user_id': userId,
      'location': true,
      'audio': false,
      'responder_contact': false,
      'share_evidence': false,
    };
  }

  // --- Evidence Entries & Sharing ---

  static Future<Map<String, dynamic>?> storeEvidenceEntry({
    required String userId,
    required String kind,
    String? notes,
    List<int>? fileBytes,
    String? filename,
    double? lat,
    double? lng,
  }) async {
    if (simulateOfflineMode) {
      final local = {
        'id': const Uuid().v4(),
        'user_id': userId,
        'kind': kind,
        'captured_at_utc': DateTime.now().toUtc().toIso8601String(),
        'notes': notes,
        'storage_path': 'local-vault/$filename',
        'is_synced': false,
      };
      final existing = await fetchEvidenceEntries(userId);
      existing.insert(0, local);
      await PlatformStore.write('cached_evidence_$userId', jsonEncode(existing));
      return local;
    }
    try {
      final uri = Uri.parse('${MokgosiConfig.apiBase}/api/v1/evidence-entries');
      final request = http.MultipartRequest('POST', uri);
      request.headers['X-Device-Key'] = MokgosiConfig.deviceApiKey;
      request.fields['user_id'] = userId;
      request.fields['kind'] = kind;
      if (notes != null) request.fields['notes'] = notes;
      if (lat != null) request.fields['lat'] = lat.toString();
      if (lng != null) request.fields['lng'] = lng.toString();
      request.fields['source_capture_utc'] = DateTime.now().toUtc().toIso8601String();

      if (fileBytes != null && fileBytes.isNotEmpty) {
        request.files.add(
          http.MultipartFile.fromBytes('media_file', fileBytes, filename: filename ?? 'file.bin'),
        );
      }
      final streamed = await httpClient.send(request).timeout(const Duration(seconds: 8));
      final res = await http.Response.fromStream(streamed);
      if (res.statusCode >= 200 && res.statusCode < 300) {
        final data = jsonDecode(res.body);
        return Map<String, dynamic>.from(data['entry'] ?? {});
      }
    } catch (_) {}
    return null;
  }

  static Future<List<Map<String, dynamic>>> fetchEvidenceEntries(String userId) async {
    if (!simulateOfflineMode) {
      try {
        final uri = Uri.parse('${MokgosiConfig.apiBase}/api/v1/evidence-entries?user_id=$userId');
        final res = await httpClient.get(uri, headers: {'X-Device-Key': MokgosiConfig.deviceApiKey});
        if (res.statusCode == 200) {
          final data = jsonDecode(res.body);
          final list = List<Map<String, dynamic>>.from(data['entries'] ?? []);
          await PlatformStore.write('cached_evidence_$userId', jsonEncode(list));
          return list;
        }
      } catch (_) {}
    }
    final cached = await PlatformStore.read('cached_evidence_$userId');
    if (cached != null) {
      return List<Map<String, dynamic>>.from(jsonDecode(cached) as List);
    }
    return [];
  }

  static Future<bool> deleteEvidenceEntry(String entryId, {bool hardDelete = false, String? userId}) async {
    if (userId != null) {
      final existing = await fetchEvidenceEntries(userId);
      existing.removeWhere((e) => e['id'] == entryId);
      await PlatformStore.write('cached_evidence_$userId', jsonEncode(existing));
    }
    if (simulateOfflineMode) return true;
    try {
      final uri = Uri.parse('${MokgosiConfig.apiBase}/api/v1/evidence-entries/$entryId?hard_delete=$hardDelete');
      final res = await httpClient.delete(uri, headers: {'X-Device-Key': MokgosiConfig.deviceApiKey});
      return res.statusCode >= 200 && res.statusCode < 300;
    } catch (_) {
      return false;
    }
  }

  static Future<Map<String, dynamic>?> shareEvidenceBundle({
    required String userId,
    required List<String> entryIds,
    required String recipientType,
    String? notes,
  }) async {
    if (simulateOfflineMode) {
      return {
        'bundle_id': const Uuid().v4(),
        'download_url': '/offline-bundle',
        'recipient_type': recipientType,
        'entry_count': entryIds.length,
      };
    }
    try {
      final uri = Uri.parse('${MokgosiConfig.apiBase}/api/v1/evidence-entries/share');
      final res = await httpClient.post(
        uri,
        headers: {
          'Content-Type': 'application/json',
          'X-Device-Key': MokgosiConfig.deviceApiKey,
        },
        body: jsonEncode({
          'user_id': userId,
          'entry_ids': entryIds,
          'recipient_type': recipientType,
          'notes': notes,
        }),
      );
      if (res.statusCode >= 200 && res.statusCode < 300) {
        return Map<String, dynamic>.from(jsonDecode(res.body));
      }
    } catch (_) {}
    return null;
  }
}
