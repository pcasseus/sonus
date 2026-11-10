import 'package:flutter/services.dart';

/// The Android package this build is installed as (App Update 1.2 device
/// QA): `com.sonus.sonus_next` for the real app (the prod flavor), and
/// `com.sonus.sonus_next.qa` for the QA install beside it. It must match
/// `applicationId` in android/app/build.gradle.kts.
const String sonusApplicationId = appFlavor == 'qa'
    ? 'com.sonus.sonus_next.qa'
    : 'com.sonus.sonus_next';
