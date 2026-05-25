# Firebase setup for Automata Designer

Guest mode works without Firebase. To enable **email sign-in** and **cloud sync**:

## 1. Create a Firebase project

1. Open [Firebase Console](https://console.firebase.google.com/)
2. Create a project (or use an existing one)
3. Enable **Authentication** → Sign-in method → **Email/Password**
4. Enable **Cloud Firestore** → Create database (start in test mode for development, then add rules below)

## 2. Register your app

Add Android, iOS, Web, and/or Windows apps in the Firebase console using your Flutter app IDs.

## 3. FlutterFire CLI

From `SU26/FAExplorer`:

```bash
dart pub global activate flutterfire_cli
flutterfire configure
```

This generates `lib/firebase_options.dart`. Then set in that file (or keep the generated file):

```dart
const bool kFirebaseConfigured = true;
```

If you keep the hand-written `firebase_options.dart` in the repo, paste the values from the generated file and set `kFirebaseConfigured = true`.

## 4. Android (optional)

Place `google-services.json` in `android/app/` and add to `android/settings.gradle.kts`:

```kotlin
id("com.google.gms.google-services") version "4.4.2" apply false
```

And in `android/app/build.gradle.kts`:

```kotlin
plugins {
    id("com.android.application")
    id("com.google.gms.google-services")
    // ...
}
```

## 5. Firestore security rules (production)

```text
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    match /users/{userId}/workspace/{docId} {
      allow read, write: if request.auth != null && request.auth.uid == userId;
    }
  }
}
```

## 6. Data layout

Signed-in users store workspace data at:

`users/{uid}/workspace/main`

Fields: `graphDsl`, `savedExports`, `showSimulator`, `showHelpOverlay`, `simInput`, `simStep`, `updatedAt`.

Guest users use **local SharedPreferences only** — no Firebase calls.
