# Data Dawn — Play Store and App Store Publishing Checklist

This checklist covers the required setup before publishing **Data Dawn** to Google Play and the Apple App Store. It is ordered as a real submission path: accounts → identity → legal → signing → store listing → review → rollout.

## 0. Locked-in identity (do not change after first upload)

| Field | Value | Why it is permanent |
|---|---|---|
| Display name | **Data Dawn** | Changeable, but pick it now — reviews reset on rename |
| Android package / application id | `com.datedawn.app` | Fixed forever once the first bundle is uploaded |
| iOS bundle identifier | `com.datedawn.app` | Fixed forever once the first build is uploaded |
| Firebase project | `datedawn` (number `255395342604`) | Baked into every build |
| URL scheme | `com.datedawn.app` | Referenced by sign-in deep links |

> **Why this matters:** Google Play and App Store Connect both reject a re-upload that changes the package/bundle id. If the id is wrong, the only fix is to publish a *new* app and migrate users. Confirm it is `com.datedawn.app` before the first upload.

## 1. Required accounts

### Google Play
- Google Play Console account ([play.google.com/console](https://play.google.com/console))
- One-time **$25** developer registration fee
- Identity verification (personal or organisation) — **this now takes days**, start it first
- For a *new personal* developer account: Google requires a **closed test with 12+ testers for 14 continuous days** before you may apply for production. Organisation accounts are exempt. Budget 2–3 weeks for this alone.

### App Store
- Apple Developer Program membership — **$99/year**
- Enrolment approval can take **24–48 hours** (longer for a new individual, which may need identity documents)
- App Store Connect access with the **Admin** or **App Manager** role

## 2. Required app metadata

### For both stores
- App name and description
- Icon set and splash assets
- Privacy policy URL (public, non-PDF, reachable without sign-in)
- Support URL
- Contact email
- App category
- Screenshots for each required device size
- Data safety / privacy disclosures

### Required for App Store
- App Privacy section must be completed
- Upload screenshot set for required iPhone/iPad sizes
- Apple Developer signing certificates and provisioning profiles
- **Demo account** for the reviewer (see §4) — a sign-in-only app is rejected without one
- **Account deletion** reachable inside the app (Apple hard requirement since 2022)

### Required for Play Store
- Data safety form
- Content rating questionnaire
- Target audience declaration
- App content declaration
- **Account deletion** URL or in-app path (Google requires this too)

## 3. Privacy policy and support — the website you need

Both stores require a **live public web page**, not a file in the repo. `PRIVACY_POLICY.md` in this repo is the source text; it must be published at a real URL, and `support@example.com` / `https://example.com` in it must be replaced with real values **before** submission — placeholder contacts are a common rejection.

You need three public URLs. The cheapest way to host all three is **GitHub Pages** (free) on the repo you already have:

1. Enable Pages: repo → **Settings → Pages** → Source: *Deploy from a branch* → `main` / `/docs`.
2. Your URLs become:
   - Privacy: `https://<username>.github.io/<repo>/PRIVACY_POLICY.html`
   - Support: `https://<username>.github.io/<repo>/SUPPORT.html`
   - Marketing/home: `https://<username>.github.io/<repo>/`

A support email alone is not sufficient for a **Paid** App Store app or for apps collecting data — Apple wants a URL where a user can get help. A one-page site with a short app description, a contact email and a couple of links is enough.

### What the policy must disclose for *this* app
- Firebase Authentication and Cloud Firestore as the data processors
- Google Sign-In, if enabled
- The exact data collected: name, email, event titles/descriptions/dates, circle membership, invitations, device push token
- Retention and deletion (what happens when a user deletes their account)
- **Data Safety form must match this policy.** Apple and Google both cross-check the policy against the questionnaire, and a mismatch is a rejection (Apple Guideline 5.1.1, Google's Data safety policy).

## 4. The sign-in wall (the most common rejection for this kind of app)

Data Dawn is **useless without an account**, so reviewers cannot see any feature. Both stores reject "login required, no demo access":

- **Apple** (Guideline 2.1 / 5.1.1): you must supply a demo account in App Store Connect → *App Review Information* → *Sign-in required*.
- **Google** (Play Console → App content): declare that sign-in is required and provide credentials.

**Action before submitting:** create a real `reviewer@datedawn.app`-style account, pre-populate it with 2–3 sample countdowns (including one shared/circle event so the collaborative features are visible), and put those credentials in both consoles. Do not rely on "Continue without an account" — check whether that path exposes enough of the app to be reviewable.

## 5. App signing and release build

### Android
1. Generate a release keystore (**do this once — losing it means you can never update the app**):
   ```powershell
   & "$env:LOCALAPPDATA\Android\Sdk\bin\keytool.exe" -genkey -v `
     -keystore $env:USERPROFILE\datedawn-upload.jks `
     -keyalg RSA -keysize 2048 -validity 10000 -alias upload
   ```
   Store the `.jks` **and its passwords** somewhere you will still have in five years (password manager + offline backup).
2. Create `android/key.properties` (already gitignored):
   ```
   storePassword=<password>
   keyPassword=<password>
   keyAlias=upload
   storeFile=C:/Users/Vi/datedawn-upload.jks
   ```
3. The release build currently signs with the **debug** key so CI can build without the keystore (`android/app/build.gradle.kts`). Before uploading, that `signingConfig = signingConfigs.getByName("debug")` must read the `key.properties` values — otherwise Play rejects the bundle.
4. Build and upload:
   ```powershell
   flutter build appbundle --release
   ```
   Output: `build/app/outputs/bundle/release/app-release.aab`
5. **Play App Signing**: Google re-signs your bundle with a key it holds. Your `.jks` becomes the *upload* key. This is the default and is recommended — accept it.

### iOS
1. Configure certificates and provisioning profiles in Xcode (or let `flutter build ipa` do it with automatic signing).
2. Bundle identifier must be `com.datedawn.app` (already set in `ios/Runner.xcodeproj/project.pbxproj`).
3. Enable capabilities: **Push Notifications** and **Background Modes → Remote notifications** if you ship reminders.
4. Archive and upload: `flutter build ipa --release` → open in **Transporter** or Xcode Organizer → upload to App Store Connect.
5. Wait for processing, then attach the build to a version and submit.

## 6. Screenshots

Both stores reject screenshots that show placeholder content, a simulator status bar, or a device frame that does not match the required size.

| Store | Requirement |
|---|---|
| App Store | 6.7" (iPhone 15/16 Pro Max) and 6.5" minimum; iPad if you ship iPad support |
| Play Store | At least 2 phone screenshots; 16:9 or 9:16 |

Take them from a **release build on a real device or a clean emulator**, signed in as the demo account with realistic countdowns. `flutter run --release` then use the device's own screenshot tool.

## 7. Firebase and security checks

- Regenerate native config for the **renamed** Firebase project and package: `flutterfire configure --project=datedawn`. This writes `lib/firebase_options.dart`, `android/app/google-services.json`, and `ios/Runner/GoogleService-Info.plist`.
- The Android app in Firebase must be registered with package name **`com.datedawn.app`** — a mismatch produces a silent auth failure on device.
- Add the **release SHA-1 and SHA-256** of your upload keystore to the Firebase Android app, or Google Sign-In fails in release builds while working in debug.
- Review `firestore.rules` before opening to the public — rules are the only thing protecting the data, and the config in `lib/firebase_config.dart` is public by design.
- Test sign-in, event creation, invitations, notifications and cross-device sync **on real devices**, signed in with two different accounts.

## 8. Pre-launch validation

- sign-in works on a real Android device and a real iPhone
- events save and sync across two accounts
- notifications arrive when enabled
- account deletion works and actually removes data
- no crashes on a cold start with no network
- screenshots match the final app state
- store listing text contains no placeholder values

## 9. Production promotion

### Google Play
Internal testing → Closed testing (**12 testers / 14 days** for new personal accounts) → Production

### App Store
TestFlight (internal first, then external beta review) → App Review submission → Production

App Review typically answers within 24–48 hours. Google's first review of a new account can take **up to 7 days**.

## 2. Required app metadata

### For both stores
- App name and description
- Icon set and splash assets
- Privacy policy URL
- Support URL
- Contact email
- App category
- Screenshots for each device size
- Data safety / privacy disclosures

### Required for App Store
- App Privacy section must be completed
- Upload screenshot set for required iPhone/iPad sizes
- Apple Developer signing certificates and provisioning profiles

### Required for Play Store
- Data safety form
- Content rating questionnaire
- Target audience declaration
- App content declaration

## 3. Privacy policy and support

Before publishing, create a live privacy policy page and add the URL to both stores.

Example requirements:
- clear explanation of Firebase usage
- Google Sign-In usage disclosure
- Firestore data storage disclosure
- notification use disclosure if enabled
- support contact email and website

## 4. App signing and release build

### Android
1. Generate a release keystore
2. Store the key in a secure location
3. Configure `android/key.properties`
4. Build the release bundle:
   ```bash
   flutter build appbundle --release
   ```
5. Upload the `.aab` file to Google Play Console

### iOS
1. Configure Apple Developer certificates and provisioning profiles
2. Set the bundle identifier in Xcode
3. Enable required capabilities
4. Archive the app and upload to App Store Connect
5. Submit for review

## 5. Firebase and security checks

- confirm Firebase config is generated for Android and iOS
- verify GoogleService-Info.plist and google-services.json are correct
- update Firestore rules and auth rules before public release
- test sign-in flows, event creation, notifications, and data sync on real devices

## 6. Pre-launch validation

Before production release, verify:
- sign-in works
- events save and sync
- notifications work when enabled
- app functions on both Android and iPhone devices
- no privacy or policy errors remain
- screenshots match the final app state

## 7. Production promotion

### Google Play
- Internal testing
- Closed testing
- Open testing
- Production release

### App Store
- TestFlight validation
- App Review submission
- Production release after approval

## 10. Final URL checklist

Fill these in and use them consistently in both consoles, the policy page and the app:

- Privacy Policy: `_______________________________`
- Support / Help: `_______________________________`
- Marketing / home: `_______________________________`
- Contact Email: `_______________________________`

Every one of these must be live and load without a sign-in before you submit.
