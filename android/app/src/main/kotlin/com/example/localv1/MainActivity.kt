package com.example.localv1

import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.util.UUID
import com.google.android.play.core.integrity.IntegrityManagerFactory
import com.google.android.play.core.integrity.StandardIntegrityManager
import com.google.android.play.core.integrity.StandardIntegrityManager.StandardIntegrityTokenRequest
import com.google.android.play.core.integrity.StandardIntegrityManager.PrepareIntegrityTokenRequest

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.example.localv1/device_id"
    private var standardIntegrityManager: StandardIntegrityManager? = null
    private var tokenProvider: StandardIntegrityManager.StandardIntegrityTokenProvider? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        
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
    }
}
