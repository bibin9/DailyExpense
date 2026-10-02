package com.bcr.dailyexpense

import android.os.Build
import android.os.Bundle
import android.os.StatFs
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyInfo
import android.security.keystore.KeyProperties
import android.security.keystore.StrongBoxUnavailableException
import android.view.WindowManager
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.security.KeyFactory
import java.security.KeyPairGenerator
import java.security.KeyStore
import java.security.PrivateKey
import java.security.Signature
import java.security.spec.ECGenParameterSpec

/**
 * Daily Expense Tracker — BCR.
 *
 * FlutterFragmentActivity is required by local_auth (BiometricPrompt).
 * Native responsibilities are kept minimal: screenshot/recents protection,
 * the per-installation activation key in Android Keystore, and free space.
 */
class MainActivity : FlutterFragmentActivity() {

    override fun onCreate(savedInstanceState: Bundle?) {
        // Secure by default, before any Flutter frame is drawn: blocks
        // screenshots, screen recording and the recent-apps preview.
        window.setFlags(
            WindowManager.LayoutParams.FLAG_SECURE,
            WindowManager.LayoutParams.FLAG_SECURE,
        )
        super.onCreate(savedInstanceState)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                try {
                    when (call.method) {
                        "installKey.ensure" -> result.success(ensureKey())
                        "installKey.publicKey" -> result.success(publicKey())
                        "installKey.sign" -> result.success(sign(call.arguments as ByteArray))
                        "installKey.delete" -> {
                            keyStore().deleteEntry(ALIAS)
                            result.success(null)
                        }
                        "installKey.protection" -> result.success(protection())
                        // Android backup exclusion is declared in the manifest
                        // (allowBackup=false + data extraction rules).
                        "storage.excludeFromBackup" -> result.success(true)
                        "storage.freeBytes" -> result.success(
                            StatFs(call.arguments as String).availableBytes,
                        )
                        "window.setSecure" -> {
                            if (call.arguments as Boolean) {
                                window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
                            } else {
                                window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
                            }
                            result.success(null)
                        }
                        else -> result.notImplemented()
                    }
                } catch (e: Exception) {
                    // Only the exception class name is returned; no data.
                    result.error("native_error", e.javaClass.simpleName, null)
                }
            }
    }

    private fun keyStore(): KeyStore = KeyStore.getInstance(KEYSTORE).apply { load(null) }

    /** SubjectPublicKeyInfo DER of the installation key, or null. */
    private fun publicKey(): ByteArray? =
        keyStore().getCertificate(ALIAS)?.publicKey?.encoded

    private fun ensureKey(): ByteArray {
        publicKey()?.let { return it }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            try {
                generate(strongBox = true)
                return publicKey()!!
            } catch (_: StrongBoxUnavailableException) {
                // Fall through to TEE-backed key.
            }
        }
        generate(strongBox = false)
        return publicKey()!!
    }

    /** Non-exportable EC P-256 signing key inside Android Keystore. */
    private fun generate(strongBox: Boolean) {
        val spec = KeyGenParameterSpec.Builder(ALIAS, KeyProperties.PURPOSE_SIGN)
            .setAlgorithmParameterSpec(ECGenParameterSpec("secp256r1"))
            .setDigests(KeyProperties.DIGEST_SHA256)
        if (strongBox && Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            spec.setIsStrongBoxBacked(true)
        }
        KeyPairGenerator.getInstance(KeyProperties.KEY_ALGORITHM_EC, KEYSTORE).apply {
            initialize(spec.build())
            generateKeyPair()
        }
    }

    /** ECDSA-SHA256, DER-encoded signature. */
    private fun sign(data: ByteArray): ByteArray {
        val key = keyStore().getKey(ALIAS, null) as PrivateKey
        return Signature.getInstance("SHA256withECDSA").run {
            initSign(key)
            update(data)
            sign()
        }
    }

    private fun protection(): String {
        val key = keyStore().getKey(ALIAS, null) as? PrivateKey ?: return "not created"
        val info = KeyFactory.getInstance(key.algorithm, KEYSTORE)
            .getKeySpec(key, KeyInfo::class.java)
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            when (info.securityLevel) {
                KeyProperties.SECURITY_LEVEL_STRONGBOX -> "Android Keystore (StrongBox)"
                KeyProperties.SECURITY_LEVEL_TRUSTED_ENVIRONMENT -> "Android Keystore (TEE)"
                KeyProperties.SECURITY_LEVEL_SOFTWARE -> "Android Keystore (software)"
                else -> "Android Keystore"
            }
        } else {
            @Suppress("DEPRECATION")
            if (info.isInsideSecureHardware) "Android Keystore (hardware)" else "Android Keystore (software)"
        }
    }

    companion object {
        private const val CHANNEL = "com.bcr.dailyexpense/platform"
        private const val KEYSTORE = "AndroidKeyStore"
        private const val ALIAS = "det_installation_key_v1"
    }
}
