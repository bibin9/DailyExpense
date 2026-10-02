import Flutter
import Security
import UIKit

// Daily Expense Tracker — BCR.
// UNVERIFIED ON DEVICE: written on Windows; must be compiled and tested on a
// Mac with Xcode (see docs/IOS_MAC.md).

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "DetPlatformBridge") {
      DetPlatformBridge.register(messenger: registrar.messenger())
    }
  }
}

/// Native capabilities for the Dart `PlatformServices` interface.
final class DetPlatformBridge {
  private static let tag = "com.bcr.dailyexpense.installkey.v1".data(using: .utf8)!
  private static var channel: FlutterMethodChannel?

  /// Fixed SubjectPublicKeyInfo header for an uncompressed P-256 point, so
  /// iOS returns the same SPKI DER format as Android and OpenSSL.
  private static let p256SpkiHeader: [UInt8] = [
    0x30, 0x59, 0x30, 0x13, 0x06, 0x07, 0x2a, 0x86, 0x48, 0xce, 0x3d, 0x02, 0x01,
    0x06, 0x08, 0x2a, 0x86, 0x48, 0xce, 0x3d, 0x03, 0x01, 0x07, 0x03, 0x42, 0x00,
  ]

  static func register(messenger: FlutterBinaryMessenger) {
    let ch = FlutterMethodChannel(name: "com.bcr.dailyexpense/platform", binaryMessenger: messenger)
    ch.setMethodCallHandler { call, result in
      switch call.method {
      case "installKey.ensure":
        result(ensureKey().map { FlutterStandardTypedData(bytes: $0) }
          ?? FlutterError(code: "native_error", message: "key_unavailable", details: nil))
      case "installKey.publicKey":
        result(publicKeySpki().map { FlutterStandardTypedData(bytes: $0) })
      case "installKey.sign":
        guard let data = (call.arguments as? FlutterStandardTypedData)?.data,
              let sig = sign(data) else {
          result(FlutterError(code: "native_error", message: "sign_failed", details: nil)); return
        }
        result(FlutterStandardTypedData(bytes: sig))
      case "installKey.delete":
        SecItemDelete(keyQuery() as CFDictionary)
        result(nil)
      case "installKey.protection":
        result(protection())
      case "storage.excludeFromBackup":
        result(excludeFromBackup(call.arguments as? String))
      case "storage.freeBytes":
        result(freeBytes(call.arguments as? String))
      case "window.setSecure":
        // iOS has no universal screenshot-blocking API; the app-switcher
        // snapshot is covered in SceneDelegate instead.
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
    channel = ch
  }

  private static func keyQuery() -> [String: Any] {
    return [
      kSecClass as String: kSecClassKey,
      kSecAttrApplicationTag as String: tag,
      kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
    ]
  }

  private static func privateKey() -> SecKey? {
    var q = keyQuery()
    q[kSecReturnRef as String] = true
    var item: CFTypeRef?
    guard SecItemCopyMatching(q as CFDictionary, &item) == errSecSuccess, let item else { return nil }
    return (item as! SecKey)
  }

  private static var secureEnclaveAvailable: Bool {
    #if targetEnvironment(simulator)
      return false
    #else
      return true
    #endif
  }

  /// Non-exportable P-256 key: Secure Enclave on devices, device-only
  /// Keychain on the simulator. Never synchronised to iCloud Keychain.
  private static func ensureKey() -> Data? {
    if privateKey() == nil {
      var error: Unmanaged<CFError>?
      var privAttrs: [String: Any] = [
        kSecAttrIsPermanent as String: true,
        kSecAttrApplicationTag as String: tag,
      ]
      var attrs: [String: Any] = [
        kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
        kSecAttrKeySizeInBits as String: 256,
        kSecAttrSynchronizable as String: false,
      ]
      if secureEnclaveAvailable,
         let access = SecAccessControlCreateWithFlags(
           nil, kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly, .privateKeyUsage, &error) {
        attrs[kSecAttrTokenID as String] = kSecAttrTokenIDSecureEnclave
        privAttrs[kSecAttrAccessControl as String] = access
      } else {
        privAttrs[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
      }
      attrs[kSecPrivateKeyAttrs as String] = privAttrs
      if SecKeyCreateRandomKey(attrs as CFDictionary, &error) == nil {
        // Secure Enclave can fail on some devices; fall back to Keychain.
        attrs.removeValue(forKey: kSecAttrTokenID as String)
        privAttrs.removeValue(forKey: kSecAttrAccessControl as String)
        privAttrs[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        attrs[kSecPrivateKeyAttrs as String] = privAttrs
        guard SecKeyCreateRandomKey(attrs as CFDictionary, &error) != nil else { return nil }
      }
    }
    return publicKeySpki()
  }

  private static func publicKeySpki() -> Data? {
    guard let key = privateKey(), let pub = SecKeyCopyPublicKey(key),
          let raw = SecKeyCopyExternalRepresentation(pub, nil) as Data?, raw.count == 65 else {
      return nil
    }
    return Data(p256SpkiHeader) + raw
  }

  /// ECDSA-SHA256, X9.62/DER signature (same format as Android).
  private static func sign(_ data: Data) -> Data? {
    guard let key = privateKey() else { return nil }
    return SecKeyCreateSignature(key, .ecdsaSignatureMessageX962SHA256, data as CFData, nil) as Data?
  }

  private static func protection() -> String {
    guard let key = privateKey() else { return "not created" }
    let attrs = SecKeyCopyAttributes(key) as? [String: Any]
    if let token = attrs?[kSecAttrTokenID as String] as? String,
       token == (kSecAttrTokenIDSecureEnclave as String) {
      return "Secure Enclave"
    }
    return "iOS Keychain (this device only)"
  }

  /// Sets NSURLIsExcludedFromBackupKey. Called on every launch for the data
  /// folder and each file in it, so it survives file replacement/migration.
  private static func excludeFromBackup(_ path: String?) -> Bool {
    guard let path, FileManager.default.fileExists(atPath: path) else { return false }
    var url = URL(fileURLWithPath: path)
    var values = URLResourceValues()
    values.isExcludedFromBackup = true
    do {
      try url.setResourceValues(values)
      return true
    } catch {
      return false
    }
  }

  private static func freeBytes(_ path: String?) -> Int64? {
    let url = URL(fileURLWithPath: path ?? NSHomeDirectory())
    let v = try? url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
    return v?.volumeAvailableCapacityForImportantUsage
  }
}
