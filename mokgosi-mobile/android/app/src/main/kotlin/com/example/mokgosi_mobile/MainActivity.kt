package com.example.mokgosi_mobile

import android.Manifest
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val channelName = "mokgosi/platform"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // By default, secure window against recent-apps preview inspection
        window.setFlags(WindowManager.LayoutParams.FLAG_SECURE, WindowManager.LayoutParams.FLAG_SECURE)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "setSecureFlag" -> {
                        val secure = call.argument<Boolean>("secure") ?: true
                        if (secure) {
                            window.setFlags(WindowManager.LayoutParams.FLAG_SECURE, WindowManager.LayoutParams.FLAG_SECURE)
                        } else {
                            window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
                        }
                        result.success(true)
                    }
                    "startForegroundEscort" -> {
                        val title = call.argument<String>("title") ?: "Walk in progress"
                        val body = call.argument<String>("body") ?: "Tap to check in or end the walk."
                        val includeMic = call.argument<Boolean>("includeMicrophone") ?: false
                        val serviceIntent = Intent(this, EscortForegroundService::class.java).apply {
                            putExtra(EscortForegroundService.EXTRA_TITLE, title)
                            putExtra(EscortForegroundService.EXTRA_BODY, body)
                            putExtra(EscortForegroundService.EXTRA_INCLUDE_MIC, includeMic)
                        }
                        try {
                            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                                startForegroundService(serviceIntent)
                            } else {
                                startService(serviceIntent)
                            }
                            result.success(true)
                        } catch (_: Exception) {
                            result.success(false)
                        }
                    }
                    "stopForegroundEscort" -> {
                        val serviceIntent = Intent(this, EscortForegroundService::class.java)
                        stopService(serviceIntent)
                        result.success(true)
                    }
                    "startRepeatingVibration" -> {
                        try {
                            val vibrator = getVibrator()
                            val timings = longArrayOf(0, 450, 200, 450, 200, 700)
                            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                                vibrator?.vibrate(VibrationEffect.createWaveform(timings, 0))
                            } else {
                                @Suppress("DEPRECATION")
                                vibrator?.vibrate(timings, 0)
                            }
                            result.success(true)
                        } catch (_: Exception) {
                            result.success(false)
                        }
                    }
                    "stopVibration" -> {
                        try {
                            getVibrator()?.cancel()
                            result.success(true)
                        } catch (_: Exception) {
                            result.success(false)
                        }
                    }
                    "sendFallbackSms" -> {
                        val phone = call.argument<String>("phone") ?: ""
                        val message = call.argument<String>("message") ?: ""
                        if (phone.isBlank()) {
                            result.success(mapOf("dispatched" to false, "reason" to "NO_PHONE"))
                        } else {
                            try {
                                val smsIntent = Intent(Intent.ACTION_SENDTO, Uri.parse("smsto:$phone")).apply {
                                    putExtra("sms_body", message)
                                    flags = Intent.FLAG_ACTIVITY_NEW_TASK
                                }
                                startActivity(smsIntent)
                                result.success(mapOf("dispatched" to true, "mode" to "SMSTO_INTENT"))
                            } catch (e: Exception) {
                                result.success(mapOf("dispatched" to false, "reason" to (e.message ?: "INTENT_ERROR")))
                            }
                        }
                    }
                    "hasAudioPermission" -> {
                        val granted = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                            checkSelfPermission(Manifest.permission.RECORD_AUDIO) == PackageManager.PERMISSION_GRANTED
                        } else {
                            true
                        }
                        result.success(granted)
                    }
                    "readStore" -> {
                        val key = call.argument<String>("key") ?: ""
                        val prefs = getSharedPreferences("mokgosi_secure_store", Context.MODE_PRIVATE)
                        result.success(prefs.getString(key, null))
                    }
                    "writeStore" -> {
                        val key = call.argument<String>("key") ?: ""
                        val value = call.argument<String>("value")
                        val prefs = getSharedPreferences("mokgosi_secure_store", Context.MODE_PRIVATE)
                        if (value == null) {
                            prefs.edit().remove(key).apply()
                        } else {
                            prefs.edit().putString(key, value).apply()
                        }
                        result.success(true)
                    }
                    "clearStore" -> {
                        val prefs = getSharedPreferences("mokgosi_secure_store", Context.MODE_PRIVATE)
                        prefs.edit().clear().apply()
                        result.success(true)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun getVibrator(): Vibrator? {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            val manager = getSystemService(Context.VIBRATOR_MANAGER_SERVICE) as? VibratorManager
            manager?.defaultVibrator
        } else {
            @Suppress("DEPRECATION")
            getSystemService(Context.VIBRATOR_SERVICE) as? Vibrator
        }
    }
}
