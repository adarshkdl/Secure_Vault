# Agent Instructions --- Secure Credential Manager

## 1. Product overview

Build a cross-platform Flutter application named **Credential Manager**
(working title: **SecureVault**). It is an offline-first personal vault
for storing and organizing sensitive information such as email accounts,
website logins, static IP configurations, Wi-Fi credentials, server
access, databases, cloud accounts, software licences, and custom
records.

The product must make it easy to: - Browse records by category. -
Search, filter, favorite, add, view, edit, and delete records. - Reveal,
copy, and share selected fields. - Share records through WhatsApp or
other installed share targets, QR-based transfer, and encrypted
export. - Back up and restore the vault safely.

Treat this as a security-sensitive password manager, not as a general
notes app. Never trade security for convenience without an explicit,
informed user choice.

**Confirmed Version 1 decision:** Option B — offline local vault on each device, with manually transferred encrypted backup files for moving data between devices. No automatic cloud synchronization or mandatory account in Version 1. See Section 8 for required flows.

## 2. Primary product principles

1.  **Security first:** sensitive values are encrypted at rest and never
    logged.
2.  **Offline first:** the core app works without an account or network
    connection.
3.  **Simple information architecture:** categories, search, favorites,
    and recent records are easy to reach.
4.  **Flexible data model:** predefined categories have useful fields;
    users can also create categories and custom fields.
5.  **Explicit sharing:** users choose exactly what fields to share and
    see a warning before credentials leave the vault.
6.  **Accessible UI:** clear labels, readable contrast, touch-friendly
    controls, and support for system font scaling.

## 3. Recommended technology

-   Flutter and Dart; support current stable Android and iOS versions.
-   Use a layered architecture: presentation, application/use-cases,
    domain, and data.
-   Use Riverpod or another consistent state-management solution.
-   Use a maintained local database with encrypted storage. Evaluate
    SQLCipher-backed SQLite or an equivalent vetted encrypted database;
    do not assume ordinary SQLite is encrypted.
-   Use platform secure storage only for key material or wrapped
    encryption keys, not as a substitute for encrypting the entire data
    store.
-   Use Android Keystore and Apple Keychain through maintained
    packages/platform APIs.
-   Use a cryptographically secure random number generator and a vetted
    authenticated-encryption implementation.
-   Pin package versions and review package maintenance, permissions,
    and security posture before adoption.

Do not invent cryptography. Do not implement custom encryption
algorithms or key derivation.

## 4. Navigation and screens

Use a bottom navigation bar with: - **Home** - **Categories** -
**Favorites** - **Settings**

Search should be available from Home and category listings. A floating
action button or prominent Add action should be available on relevant
listing screens.

### 4.1 First launch and vault setup

-   Welcome/onboarding screen explaining local-first storage and the
    importance of the master password.
-   Create master password and confirm it.
-   Explain that a forgotten master password may make the vault
    unrecoverable unless the user has a valid recovery/backup method.
-   Offer biometric unlock only after the master password has been
    established.
-   Do not create a hidden default password or hard-code credentials.

### 4.2 Vault unlock

-   Master password entry.
-   Optional biometric unlock, with master-password fallback.
-   Rate-limit repeated failed attempts and use platform security
    controls where appropriate.
-   Auto-lock after the configured inactivity period and when the app is
    backgrounded, according to user settings.
-   Do not reveal record previews on the lock screen or in app-switcher
    snapshots.

### 4.3 Home dashboard

Show: - Greeting/title and vault lock status. - Global search. -
Category shortcuts with item counts. - Favorites and recently accessed
records. - Add credential action. - Optional security reminders, such as
weak or reused passwords, only if those checks can be performed locally
and safely.

### 4.4 Category listing

-   Display category name, icon, and record count.
-   Search within the category.
-   Sort by name, recently updated, or recently used.
-   Filter favorites.
-   Each record row/card should show a title, non-sensitive subtitle,
    category marker, and favorite state.
-   Never show a password or other secret in a list preview.

### 4.5 Credential details

-   Show title, category, and selected non-secret metadata.
-   Mask passwords, tokens, recovery codes, and other secret fields by
    default.
-   Provide explicit reveal/hide, copy, edit, favorite, share, and
    delete actions.
-   Require re-authentication for especially sensitive actions when
    configured.
-   Show created and last-updated timestamps.
-   Avoid exposing secrets in accessibility announcements when hidden.

### 4.6 Add/edit credential

-   Category-specific dynamic form.
-   Required-field validation and clear inline errors.
-   Password visibility toggle and optional password generator.
-   Add/remove custom fields.
-   Notes field.
-   Save and cancel actions; confirm discarding unsaved changes.
-   Editing must preserve fields not visible in the current form.
-   Warn before overwriting an existing record when duplicate detection
    finds a likely match.

### 4.7 Sharing and export

Provide separate flows for: 1. **Share selected fields:** user
explicitly selects fields; secrets are unchecked by default. 2.
**WhatsApp / system share sheet:** share only the user-approved payload.
Warn that the receiving app and recipient may retain it. 3. **QR
transfer:** prefer an encrypted, short-lived transfer payload with a
one-time session, expiry, and explicit receiver confirmation. Do not
encode plaintext passwords in a static QR code. If secure ephemeral
transfer cannot be implemented in the MVP, disable QR credential sharing
and explain why rather than shipping an unsafe implementation. 4.
**Encrypted export:** create an encrypted backup/export file protected
by a strong user-provided passphrase or a securely exchanged key.
Explain that the passphrase must be shared separately from the file. 5.
**Copy:** copy one chosen field only; clear the clipboard after a short
configurable interval where supported and warn that other apps may
access clipboard contents.

Sharing must never happen silently. Show a final preview of the exact
fields and destination before invoking the native share sheet.

### 4.8 Settings

-   Change master password.
-   Enable/disable biometric unlock.
-   Auto-lock timeout.
-   Clipboard clearing preference.
-   Theme: system/light/dark.
-   Backup and restore.
-   Import/export.
-   Security information and privacy explanation.
-   About, app version, and support information.
-   Clear vault / delete all data with strong confirmation and
    re-authentication.

## 5. Categories and suggested fields

Implement these built-in categories. Keep the schema extensible.

### Email account

-   Display name/provider
-   Email address (required)
-   Password
-   Recovery email
-   Recovery phone/account
-   Username (optional)
-   IMAP/POP/SMTP settings (optional advanced section)
-   Two-factor authentication notes or recovery-code reference (do not
    encourage storing the only copy of recovery codes in the same vault
    without warning)
-   Notes
-   Website URL

### Website login

-   Website/service name
-   URL
-   Username/email
-   Password
-   Recovery email/phone
-   Notes
-   Tags

### Static IP configuration

-   Configuration name/device
-   IP address
-   Subnet mask or CIDR prefix
-   Default gateway
-   DNS 1 and DNS 2
-   MAC address (optional)
-   VLAN (optional)
-   Location/device notes
-   Validate IP/CIDR formats; do not assume all networks use IPv4.

### Wi-Fi

-   Network/SSID
-   Password
-   Security type
-   Router/admin URL or IP
-   Notes

### Server / hosting

-   Name/environment
-   Hostname/IP
-   Port
-   Protocol/service
-   Username
-   Password or key reference
-   SSH key reference (avoid storing private keys in MVP unless secure
    key-file handling is designed)
-   Provider/URL
-   Notes

### Database

-   Name/environment
-   Engine
-   Host
-   Port
-   Database/schema
-   Username
-   Password
-   SSL/connection notes
-   Notes

### Social / cloud / application / licence

-   Service/provider
-   Account or licence identifier
-   Username/email
-   Password or secret key
-   Recovery information
-   Website URL
-   Expiry/renewal date where relevant
-   Notes

### Custom category

-   Name, icon, color, and user-defined fields.
-   Field types: short text, long text, email, URL, phone, username,
    password/secret, date, number, IP address, and boolean.
-   Each field must support a sensitivity setting so secrets are masked
    and encrypted appropriately.

## 6. Data model

Use stable IDs (UUIDs) and timestamps. Suggested conceptual entities:

### Credential

-   id
-   categoryId
-   title
-   fields: ordered list/map of field definitions and encrypted values
-   notes (encrypted)
-   tags
-   isFavorite
-   createdAt
-   updatedAt
-   lastAccessedAt
-   deletedAt (optional soft-delete/tombstone if required for safe
    backup sync)

### Category

-   id
-   name
-   iconKey
-   colorKey
-   isBuiltIn
-   sortOrder
-   customFieldDefinitions

### Field definition

-   id
-   key
-   label
-   type
-   isRequired
-   isSensitive
-   sortOrder
-   validation rules

Encrypt sensitive values and notes. Prefer encrypting the full record
payload, including titles and metadata, where practical, because account
names and server addresses can themselves be sensitive. Keep only the
minimum metadata outside encryption needed for app operation.

## 7. Security requirements --- non-negotiable

-   Encrypt vault data at rest using a vetted authenticated-encryption
    scheme.
-   Derive keys from the master password using a memory-hard password
    KDF such as Argon2id where available, with parameters selected for
    supported devices; use a vetted alternative such as scrypt or PBKDF2
    only when platform constraints require it and document the
    trade-off.
-   Use a unique random salt per vault and unique nonces/IVs as required
    by the selected encryption scheme.
-   Store key material or wrapped keys in Android Keystore / Apple
    Keychain; never hard-code keys.
-   Separate authentication from encryption design. Biometric unlock
    should release a protected key or key-encryption key through
    platform APIs, not replace the master-password security model.
-   Do not store the master password. Clear password/key material from
    memory as far as the platform/runtime permits after use.
-   Never log secrets, request bodies containing secrets, decrypted
    database rows, or share payloads.
-   Exclude secrets from analytics, crash reports, notifications,
    screenshots, and debug output.
-   Disable Android backups of raw vault/key material unless a
    deliberately designed encrypted backup process is used.
-   Protect app-switcher previews and sensitive screens from
    screenshots/recording where supported; explain platform limitations.
-   Re-authenticate before master-password change, full export,
    destructive actions, and optionally before revealing/copying
    secrets.
-   Use secure random IDs and avoid predictable share tokens.
-   Add clipboard warnings and automatic clearing where supported.
-   Use dependency scanning and security review before release.
-   Provide a clear warning that no app can prevent a recipient from
    photographing, copying, or redistributing information once it has
    been shared.

## 8. Confirmed Version 1 architecture decision: Option B

**Decision: support multiple devices through manually transferred encrypted backup files.** Version 1 has no automatic cloud synchronization and does not require a user account.

- Each device maintains its own local encrypted vault.
- The user explicitly creates an encrypted backup file from the Backup & Restore screen.
- Encrypt the backup before writing it to a shareable destination. Never create a plaintext intermediate export.
- The user may transfer the encrypted file using WhatsApp, USB, AirDrop, Google Drive, or another file-transfer method. The app does not upload it automatically.
- Protect the backup with a separate strong backup passphrase. Do not reuse or silently derive it from the master password.
- Tell the user to send the backup passphrase through a different channel from the backup file. Never attach the passphrase to the file or include it in the same share message.
- Restore must validate file structure, format version, integrity, and authentication before importing data.
- Restore must not merge or overwrite an existing vault silently. Require explicit confirmation and re-authentication before replacement; recommend creating a fresh backup first.
- Include encrypted credential data, category/custom-field definitions, favorites, tags, and required schema/version metadata. Do not include device-bound Keychain/Keystore secrets.
- Use a versioned authenticated backup format, unique random salt and nonce/IV as required by the vetted encryption scheme, and integrity verification before import.
- Handle wrong passphrase, corrupted/unsupported files, incomplete transfers, insufficient storage, and interrupted restore without partially replacing the active vault.
- Cloud storage may be used by the user as a file-transfer destination, but the app must not access or sync cloud accounts in Version 1.

### 8.1 Backup flow
1. User unlocks the vault and opens Settings → Backup & Restore → Create Backup.
2. Explain that the backup contains sensitive data and will be encrypted locally.
3. User creates and confirms a strong backup passphrase; show strength guidance.
4. App serializes the vault into the versioned backup format and encrypts it before writing the output file.
5. App verifies the completed file and opens the native share/save sheet.
6. Show a reminder to keep the passphrase separate from the backup file.

### 8.2 Restore flow
1. User opens Restore from Backup and selects a file using the system file picker.
2. App validates file structure and supported version, then requests the backup passphrase.
3. App authenticates/decrypts into a temporary isolated staging area; do not modify the active vault yet.
4. Show safe metadata such as backup creation date and record count, without displaying secrets.
5. User confirms replacement. Require re-authentication if an existing vault will be replaced.
6. Commit restore atomically; if any step fails, retain the existing vault unchanged.
7. Ask the user to set or confirm the destination device's master-password/biometric setup. Never copy device-bound keychain/keystore secrets from the source device.

### 8.3 Multi-device expectations and limitations
- Manual backup transfer is a snapshot workflow, not live synchronization.
- Changes made on one device are not reflected on another until a new backup is created and restored.
- Explain that restoring a newer backup may replace newer local changes on the destination device.
- Do not implement automatic conflict resolution or background sync in Version 1.
- Losing both the vault and its valid backup passphrase can make the backup unrecoverable.

## 9. Search, sorting, and usability

-   Search by title, username/email, URL, category, and tags.
-   For encrypted fields, choose a deliberate privacy-preserving search
    strategy. Do not create plaintext search indexes of secrets. If
    searchable indexing is implemented, document exactly what metadata
    is exposed.
-   Support category filters, favorites, and sorting.
-   Confirm deletion and provide a recoverable Recently Deleted area if
    it can be implemented without weakening security.
-   Include empty states, loading states, error states, and helpful
    validation.
-   Support accessibility labels, large text, and screen readers.

## 10. Visual design direction

Use a modern, calm, trustworthy interface: - Primary palette: deep blue
with white/light neutral surfaces; provide a proper dark theme. - Use
distinct but consistent category icons. - Use cards or compact rows with
clear hierarchy. - Keep Add, Search, Favorite, Reveal, Copy, Edit,
Delete, and Share actions easy to discover. - Use masked values and eye
icons for secret fields. - Avoid visual clutter and avoid showing
sensitive data in dashboard previews. - Use consistent spacing,
typography, corner radius, and button hierarchy. - Design for common
Android and iPhone screen sizes and safe areas.

## 11. Functional acceptance criteria

The first release is acceptable only when: - A user can create and
unlock a vault with a master password. - A user can add, view, edit,
favorite, search, filter, and delete credentials. - Built-in categories
and custom categories work. - Category-specific forms validate and
preserve their data. - Secret fields are masked by default and encrypted
at rest. - The app locks according to the configured timeout. - The user
can export and restore an encrypted backup. - Sharing requires field
selection and a confirmation preview. - No plaintext secret appears in
logs, list previews, notifications, or analytics. - QR sharing is either
implemented as an encrypted, expiring transfer or intentionally disabled
until it can be safe. - Database migrations and backup/restore are
tested. - Core flows work offline.

## 12. Testing requirements

Create unit, widget, integration, and security-focused tests for: -
Master-password setup, unlock, incorrect password, and lockout/rate
limiting. - Encryption/decryption and tamper detection. -
Add/edit/delete and category-specific validation. - Custom fields and
schema migrations. - Search, favorites, and filters. - Auto-lock and
background/foreground transitions. - Clipboard clearing behavior. -
Share-field selection and preview. - Encrypted backup, wrong passphrase,
corrupted file, and restore. - QR expiry and one-time-use behavior if QR
transfer is implemented. - Android and iOS platform-specific
secure-storage behavior.

Use synthetic test credentials only. Never use real personal passwords
in screenshots, fixtures, tests, or sample data.

## 13. Suggested delivery phases

### Phase 1 --- Secure local MVP

-   Vault setup/unlock
-   Encrypted local storage
-   Categories and custom fields
-   Dashboard, listing, details, add/edit/delete
-   Search, favorites, auto-lock
-   Encrypted local backup and restore

### Phase 2 --- Safe sharing and usability

-   Field-level share selection
-   Native share sheet / WhatsApp integration
-   Encrypted QR transfer with expiry and one-time use
-   Password generator and strength feedback
-   Clipboard clearing and recent activity

### Phase 3 --- Advanced features

-   Optional end-to-end encrypted sync
-   Import from supported password managers
-   Expiry reminders
-   Security audit/report
-   Additional platform integrations

## 14. Agent working instructions

Before implementation: 1. Inspect the existing repository and report its
current framework, structure, dependencies, and conventions. 2. Do not
replace or restructure working code without explaining why. 3. Produce a
concise implementation plan and identify security-sensitive decisions.
4. Confirm the encryption/database approach and package maintenance
before coding.

During implementation: 1. Build reusable components and category-driven
forms. 2. Keep business logic out of widgets. 3. Add tests alongside
each feature. 4. Use synthetic sample data only. 5. Do not claim a
security feature is implemented until its behavior is tested. 6. Do not
implement unsafe plaintext QR or sharing as a temporary shortcut. 7.
Keep README and setup instructions current.

At completion: 1. Run formatter, static analysis, and all relevant
tests. 2. Report implemented features, known limitations, package
choices, and commands used. 3. Provide manual test steps for Android and
iOS. 4. List any security items that still require review.

**Important:** This file is a product and implementation brief, not a
substitute for a professional security review. A credential vault should
receive a threat-model review and independent security testing before
storing real credentials.
