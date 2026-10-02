# Offline activation

Activation makes sure only phones approved by the administrator can use an unmodified copy of the app. It works with no internet on either side.

## How it works

```
Phone                                   Administrator (det_admin on a PC)
-----                                   ---------------------------------
1. Creates a P-256 key pair inside
   Android Keystore / iOS Secure Enclave
   (private key cannot be exported)
2. Shows request code ───────────────►  3. det_admin sign --request DETREQ1:…
   DETREQ1:<client>:<fingerprint>:<chk>     signs with the client's ISSUER private key
                          ◄───────────────  4. Activation code (ES256 JWS) sent back
5. Verifies signature with the embedded
   issuer PUBLIC key, client id and
   fingerprint, then signs a random
   challenge with its private key to prove
   the bound key is really on this phone.
6. Stores the token in the encrypted DB.
   Steps 5 (verify + proof) repeat on every start.
```

The request code and activation code can be sent by any channel (WhatsApp, email, paper). They contain no expense data and no personal data — only the client id and a hash of a public key.

## Formats (interoperable)

| Item | Format |
|---|---|
| Algorithm | ECDSA NIST P-256 with SHA-256 (JOSE `ES256`) for both the issuer and the installation keys |
| Installation fingerprint | SHA-256 of the installation public key as SubjectPublicKeyInfo DER, base32 (RFC 4648, no padding, 52 chars) |
| Request code | `DETREQ1:<client-id>:<fingerprint>:<check>`; check = first 4 base32 chars of SHA-256 of the preceding text (catches typos) |
| Activation code | JWS compact: `base64url(header).base64url(payload).base64url(r‖s)`; header `{"alg":"ES256","typ":"det-activation"}`; payload `{"v":1,"cid","fp","iat","exp"?,"lbl"?,"jti"}`. Only `ES256` is accepted. |
| Issuer private key | PEM `EC PRIVATE KEY` (SEC1 / RFC 5915, named curve prime256v1). PKCS#8 `PRIVATE KEY` from OpenSSL is also accepted. |
| Issuer public key | PEM `PUBLIC KEY` (SPKI) on disk; base64 SPKI DER in `config/clients/<client>.json` as `DET_ISSUER_PUBLIC_KEY` |
| Platform signatures | DER ECDSA (Android `SHA256withECDSA`, iOS `ecdsaSignatureMessageX962SHA256`, OpenSSL) |

Interop was tested with OpenSSL 3.2.4: OpenSSL reads det_admin keys, verifies det_admin signatures, and det_admin verifies OpenSSL signatures and reads OpenSSL PKCS#8 keys.

## Admin utility (`admin_cli/`)

Run from the repository root (Dart SDK from Flutter is enough):

```bash
dart run admin_cli/bin/det_admin.dart help
```

| Command | Purpose |
|---|---|
| `init-issuer --client insideout-casa` | Create the client's issuer key pair. Refuses to overwrite. |
| `write-config --client insideout-casa --name "InsideOut Casa" --out config/clients/insideout-casa.json` | Write the app build config (public key only). |
| `sign --client insideout-casa --request "DETREQ1:…" --label "Driver – Ahmed" [--expires-days 365]` | Print an activation code; appends to `<client>.issued.csv`. |
| `verify --client insideout-casa --token "<code>" [--request "DETREQ1:…"]` | Check a code. |
| `public-key --client insideout-casa` | Print the base64 public key. |

Issuer keys are stored **outside the repository**, by default in `%USERPROFILE%\.bcr-det\issuers\` (Windows) or `~/.bcr-det/issuers/` (macOS/Linux); override with `--dir` or `BCR_DET_ISSUER_DIR`.

### Keys created on 2026-10-02

| Client id | Purpose | Private key location |
|---|---|---|
| `bcr-dev` | Development/testing only (`config/clients/dev.json`) | `C:\Users\Internet\.bcr-det\issuers\bcr-dev.issuer.key.pem` |
| `insideout-casa` | InsideOut Casa builds | `C:\Users\Internet\.bcr-det\issuers\insideout-casa.issuer.key.pem` |

**Protect the issuer private key.**
- Anyone holding it can activate unlimited phones for that client. Keep it on an admin PC only and never put it in the repo, the app, email or chat.
- Back it up offline (for example an encrypted USB stick kept in a safe).
- If it is lost, already-activated phones keep working, but new phones can only be activated after a new key is created and a new app build is installed everywhere.
- If you would rather generate the production key on a dedicated admin machine, do that **before the first release**: delete the PC copy, run `init-issuer` there, re-run `write-config`, and rebuild.

## Typical procedure

1. The employee installs the app and opens it. After unlocking, the app shows **Activate this phone** with a request code. They tap **Copy request code** and send it to the administrator.
2. The administrator runs `det_admin sign …` and sends back the activation code.
3. The employee copies it, taps the paste icon and then **Activate**.

## Fresh install vs. upgrade

- **Upgrade** (same app id and signing key installed over the old one): app files stay, so the database, key and activation are kept. Nothing to do.
- **Fresh install / reinstall:** Android removes everything on uninstall. iOS removes app files but **may keep Keychain items**. The app spots a fresh install (no install marker and no database) and deletes leftover Keychain items, so it starts clean and asks for activation again.
- A token restored or copied onto another phone fails the proof-of-possession check, and the app asks for activation again.

## Limits — please read

- Activation stops casual use of an **unmodified** app on unapproved phones. It does **not** stop someone copying the APK, and it does **not** replace Apple's signing and provisioning requirements.
- It is **not tamper-proof** on rooted/jailbroken or otherwise compromised phones, or against someone who modifies and re-signs the app.
- It is fully offline, so there is **no instant remote revocation**. To limit exposure, use `--expires-days`; expired phones must be re-activated. Device clocks can be changed, so expiry is a soft control.
- No IMEI, advertising ID, phone number or online licensing service is used.
