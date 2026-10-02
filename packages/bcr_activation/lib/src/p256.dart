import 'dart:math';
import 'dart:typed_data';

import 'package:pointycastle/export.dart';

import 'der.dart';

/// NIST P-256 (secp256r1) ECDSA with SHA-256 — the only algorithm used by
/// activation. Chosen because Android Keystore (incl. StrongBox) and the iOS
/// Secure Enclave both support it natively, and it is JOSE "ES256".
final ECDomainParameters p256 = ECCurve_secp256r1();

/// P-256 field prime p = 2^256 - 2^224 + 2^192 + 2^96 - 1 (FIPS 186-4 D.1.2.3).
final BigInt _p256FieldPrime = BigInt.parse(
  'ffffffff00000001000000000000000000000000ffffffffffffffffffffffff',
  radix: 16,
);

Uint8List sha256(List<int> data) =>
    SHA256Digest().process(Uint8List.fromList(data));

/// Validates that [point65] is an uncompressed point on P-256 (not infinity).
ECPoint decodeValidatedP256Point(Uint8List point65) {
  if (point65.length != 65 || point65[0] != 0x04) {
    throw const DerFormatException('Expected uncompressed P-256 point');
  }
  final x = bytesToBigInt(point65.sublist(1, 33));
  final y = bytesToBigInt(point65.sublist(33, 65));
  final prime = _p256FieldPrime;
  if (x >= prime || y >= prime) {
    throw const DerFormatException('Point coordinate out of range');
  }
  final a = p256.curve.a!.toBigInteger()!;
  final b = p256.curve.b!.toBigInteger()!;
  final lhs = (y * y) % prime;
  final rhs = (x * x * x + a * x + b) % prime;
  if (lhs != rhs) throw const DerFormatException('Point is not on P-256');
  final q = p256.curve.decodePoint(point65);
  if (q == null || q.isInfinity) {
    throw const DerFormatException('Invalid P-256 point');
  }
  return q;
}

class P256KeyPair {
  P256KeyPair(this.privateScalar, this.publicPoint);

  /// 32-byte private scalar `d`.
  final Uint8List privateScalar;

  /// 65-byte uncompressed public point.
  final Uint8List publicPoint;

  Uint8List get spki => encodeP256Spki(publicPoint);

  static P256KeyPair generate([Random? random]) {
    final rnd = random ?? Random.secure();
    final seed = Uint8List.fromList(List.generate(32, (_) => rnd.nextInt(256)));
    final fortuna = FortunaRandom()..seed(KeyParameter(seed));
    final gen = ECKeyGenerator()
      ..init(ParametersWithRandom(ECKeyGeneratorParameters(p256), fortuna));
    final pair = gen.generateKeyPair();
    final priv = pair.privateKey;
    final pub = pair.publicKey;
    return P256KeyPair(
      bigIntToBytes(priv.d!, 32),
      Uint8List.fromList(pub.Q!.getEncoded(false)),
    );
  }

  static P256KeyPair fromPrivateScalar(Uint8List d) {
    final scalar = bytesToBigInt(d);
    if (scalar <= BigInt.zero || scalar >= p256.n) {
      throw const DerFormatException('Private scalar out of range');
    }
    final q = (p256.G * scalar)!;
    return P256KeyPair(Uint8List.fromList(d), q.getEncoded(false));
  }

  /// Deterministic (RFC 6979) ECDSA-SHA256 signature as raw r||s (64 bytes,
  /// JOSE/IEEE P1363 format).
  Uint8List signRaw(List<int> message) {
    final signer = ECDSASigner(SHA256Digest(), HMac(SHA256Digest(), 64))
      ..init(
        true,
        PrivateKeyParameter<ECPrivateKey>(
          ECPrivateKey(bytesToBigInt(privateScalar), p256),
        ),
      );
    final sig =
        signer.generateSignature(Uint8List.fromList(message)) as ECSignature;
    return Uint8List.fromList([
      ...bigIntToBytes(sig.r, 32),
      ...bigIntToBytes(sig.s, 32),
    ]);
  }

  /// Same signature as DER, matching what Android/iOS/OpenSSL produce.
  Uint8List signDer(List<int> message) {
    final raw = signRaw(message);
    return encodeDerEcdsaSignature(
      bytesToBigInt(raw.sublist(0, 32)),
      bytesToBigInt(raw.sublist(32)),
    );
  }
}

/// Verifies an ECDSA-SHA256 signature over [message] with the P-256 public
/// key [publicKey] (SPKI DER or raw point). Never throws for bad input.
bool verifyP256({
  required Uint8List publicKey,
  required List<int> message,
  required BigInt r,
  required BigInt s,
}) {
  try {
    final q = decodeValidatedP256Point(parseP256PublicKey(publicKey));
    final n = p256.n;
    if (r <= BigInt.zero || r >= n || s <= BigInt.zero || s >= n) return false;
    final verifier = ECDSASigner(SHA256Digest())
      ..init(false, PublicKeyParameter<ECPublicKey>(ECPublicKey(q, p256)));
    return verifier.verifySignature(
      Uint8List.fromList(message),
      ECSignature(r, s),
    );
  } on Object {
    return false;
  }
}

bool verifyP256Raw(Uint8List publicKey, List<int> message, Uint8List raw64) {
  if (raw64.length != 64) return false;
  return verifyP256(
    publicKey: publicKey,
    message: message,
    r: bytesToBigInt(raw64.sublist(0, 32)),
    s: bytesToBigInt(raw64.sublist(32)),
  );
}

bool verifyP256Der(Uint8List publicKey, List<int> message, Uint8List der) {
  try {
    final sig = parseDerEcdsaSignature(der);
    return verifyP256(
      publicKey: publicKey,
      message: message,
      r: sig.r,
      s: sig.s,
    );
  } on Object {
    return false;
  }
}
