import 'dart:convert';
import 'dart:typed_data';

import 'der.dart';
import 'p256.dart';

const _b32Alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';

/// RFC 4648 base32, upper case, no padding.
String base32Encode(List<int> data) {
  final out = StringBuffer();
  var buffer = 0;
  var bits = 0;
  for (final byte in data) {
    buffer = (buffer << 8) | byte;
    bits += 8;
    while (bits >= 5) {
      out.write(_b32Alphabet[(buffer >> (bits - 5)) & 31]);
      bits -= 5;
    }
  }
  if (bits > 0) out.write(_b32Alphabet[(buffer << (5 - bits)) & 31]);
  return out.toString();
}

Uint8List base32Decode(String input) {
  final clean = input.toUpperCase().replaceAll(RegExp(r'[\s\-=]'), '');
  final out = <int>[];
  var buffer = 0;
  var bits = 0;
  for (final ch in clean.split('')) {
    final v = _b32Alphabet.indexOf(ch);
    if (v < 0) throw FormatException('Invalid character "$ch"');
    buffer = (buffer << 5) | v;
    bits += 5;
    if (bits >= 8) {
      out.add((buffer >> (bits - 8)) & 0xff);
      bits -= 8;
    }
  }
  return Uint8List.fromList(out);
}

String base64UrlNoPad(List<int> data) =>
    base64Url.encode(data).replaceAll('=', '');

Uint8List base64UrlDecodeLenient(String s) =>
    base64Url.decode(base64Url.normalize(s.trim()));

/// SHA-256 over the canonical SPKI DER of an installation public key,
/// base32-encoded (52 characters). Accepts SPKI or a raw point so Android and
/// iOS produce the same fingerprint for the same key.
String installationFingerprint(Uint8List publicKey) {
  final point = parseP256PublicKey(publicKey);
  decodeValidatedP256Point(point);
  return base32Encode(sha256(encodeP256Spki(point)));
}

/// Groups a fingerprint for display: ABCD-EFGH-…
String groupForDisplay(String code, {int size = 4}) {
  final parts = <String>[];
  for (var i = 0; i < code.length; i += size) {
    parts.add(
      code.substring(i, i + size > code.length ? code.length : i + size),
    );
  }
  return parts.join('-');
}

final _clientIdPattern = RegExp(r'^[a-z0-9][a-z0-9\-]{1,46}[a-z0-9]$');

bool isValidClientId(String id) => _clientIdPattern.hasMatch(id);

/// What a phone shows and the administrator signs:
/// `DETREQ1:<client-id>:<fingerprint>:<check>`
///
/// The check is 4 base32 chars of SHA-256 over the rest, so the admin
/// utility catches copy/typing mistakes before signing.
class ActivationRequest {
  ActivationRequest({required this.clientId, required this.fingerprint}) {
    if (!isValidClientId(clientId)) {
      throw FormatException('Invalid client id "$clientId"');
    }
    if (fingerprint.length != 52 || base32Decode(fingerprint).length != 32) {
      throw const FormatException('Fingerprint must be 52 base32 characters');
    }
  }

  static const prefix = 'DETREQ1';

  final String clientId;
  final String fingerprint;

  static String _check(String clientId, String fingerprint) =>
      base32Encode(sha256(utf8.encode('$prefix:$clientId:$fingerprint')))
          .substring(0, 4);

  String encode() =>
      '$prefix:$clientId:$fingerprint:${_check(clientId, fingerprint)}';

  static ActivationRequest parse(String text) {
    final parts = text.trim().replaceAll(RegExp(r'\s'), '').split(':');
    if (parts.length != 4 || parts[0].toUpperCase() != prefix) {
      throw const FormatException(
        'Not a Daily Expense Tracker request code (expected DETREQ1:…)',
      );
    }
    final clientId = parts[1].toLowerCase();
    final fp = parts[2].toUpperCase().replaceAll('-', '');
    final req = ActivationRequest(clientId: clientId, fingerprint: fp);
    if (_check(clientId, fp) != parts[3].toUpperCase()) {
      throw const FormatException(
        'Request code check failed — it was probably mistyped or cut off',
      );
    }
    return req;
  }
}
