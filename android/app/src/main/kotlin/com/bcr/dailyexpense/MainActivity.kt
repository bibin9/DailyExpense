package com.bcr.dailyexpense

import android.app.Activity
import android.content.Intent
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
import java.io.File
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
                        "file.saveAs" -> {
                            val args = call.arguments as Map<*, *>
                            startDocumentRequest(
                                result,
                                REQ_SAVE,
                                args["source"] as String,
                                Intent(Intent.ACTION_CREATE_DOCUMENT)
                                    .addCategory(Intent.CATEGORY_OPENABLE)
                                    .setType("application/octet-stream")
                                    .putExtra(Intent.EXTRA_TITLE, args["name"] as String),
                            )
                        }
                        "file.pick" -> startDocumentRequest(
                            result,
                            REQ_PICK,
                            call.arguments as String,
                            Intent(Intent.ACTION_OPEN_DOCUMENT)
                                .addCategory(Intent.CATEGORY_OPENABLE)
                                .setType("*/*"),
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

    // --- System document pickers (backup save / restore pick) -------------
    // Uses the Storage Access Framework: the user chooses the place, the
    // app only copies bytes. No storage or network permission is needed.

    private var pendingResult: MethodChannel.Result? = null
    private var pendingPath: String? = null

    private fun startDocumentRequest(
        result: MethodChannel.Result,
        requestCode: Int,
        path: String,
        intent: Intent,
    ) {
        if (pendingResult != null) {
            result.error("busy", "picker_already_open", null)
            return
        }
        pendingResult = result
        pendingPath = path
        @Suppress("DEPRECATION")
        startActivityForResult(intent, requestCode)
    }

    @Deprecated("Deprecated in Java")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        @Suppress("DEPRECATION")
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != REQ_SAVE && requestCode != REQ_PICK) return
        val result = pendingResult ?: return
        val path = pendingPath
        pendingResult = null
        pendingPath = null
        val uri = data?.data
        if (resultCode != Activity.RESULT_OK || uri == null || path == null) {
            result.success(false)
            return
        }
        try {
            if (requestCode == REQ_SAVE) {
                contentResolver.openOutputStream(uri, "wt")!!.use { out ->
                    File(path).inputStream().use { it.copyTo(out) }
                }
            } else {
                contentResolver.openInputStream(uri)!!.use { input ->
                    File(path).outputStream().use { out ->
                        val buffer = ByteArray(64 * 1024)
                        var total = 0L
                        while (true) {
                            val n = input.read(buffer)
                            if (n < 0) break
                            total += n
                            if (total > MAX_IMPORT_BYTES) throw IllegalStateException("too_large")
                            out.write(buffer, 0, n)
                        }
                    }
                }
            }
            result.success(true)
        } catch (e: Exception) {
            if (requestCode == REQ_PICK) File(path).delete()
            result.error("native_error", e.javaClass.simpleName, null)
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
        private const val REQ_SAVE = 4101
        private const val REQ_PICK = 4102
        private const val MAX_IMPORT_BYTES = 512L * 1024 * 1024
    }
}
