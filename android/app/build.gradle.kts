plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.datedawn.app"
    compileSdk = flutter.compileSdkVersion
    // Pinned rather than taken from `flutter.ndkVersion`: an explicit version
    // makes Gradle fetch the NDK it needs (including `llvm-strip`, which the
    // release pipeline uses to strip native debug symbols) instead of failing
    // when the host SDK has a different one installed.
    //
    // 28.2.13676358 is the highest version any current plugin requires
    // (`cloud_firestore`/`jni`, `share_plus`, `shared_preferences_android`),
    // and NDK releases are backward compatible — pinning lower than a plugin
    // asks for is what makes the build complain.
    ndkVersion = "28.2.13676358"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        // Required by flutter_local_notifications, which uses java.time on API
        // levels below 26. Without this the release build fails at
        // `:app:checkReleaseAarMetadata` with "requires core library
        // desugaring to be enabled". The extra dependency is the desugaring
        // runtime that back-ports those APIs.
        isCoreLibraryDesugaringEnabled = true
    }

    defaultConfig {
        // DateDawn's permanent package name. This value is what Google Play uses
        // to identify the app: once the first bundle is uploaded it can NEVER be
        // changed, and every future `google-services.json` must be generated for
        // exactly this package name.
        applicationId = "com.datedawn.app"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // Release builds are signed with the upload key configured in
            // key.properties. That file is deliberately not committed (see
            // .gitignore), so CI falls back to the debug key: it proves the
            // release build compiles without shipping a real signing key to a
            // build server. Play uploads must use the real key locally.
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

dependencies {
    // The back-port of java.time that core library desugaring needs at runtime.
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
