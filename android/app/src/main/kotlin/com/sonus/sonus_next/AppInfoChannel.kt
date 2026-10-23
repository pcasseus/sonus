package com.sonus.sonus_next

import android.app.Activity
import android.content.pm.PackageInfo
import android.content.pm.PackageManager
import android.os.Build
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

/**
 * Reports the installed app's version name and build number for the
 * About Sonus page. It exposes nothing else about the device or package.
 */
class AppInfoChannel(activity: Activity, messenger: BinaryMessenger) {
    init {
        MethodChannel(messenger, CHANNEL).setMethodCallHandler { call, result ->
            if (call.method != "getAppInfo") {
                result.notImplemented()
                return@setMethodCallHandler
            }

            try {
                val info = packageInfo(activity)
                result.success(
                    mapOf(
                        "versionName" to (info.versionName ?: ""),
                        "buildNumber" to buildNumber(info).toString()
                    )
                )
            } catch (error: Exception) {
                result.error(
                    "APP_INFO_UNAVAILABLE",
                    "App information is unavailable.",
                    null
                )
            }
        }
    }

    private fun packageInfo(activity: Activity): PackageInfo {
        val manager = activity.packageManager
        val name = activity.packageName

        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            manager.getPackageInfo(name, PackageManager.PackageInfoFlags.of(0))
        } else {
            @Suppress("DEPRECATION")
            manager.getPackageInfo(name, 0)
        }
    }

    private fun buildNumber(info: PackageInfo): Long {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            info.longVersionCode
        } else {
            @Suppress("DEPRECATION")
            info.versionCode.toLong()
        }
    }

    companion object {
        const val CHANNEL = "com.sonus.sonus_next/app_info"
    }
}
