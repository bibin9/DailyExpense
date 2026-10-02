import 'dart:convert';
import 'dart:typed_data';

/// Minimal DER helpers for the fixed key and signature formats used by
/// activation. Only what is needed for NIST P-256 is implemented.

/// OID 1.2.840.10045.2.1 (id-ecPublicKey)
const List<int> _oidEcPublicKey = [0x2a, 0x86, 0x48, 0xce, 0x3d, 0x02, 0x01];

/// OID 1.2.840.10045.3.1.7 (prime256v1 / secp256r1 / NIST P-256)
const List<int> _oidPrime256v1 = [
  0x2a, 0x86, 0x48, 0xce, 0x3d, 0x03, 0x01, 0x07, //
];

/// Fixed SubjectPublicKeyInfo prefix for an uncompressed P-256 point.
/// SPKI = prefix (26 bytes) + 0x04 || X (32) || Y (32) = 91 bytes.
final Uint8List p256SpkiPrefix = Uint8List.fromList([
  0x30, 0x59, 0x30, 0x13, 0x06, 0x07, ..._oidEcPublicKey, //
  0x06, 0x08, ..._oidPrime256v1, 0x03, 0x42, 0x00,
]);

class DerFormatException extends FormatException {
  const DerFormatException(super.message);
}

class _Tlv {
  _Tlv(this.tag, this.valueStart, this.valueEnd);
  final int tag;
  final int valueStart;
  final int valueEnd;
  int get length => valueEnd - valueStart;
}

_Tlv _readTlv(Uint8List b, int offset, [int? limit]) {
  final end = limit ?? b.length;
  if (offset + 2 > end) throw const DerFormatException('Truncated DER');
  final tag = b[offset];
  var lenByte = b[offset + 1];
  var pos = offset + 2;
  int length;
  if (lenByte < 0x80) {
    length = lenByte;
  } else {
    final n = lenByte & 0x7f;
    if (n == 0 || n > 3 || pos + n > end) {
      throw const DerFormatException('Unsupported DER length');
    }
    length = 0;
    for (var i = 0; i < n; i++) {
      length = (length << 8) | b[pos + i];
    }
    pos += n;
  }
  if (pos + length > end) throw const DerFormatException('Truncated DER');
  return _Tlv(tag, pos, pos + length);
}

bool _bytesEqual(Uint8List a, int start, int end, List<int> expected) {
  if (end - start != expected.length) return false;
  for (var i = 0; i < expected.length; i++) {
    if (a[start + i] != expected[i]) return false;
  }
  return true;
}

/// Encodes an uncompressed P-256 point (65 bytes, 0x04 prefix) as SPKI DER.
Uint8List encodeP256Spki(Uint8List uncompressedPoint) {
  if (uncompressedPoint.length != 65 || uncompressedPoint[0] != 0x04) {
    throw const DerFormatException('Expected 65-byte uncompressed P-256 point');
  }
  return Uint8List.fromList([...p256SpkiPrefix, ...uncompressedPoint]);
}

/// Accepts either SPKI DER (Android `getEncoded()`, OpenSSL `-pubout`) or a
/// raw 65-byte X9.63 point (iOS `SecKeyCopyExternalRepresentation`) and
/// returns the 65-byte uncompressed point. Rejects anything other than a
/// named-curve P-256 key.
Uint8List parseP256PublicKey(Uint8List input) {
  if (input.length == 65 && input[0] == 0x04) {
    return Uint8List.fromList(input);
  }
  final outer = _readTlv(input, 0);
  if (outer.tag != 0x30 || outer.valueEnd != input.length) {
    throw const DerFormatException('Not an SPKI sequence');
  }
  final alg = _readTlv(input, outer.valueStart, outer.valueEnd);
  if (alg.tag != 0x30) throw const DerFormatException('Missing algorithm');
  final oid1 = _readTlv(input, alg.valueStart, alg.valueEnd);
  if (oid1.tag != 0x06 ||
      !_bytesEqual(input, oid1.valueStart, oid1.valueEnd, _oidEcPublicKey)) {
    throw const DerFormatException('Not an EC public key');
  }
  final oid2 = _readTlv(input, oid1.valueEnd, alg.valueEnd);
  if (oid2.tag != 0x06 ||
      !_bytesEqual(input, oid2.valueStart, oid2.valueEnd, _oidPrime256v1)) {
    throw const DerFormatException('Not a P-256 key');
  }
  final bits = _readTlv(input, alg.valueEnd, outer.valueEnd);
  if (bits.tag != 0x03 || bits.length != 66 || input[bits.valueStart] != 0) {
    throw const DerFormatException('Unexpected public key bit string');
  }
  final point = Uint8List.sublistView(
    input,
    bits.valueStart + 1,
    bits.valueEnd,
  );
  if (point[0] != 0x04) {
    throw const DerFormatException('Only uncompressed points are supported');
  }
  return Uint8List.fromList(point);
}

/// Parses an ASN.1 DER ECDSA signature (SEQUENCE { INTEGER r, INTEGER s }),
/// the format produced by Android `SHA256withECDSA`, iOS
/// `ecdsaSignatureMessageX962SHA256` and OpenSSL.
({BigInt r, BigInt s}) parseDerEcdsaSignature(Uint8List der) {
  final seq = _readTlv(der, 0);
  if (seq.tag != 0x30 || seq.valueEnd != der.length) {
    throw const DerFormatException('Not a DER signature');
  }
  final r = _readTlv(der, seq.valueStart, seq.valueEnd);
  final s = _readTlv(der, r.valueEnd, seq.valueEnd);
  if (r.tag != 0x02 || s.tag != 0x02 || s.valueEnd != seq.valueEnd) {
    throw const DerFormatException('Malformed DER signature');
  }
  return (
    r: bytesToBigInt(Uint8List.sublistView(der, r.valueStart, r.valueEnd)),
    s: bytesToBigInt(Uint8List.sublistView(der, s.valueStart, s.valueEnd)),
  );
}

/// Encodes r and s as an ASN.1 DER ECDSA signature.
Uint8List encodeDerEcdsaSignature(BigInt r, BigInt s) {
  List<int> intTlv(BigInt v) {
    var bytes = bigIntToBytes(v, 32).toList();
    while (bytes.length > 1 && bytes[0] == 0 && bytes[1] < 0x80) {
      bytes = bytes.sublist(1);
    }
    if (bytes[0] >= 0x80) bytes = [0, ...bytes];
    return [0x02, bytes.length, ...bytes];
  }

  final body = [...intTlv(r), ...intTlv(s)];
  return Uint8List.fromList([0x30, body.length, ...body]);
}

/// SEC1 / RFC 5915 `EC PRIVATE KEY` for P-256, including curve parameters and
/// public key, so OpenSSL can read it (`openssl ec -in issuer.pem -text`).
Uint8List encodeP256Sec1PrivateKey(Uint8List d32, Uint8List point65) {
  if (d32.length != 32 || point65.length != 65) {
    throw const DerFormatException('Bad P-256 private key material');
  }
  return Uint8List.fromList([
    0x30, 0x77, 0x02, 0x01, 0x01, 0x04, 0x20, ...d32, //
    0xa0, 0x0a, 0x06, 0x08, ..._oidPrime256v1,
    0xa1, 0x44, 0x03, 0x42, 0x00, ...point65,
  ]);
}

/// Parses a P-256 private key from SEC1 (`EC PRIVATE KEY`) or PKCS#8
/// (`PRIVATE KEY`) DER and returns the 32-byte scalar.
Uint8List parseP256PrivateKey(Uint8List der) {
  final outer = _readTlv(der, 0);
  if (outer.tag != 0x30) throw const DerFormatException('Not a key sequence');
  final version = _readTlv(der, outer.valueStart, outer.valueEnd);
  if (version.tag != 0x02 || version.length != 1) {
    throw const DerFormatException('Missing key version');
  }
  final next = _readTlv(der, version.valueEnd, outer.valueEnd);
  if (der[version.valueStart] == 1 && next.tag == 0x04) {
    // SEC1: version 1, OCTET STRING privateKey, [0] params, [1] public key.
    if (next.length != 32) throw const DerFormatException('Bad scalar size');
    var pos = next.valueEnd;
    while (pos < outer.valueEnd) {
      final opt = _readTlv(der, pos, outer.valueEnd);
      if (opt.tag == 0xa0) {
        final oid = _readTlv(der, opt.valueStart, opt.valueEnd);
        if (!_bytesEqual(der, oid.valueStart, oid.valueEnd, _oidPrime256v1)) {
          throw const DerFormatException('Not a P-256 key');
        }
      }
      pos = opt.valueEnd;
    }
    return Uint8List.fromList(der.sublist(next.valueStart, next.valueEnd));
  }
  if (der[version.valueStart] == 0 && next.tag == 0x30) {
    // PKCS#8: version 0, AlgorithmIdentifier, OCTET STRING { SEC1 }.
    final oid1 = _readTlv(der, next.valueStart, next.valueEnd);
    final oid2 = _readTlv(der, oid1.valueEnd, next.valueEnd);
    if (!_bytesEqual(der, oid1.valueStart, oid1.valueEnd, _oidEcPublicKey) ||
        !_bytesEqual(der, oid2.valueStart, oid2.valueEnd, _oidPrime256v1)) {
      throw const DerFormatException('Not a P-256 PKCS#8 key');
    }
    final inner = _readTlv(der, next.valueEnd, outer.valueEnd);
    if (inner.tag != 0x04) throw const DerFormatException('Bad PKCS#8 body');
    return parseP256PrivateKey(
      Uint8List.fromList(der.sublist(inner.valueStart, inner.valueEnd)),
    );
  }
  throw const DerFormatException('Unsupported private key format');
}

String pemEncode(String label, Uint8List der) {
  final b64 = base64.encode(der);
  final lines = <String>[];
  for (var i = 0; i < b64.length; i += 64) {
    lines.add(b64.substring(i, i + 64 > b64.length ? b64.length : i + 64));
  }
  return '-----BEGIN $label-----\n${lines.join('\n')}\n-----END $label-----\n';
}

/// Decodes the first PEM block, or plain base64 if no PEM armour is present.
Uint8List pemOrBase64Decode(String text) {
  final match = RegExp(r'-----BEGIN ([A-Z ]+)-----([\s\S]*?)-----END \1-----')
      .firstMatch(text);
  final body = (match != null ? match.group(2)! : text).replaceAll(
    RegExp(r'\s'),
    '',
  );
  return base64.decode(body);
}

BigInt bytesToBigInt(List<int> bytes) {
  var result = BigInt.zero;
  for (final b in bytes) {
    result = (result << 8) | BigInt.from(b);
  }
  return result;
}

Uint8List bigIntToBytes(BigInt value, int length) {
  final out = Uint8List(length);
  var v = value;
  for (var i = length - 1; i >= 0; i--) {
    out[i] = (v & BigInt.from(0xff)).toInt();
    v = v >> 8;
  }
  if (v != BigInt.zero) throw ArgumentError('Value does not fit in $length');
  return out;
}
