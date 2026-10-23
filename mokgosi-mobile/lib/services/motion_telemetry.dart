import 'dart:async';
import 'dart:math' as math;
import 'package:geolocator/geolocator.dart';
import 'package:sensors_plus/sensors_plus.dart';
import '../config/mokgosi_config.dart';

class GeoPointFix {
  const GeoPointFix({
    required this.lat,
    required this.lng,
    required this.isDemoOverride,
    required this.capturedAtUtc,
  });

  final double lat;
  final double lng;
  final bool isDemoOverride;
  final String capturedAtUtc;
}

/// Monitors accelerometer vector magnitude (g = sqrt(x^2 + y^2 + z^2) / 9.81)
/// and device GPS coordinates without ever blocking an alert on sensor locks.
class MotionTelemetry {
  StreamSubscription<AccelerometerEvent>? _accelSub;
  StreamSubscription<Position>? _positionSub;

  double _peakGForce = 1.0;
  GeoPointFix _lastKnownFix = GeoPointFix(
    lat: MokgosiConfig.gaboroneDemoLat,
    lng: MokgosiConfig.gaboroneDemoLng,
    isDemoOverride: true,
    capturedAtUtc: DateTime.now().toUtc().toIso8601String(),
  );

  double get peakGForce => _peakGForce;
  GeoPointFix get lastKnownFix => _lastKnownFix;

  /// Pure function for unit testing accelerometer vector to G-force conversion.
  static double computeGForce(double x, double y, double z) {
    final magnitude = math.sqrt(x * x + y * y + z * z);
    return double.parse((magnitude / 9.81).toStringAsFixed(2));
  }

  void resetPeakG() {
    _peakGForce = 1.0;
  }

  /// Starts listening to hardware accelerometer events and triggers [onImpactThreshold]
  /// when magnitude >= 3.5g.
  void startMonitoring({
    required void Function(double gForce) onImpactThreshold,
  }) {
    _accelSub?.cancel();
    try {
      _accelSub = accelerometerEventStream().listen(
        (event) {
          final g = computeGForce(event.x, event.y, event.z);
          if (g > _peakGForce) {
            _peakGForce = g;
          }
          if (g >= MokgosiConfig.impactThresholdG) {
            onImpactThreshold(_peakGForce);
          }
        },
        onError: (_) {
          // Sensor errors on emulators must never interrupt escort protection.
        },
      );
    } catch (_) {}
  }

  /// Allows deterministic demo / automated testing of a >= 3.5g physical impact.
  double simulateImpact({
    double simulatedG = 4.2,
    void Function(double gForce)? onImpactThreshold,
  }) {
    if (simulatedG > _peakGForce) {
      _peakGForce = simulatedG;
    }
    if (_peakGForce >= MokgosiConfig.impactThresholdG) {
      onImpactThreshold?.call(_peakGForce);
    }
    return _peakGForce;
  }

  /// Resolves the best available GPS fix immediately without blocking an SOS.
  /// If [pinToGaboroneDemoCbd] is true or location permission is denied, returns
  /// the Gaborone CBD camera-mesh coordinates (-24.6560, 25.9090).
  Future<GeoPointFix> resolveCurrentFix({required bool pinToGaboroneDemoCbd}) async {
    final nowUtc = DateTime.now().toUtc().toIso8601String();
    if (pinToGaboroneDemoCbd) {
      _lastKnownFix = GeoPointFix(
        lat: MokgosiConfig.gaboroneDemoLat,
        lng: MokgosiConfig.gaboroneDemoLng,
        isDemoOverride: true,
        capturedAtUtc: nowUtc,
      );
      return _lastKnownFix;
    }
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        return _lastKnownFix;
      }
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return _lastKnownFix;
      }
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 2),
        ),
      );
      _lastKnownFix = GeoPointFix(
        lat: pos.latitude,
        lng: pos.longitude,
        isDemoOverride: false,
        capturedAtUtc: DateTime.now().toUtc().toIso8601String(),
      );
    } catch (_) {
      // Never block an alert on GPS timeout; return last known fix immediately.
    }
    return _lastKnownFix;
  }

  /// Streams live GPS updates while an incident is active (including covertly
  /// after Duress PIN entry).
  void startLiveLocationStream({
    required bool pinToGaboroneDemoCbd,
    required void Function(GeoPointFix fix) onLocationUpdate,
  }) {
    _positionSub?.cancel();
    if (pinToGaboroneDemoCbd) {
      return;
    }
    try {
      _positionSub = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 10,
        ),
      ).listen(
        (pos) {
          final fix = GeoPointFix(
            lat: pos.latitude,
            lng: pos.longitude,
            isDemoOverride: false,
            capturedAtUtc: DateTime.now().toUtc().toIso8601String(),
          );
          _lastKnownFix = fix;
          onLocationUpdate(fix);
        },
        onError: (_) {},
      );
    } catch (_) {}
  }

  void stopMonitoring() {
    _accelSub?.cancel();
    _accelSub = null;
    _positionSub?.cancel();
    _positionSub = null;
  }
}

