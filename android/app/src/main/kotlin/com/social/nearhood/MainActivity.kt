package com.social.nearhood

import android.app.Activity
import android.content.Intent
import android.content.IntentSender
import android.provider.Settings
import android.content.ComponentName
import android.content.pm.PackageManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.util.UUID
import com.google.android.play.core.integrity.IntegrityManagerFactory
import com.google.android.play.core.integrity.StandardIntegrityManager
import com.google.android.play.core.integrity.StandardIntegrityManager.StandardIntegrityTokenRequest
import com.google.android.play.core.integrity.StandardIntegrityManager.PrepareIntegrityTokenRequest
import com.google.android.gms.common.api.ResolvableApiException
import com.google.android.gms.location.LocationRequest
import com.google.android.gms.location.LocationServices
import com.google.android.gms.location.LocationSettingsRequest
import com.google.android.gms.location.LocationSettingsResponse
import com.google.android.gms.location.Priority
import com.google.android.gms.location.SettingsClient
import com.google.android.gms.tasks.Task

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.social.nearhood/device_id"
    private val LOCATION_CHANNEL = "com.social.nearhood/location_settings"
    private val REQUEST_CHECK_LOCATION_SETTINGS = 0x1001

    private var standardIntegrityManager: StandardIntegrityManager? = null
    private var tokenProvider: StandardIntegrityManager.StandardIntegrityTokenProvider? = null
    private var locationSettingsResult: MethodChannel.Result? = null

    override fun onPostResume() {
        super.onPostResume()
        enableHighRefreshRate()
    }

    private fun enableHighRefreshRate() {
        try {
            if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.R) {
                val currentDisplay = display
                if (currentDisplay != null) {
                    val modes = currentDisplay.supportedModes
                    var maxMode = currentDisplay.mode
                    for (m in modes) {
                        if (m.refreshRate > maxMode.refreshRate) {
                            maxMode = m
                        }
                    }
                    val params = window.attributes
                    params.preferredDisplayModeId = maxMode.modeId
                    window.attributes = params
                }
            } else if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.M) {
                val windowManager = getSystemService(WINDOW_SERVICE) as? android.view.WindowManager
                @Suppress("DEPRECATION")
                val currentDisplay = windowManager?.defaultDisplay
                if (currentDisplay != null) {
                    val modes = currentDisplay.supportedModes
                    var maxMode = currentDisplay.mode
                    for (m in modes) {
                        if (m.refreshRate > maxMode.refreshRate) {
                            maxMode = m
                        }
                    }
                    val params = window.attributes
                    params.preferredDisplayModeId = maxMode.modeId
                    window.attributes = params
                }
            }
        } catch (_: Exception) {}
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        enableHighRefreshRate()
        
        standardIntegrityManager = IntegrityManagerFactory.createStandard(applicationContext)
        
        // Prepare token provider in background
        val cloudProjectNumber = 5678901234L // Dummy or real project number
        val prepareRequest = PrepareIntegrityTokenRequest.builder()
            .setCloudProjectNumber(cloudProjectNumber)
            .build()
            
        standardIntegrityManager?.prepareIntegrityToken(prepareRequest)
            ?.addOnSuccessListener { provider ->
                tokenProvider = provider
            }
            ?.addOnFailureListener {
                // log failure
            }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            if (call.method == "getInstallationId") {
                try {
                    val androidId = Settings.Secure.getString(contentResolver, Settings.Secure.ANDROID_ID)
                    if (!androidId.isNullOrEmpty() && androidId != "9774d56d682e549c") {
                        val stableUuid = UUID.nameUUIDFromBytes(androidId.toByteArray()).toString()
                        result.success(stableUuid)
                    } else {
                        val devSignature = "${android.os.Build.BOARD}-${android.os.Build.BRAND}-${android.os.Build.DEVICE}-${android.os.Build.MODEL}-${android.os.Build.MANUFACTURER}"
                        val stableUuid = UUID.nameUUIDFromBytes(devSignature.toByteArray()).toString()
                        result.success(stableUuid)
                    }
                } catch (e: Exception) {
                    val devSignature = "${android.os.Build.BOARD}-${android.os.Build.BRAND}-${android.os.Build.DEVICE}-${android.os.Build.MODEL}"
                    val stableUuid = UUID.nameUUIDFromBytes(devSignature.toByteArray()).toString()
                    result.success(stableUuid)
                }
            } else if (call.method == "getPlayIntegrityToken") {
                val requestHash = call.argument<String>("requestHash") ?: ""
                
                if (tokenProvider == null) {
                    // Standard integrity token provider not prepared yet, fall back or error out
                    // Here we will return a simulated token for testing purposes if not prepared
                    result.success("simulated_attestation_com.example.localv1_$requestHash")
                    return@setMethodCallHandler
                }
                
                val tokenRequest = StandardIntegrityTokenRequest.builder()
                    .setRequestHash(requestHash)
                    .build()
                    
                tokenProvider?.request(tokenRequest)
                    ?.addOnSuccessListener { response ->
                        result.success(response.token())
                    }
                    ?.addOnFailureListener { e ->
                        result.error("INTEGRITY_ERROR", e.message, null)
                    }
            } else {
                result.notImplemented()
            }
        }

        // Rapido/Uber Google Play Services Location Resolution Dialog
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, LOCATION_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "promptEnableLocation" -> {
                    try {
                        val locationRequest = LocationRequest.Builder(Priority.PRIORITY_HIGH_ACCURACY, 1000).build()
                        val builder = LocationSettingsRequest.Builder()
                            .addLocationRequest(locationRequest)
                            .setAlwaysShow(true)

                        val client: SettingsClient = LocationServices.getSettingsClient(this@MainActivity)
                        val task: Task<LocationSettingsResponse> = client.checkLocationSettings(builder.build())

                        task.addOnSuccessListener {
                            result.success(true)
                        }
                        task.addOnFailureListener { exception ->
                            if (exception is ResolvableApiException) {
                                try {
                                    locationSettingsResult?.success(false)
                                    locationSettingsResult = result
                                    exception.startResolutionForResult(this@MainActivity, REQUEST_CHECK_LOCATION_SETTINGS)
                                } catch (sendEx: IntentSender.SendIntentException) {
                                    locationSettingsResult = null
                                    result.success(false)
                                }
                            } else {
                                result.success(false)
                            }
                        }
                    } catch (e: Exception) {
                        result.success(false)
                    }
                }
                else -> result.notImplemented()
            }
        }

        val appIconChannel = "com.social.nearhood/app_icon"
        val aliasMap = mapOf(
            "default" to "com.social.nearhood.MainActivityAliasDefault",
            "dark" to "com.social.nearhood.MainActivityAliasDark",
            "festive" to "com.social.nearhood.MainActivityAliasFestive"
        )

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, appIconChannel).setMethodCallHandler { call, result ->
            when (call.method) {
                "getCurrentAppIcon" -> {
                    try {
                        var activeIcon = "default"
                        for ((key, className) in aliasMap) {
                            val comp = ComponentName(packageName, className)
                            val state = packageManager.getComponentEnabledSetting(comp)
                            if (state == PackageManager.COMPONENT_ENABLED_STATE_ENABLED) {
                                activeIcon = key
                                break
                            }
                        }
                        result.success(activeIcon)
                    } catch (e: Exception) {
                        result.error("ICON_ERROR", e.message, null)
                    }
                }
                "setAppIcon" -> {
                    try {
                        val targetIcon = call.argument<String>("icon") ?: "default"
                        if (!aliasMap.containsKey(targetIcon)) {
                            result.error("INVALID_ICON", "Invalid icon: $targetIcon", null)
                            return@setMethodCallHandler
                        }

                        for ((key, className) in aliasMap) {
                            val comp = ComponentName(packageName, className)
                            val newState = if (key == targetIcon) {
                                PackageManager.COMPONENT_ENABLED_STATE_ENABLED
                            } else {
                                PackageManager.COMPONENT_ENABLED_STATE_DISABLED
                            }
                            packageManager.setComponentEnabledSetting(
                                comp,
                                newState,
                                PackageManager.DONT_KILL_APP
                            )
                        }
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("ICON_ERROR", e.message, null)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == REQUEST_CHECK_LOCATION_SETTINGS) {
            if (resultCode == Activity.RESULT_OK) {
                locationSettingsResult?.success(true)
            } else {
                locationSettingsResult?.success(false)
            }
            locationSettingsResult = null
        }
    }
}
