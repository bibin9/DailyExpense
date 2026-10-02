import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:bcr_activation/bcr_activation.dart';

/// Daily Expense Tracker admin utility — BCR.
///
/// Issuer private keys live OUTSIDE the repository, by default in
/// `<home>/.bcr-det/issuers/`. Never copy them into the project or the app.

const usage = '''
det_admin — Daily Expense Tracker activation utility (BCR)

Commands:
  init-issuer   --client <id> [--dir <issuer-dir>]
                Create a new issuer key pair for a client. Refuses to overwrite.
  write-config  --client <id> --name "<Client display name>" --out <file.json>
                [--dir <issuer-dir>]
                Write the app build config (client id, name, issuer PUBLIC key).
  sign          --client <id> --request <DETREQ1:...> [--label "<phone label>"]
                [--expires-days <n>] [--dir <issuer-dir>]
                Sign an activation request and print the activation token.
  verify        --client <id> --token <token> [--request <DETREQ1:...>]
                [--dir <issuer-dir>]
                Check a token against the issuer public key (and a request).
  public-key    --client <id> [--dir <issuer-dir>]
                Print the issuer public key (base64 SPKI DER).

Default issuer dir: <home>/.bcr-det/issuers   (override with --dir or BCR_DET_ISSUER_DIR)
''';

class CliException implements Exception {
  CliException(this.message, [this.exitCode = 64]);
  final String message;
  final int exitCode;
  @override
  String toString() => message;
}

Map<String, String> parseOptions(List<String> args) {
  final out = <String, String>{};
  for (var i = 0; i < args.length; i++) {
    final a = args[i];
    if (!a.startsWith('--')) throw CliException('Unexpected argument "$a"');
    if (i + 1 >= args.length) throw CliException('Missing value for $a');
    out[a.substring(2)] = args[++i];
  }
  return out;
}

String defaultIssuerDir(Map<String, String> env) {
  final override = env['BCR_DET_ISSUER_DIR'];
  if (override != null && override.isNotEmpty) return override;
  final home = env['USERPROFILE'] ?? env['HOME'];
  if (home == null) throw CliException('Cannot find home directory; use --dir');
  return '$home${Platform.pathSeparator}.bcr-det${Platform.pathSeparator}issuers';
}

String _req(Map<String, String> o, String key) {
  final v = o[key];
  if (v == null || v.trim().isEmpty) throw CliException('--$key is required');
  return v.trim();
}

class Admin {
  Admin({required this.out, Map<String, String>? env, DateTime Function()? now})
    : env = env ?? Platform.environment,
      now = now ?? DateTime.now;

  final StringSink out;
  final Map<String, String> env;
  final DateTime Function() now;

  File _privFile(String dir, String client) =>
      File('$dir${Platform.pathSeparator}$client.issuer.key.pem');
  File _pubFile(String dir, String client) =>
      File('$dir${Platform.pathSeparator}$client.issuer.pub.pem');
  File _logFile(String dir, String client) =>
      File('$dir${Platform.pathSeparator}$client.issued.csv');

  String _client(Map<String, String> o) {
    final c = _req(o, 'client').toLowerCase();
    if (!isValidClientId(c)) {
      throw CliException(
        'Client id must be 3-48 chars: lower-case letters, digits, hyphens',
      );
    }
    return c;
  }

  P256KeyPair _loadIssuer(String dir, String client) {
    final f = _privFile(dir, client);
    if (!f.existsSync()) {
      throw CliException('No issuer key for "$client" at ${f.path}', 66);
    }
    return P256KeyPair.fromPrivateScalar(
      parseP256PrivateKey(pemOrBase64Decode(f.readAsStringSync())),
    );
  }

  int run(List<String> args) {
    if (args.isEmpty || args.first == 'help' || args.first == '--help') {
      out.write(usage);
      return args.isEmpty ? 64 : 0;
    }
    final o = parseOptions(args.sublist(1));
    final dir = o['dir'] ?? defaultIssuerDir(env);
    switch (args.first) {
      case 'init-issuer':
        return _initIssuer(dir, _client(o));
      case 'write-config':
        return _writeConfig(dir, _client(o), _req(o, 'name'), _req(o, 'out'));
      case 'sign':
        return _sign(dir, _client(o), o);
      case 'verify':
        return _verify(dir, _client(o), o);
      case 'public-key':
        final issuer = _loadIssuer(dir, _client(o));
        out.writeln(base64.encode(issuer.spki));
        return 0;
      default:
        throw CliException('Unknown command "${args.first}"\n\n$usage');
    }
  }

  int _initIssuer(String dir, String client) {
    final priv = _privFile(dir, client);
    if (priv.existsSync()) {
      throw CliException(
        'Issuer key already exists at ${priv.path}. Refusing to overwrite: '
        'replacing it would invalidate every phone activated for $client.',
        73,
      );
    }
    Directory(dir).createSync(recursive: true);
    final pair = P256KeyPair.generate(Random.secure());
    priv.writeAsStringSync(
      pemEncode(
        'EC PRIVATE KEY',
        encodeP256Sec1PrivateKey(pair.privateScalar, pair.publicPoint),
      ),
      flush: true,
    );
    _pubFile(
      dir,
      client,
    ).writeAsStringSync(pemEncode('PUBLIC KEY', pair.spki), flush: true);
    if (!Platform.isWindows) {
      Process.runSync('chmod', ['600', priv.path]);
    }
    out
      ..writeln('Created issuer key for "$client"')
      ..writeln('  PRIVATE (keep secret, back up offline): ${priv.path}')
      ..writeln('  public:  ${_pubFile(dir, client).path}')
      ..writeln('  public key (base64 SPKI): ${base64.encode(pair.spki)}')
      ..writeln()
      ..writeln(
        'Next: det_admin write-config --client $client '
        '--name "<Client name>" --out config/clients/$client.json',
      );
    return 0;
  }

  int _writeConfig(String dir, String client, String name, String outPath) {
    final issuer = _loadIssuer(dir, client);
    final config = {
      'DET_CLIENT_ID': client,
      'DET_CLIENT_NAME': name.trim(),
      'DET_ISSUER_PUBLIC_KEY': base64.encode(issuer.spki),
    };
    File(outPath)
      ..createSync(recursive: true)
      ..writeAsStringSync(
        '${const JsonEncoder.withIndent('  ').convert(config)}\n',
      );
    out.writeln('Wrote $outPath (contains only the PUBLIC key).');
    return 0;
  }

  int _sign(String dir, String client, Map<String, String> o) {
    final request = ActivationRequest.parse(_req(o, 'request'));
    if (request.clientId != client) {
      throw CliException(
        'Request is for client "${request.clientId}", not "$client". '
        'Was it made with a different client build?',
      );
    }
    final issuer = _loadIssuer(dir, client);
    final days = o['expires-days'];
    final issuedAt = now().toUtc();
    DateTime? exp;
    if (days != null) {
      final n = int.tryParse(days);
      if (n == null || n < 1 || n > 3650) {
        throw CliException('--expires-days must be 1..3650');
      }
      exp = issuedAt.add(Duration(days: n));
    }
    final rnd = Random.secure();
    final jti = base32Encode(List.generate(10, (_) => rnd.nextInt(256)));
    final label = o['label']?.trim();
    if (label != null && label.length > 60) {
      throw CliException('--label must be at most 60 characters');
    }
    final token = signActivationToken(
      ActivationClaims(
        clientId: client,
        fingerprint: request.fingerprint,
        issuedAt: issuedAt,
        expiresAt: exp,
        label: label,
        tokenId: jti,
      ),
      issuer,
    );
    // Self-check with the public key before handing the token out.
    final check = verifyActivationToken(
      token: token,
      issuerPublicKey: issuer.spki,
      expectedClientId: client,
      deviceFingerprint: request.fingerprint,
      now: issuedAt,
    );
    if (!check.isValid) {
      throw CliException('Self-check failed: ${check.status}', 70);
    }

    final log = _logFile(dir, client);
    if (!log.existsSync()) {
      log.writeAsStringSync(
        'issued_at_utc,token_id,fingerprint,label,expires_at_utc\n',
      );
    }
    String csv(String? v) => '"${(v ?? '').replaceAll('"', '""')}"';
    log.writeAsStringSync(
      '${issuedAt.toIso8601String()},$jti,${request.fingerprint},'
      '${csv(label)},${exp?.toIso8601String() ?? ''}\n',
      mode: FileMode.append,
    );
    out
      ..writeln('Activation token (send this to the phone user):')
      ..writeln()
      ..writeln(token)
      ..writeln()
      ..writeln('Bound to fingerprint ${groupForDisplay(request.fingerprint)}')
      ..writeln(exp == null ? 'No expiry.' : 'Expires ${exp.toIso8601String()}')
      ..writeln('Logged in ${log.path}');
    return 0;
  }

  int _verify(String dir, String client, Map<String, String> o) {
    final issuer = _loadIssuer(dir, client);
    final token = _req(o, 'token');
    final reqText = o['request'];
    String fp;
    if (reqText != null) {
      fp = ActivationRequest.parse(reqText).fingerprint;
    } else {
      final parts = token.split('.');
      if (parts.length != 3) throw CliException('Malformed token', 65);
      final payload = jsonDecode(
        utf8.decode(base64UrlDecodeLenient(parts[1])),
      ) as Map<String, Object?>;
      fp = (payload['fp'] as String?) ?? '';
    }
    final check = verifyActivationToken(
      token: token,
      issuerPublicKey: Uint8List.fromList(issuer.spki),
      expectedClientId: client,
      deviceFingerprint: fp,
      now: now().toUtc(),
    );
    out.writeln('Status: ${check.status.name}');
    final c = check.claims;
    if (c != null) {
      out
        ..writeln('  client:      ${c.clientId}')
        ..writeln('  fingerprint: ${groupForDisplay(c.fingerprint)}')
        ..writeln('  issued:      ${c.issuedAt.toIso8601String()}')
        ..writeln('  expires:     ${c.expiresAt?.toIso8601String() ?? 'never'}')
        ..writeln('  label:       ${c.label ?? '-'}');
    }
    return check.isValid ? 0 : 1;
  }
}
