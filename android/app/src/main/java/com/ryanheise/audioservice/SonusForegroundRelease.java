// SN-44: Sonus's own code, deliberately declared in audio_service's package.
//
// Pinned to audio_service 0.18.18 (pubspec.yaml). When a session goes idle,
// audio_service calls AudioService.stop(), which only calls stopSelf().
// The plugin's own MediaBrowser stays bound to the service while an
// activity exists, so the service is not destroyed, onDestroy() never
// leaves the foreground, and Android refuses to cancel a foreground
// service's notification: Stop and a finished queue left a dead
// notification behind. The plugin exposes no API for this, and the
// running service is only reachable through the package-private
// AudioService.instance, hence this package.
//
// Java rather than Kotlin: AudioService's androidx.media superclass is not
// on the app's compile classpath, and only javac can read the field as a
// plain Object without resolving it.
//
// Upgrading audio_service: if `instance` is renamed or removed this file
// stops compiling. Re-run the SN-44 Stop and end-of-queue checks after any
// upgrade, and delete this file if the plugin starts leaving the
// foreground itself.
package com.ryanheise.audioservice;

import android.app.Service;
import android.os.Build;

public final class SonusForegroundRelease {
    private SonusForegroundRelease() {}

    /**
     * Takes the media service out of the foreground and removes its
     * notification. The service stays bound, exactly as before playback
     * first started, and returns to the foreground when playback resumes.
     *
     * @return false when no media service is running.
     */
    public static boolean release() {
        final Object running = AudioService.instance;

        if (!(running instanceof Service)) {
            return false;
        }

        final Service service = (Service) running;

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            service.stopForeground(Service.STOP_FOREGROUND_REMOVE);
        } else {
            service.stopForeground(true);
        }

        return true;
    }
}
