package io.github.omashishsoni.mocode

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Intent
import android.os.Build
import android.os.IBinder
import android.util.Log
import java.io.File
import java.io.FileOutputStream

/**
 * Foreground service that keeps the Go daemon process alive when the app is
 * backgrounded. Without this, Android kills the process after ~1 minute.
 *
 * Lifecycle:
 *   1. startForegroundService(intent) from DaemonBridge
 *   2. onStartCommand extracts binary, spawns process, shows notification
 *   3. Monitor thread restarts process if it dies unexpectedly
 *   4. stopSelf() or stopService() tears everything down
 */
class DaemonService : Service() {

    companion object {
        const val TAG = "MoCodeDaemon"
        const val CHANNEL_ID = "mocode_daemon"
        const val NOTIFICATION_ID = 1
        const val BINARY_NAME = "mocode"

        /** Set by the service so DaemonBridge can query state. */
        @Volatile
        var isRunning = false
            private set

        @Volatile
        var daemonPort: Int = 0
            private set

        @Volatile
        var process: Process? = null
            private set
    }

    private var monitorThread: Thread? = null
    @Volatile
    private var shouldRun = true

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (isRunning) {
            Log.d(TAG, "Daemon already running, ignoring start request")
            return START_STICKY
        }

        startForeground(NOTIFICATION_ID, buildNotification("Starting daemon..."))
        shouldRun = true

        Thread {
            try {
                val binary = extractBinary()
                if (binary == null) {
                    Log.e(TAG, "Failed to extract daemon binary")
                    updateNotification("Daemon failed: binary not found")
                    stopSelf()
                    return@Thread
                }

                startDaemonProcess(binary)
            } catch (e: Exception) {
                Log.e(TAG, "Failed to start daemon", e)
                updateNotification("Daemon failed: ${e.message}")
                stopSelf()
            }
        }.start()

        return START_STICKY
    }

    override fun onDestroy() {
        shouldRun = false
        isRunning = false
        killDaemon()
        monitorThread?.interrupt()
        monitorThread = null
        super.onDestroy()
        Log.i(TAG, "Daemon service destroyed")
    }

    /**
     * Extract the Go binary from assets to the app's native library directory.
     * Returns the File if successful, null otherwise.
     */
    private fun extractBinary(): File? {
        val abi = Build.SUPPORTED_ABIS.firstOrNull() ?: "arm64-v8a"
        val assetPath = "bin/$abi/$BINARY_NAME"

        val targetDir = File(filesDir, "bin")
        targetDir.mkdirs()
        val targetFile = File(targetDir, BINARY_NAME)

        // Check if binary already exists and matches the bundled version.
        // We use a version marker file to know when to re-extract.
        val versionFile = File(targetDir, "$BINARY_NAME.version")
        val bundledVersion = try {
            assets.open("bin/VERSION").bufferedReader().readLine()?.trim() ?: "0"
        } catch (_: Exception) {
            "0"
        }

        if (targetFile.exists() && versionFile.exists() &&
            versionFile.readText().trim() == bundledVersion) {
            Log.d(TAG, "Binary already extracted (version $bundledVersion)")
            return targetFile
        }

        return try {
            assets.open(assetPath).use { input ->
                FileOutputStream(targetFile).use { output ->
                    input.copyTo(output)
                }
            }
            targetFile.setExecutable(true, false)
            versionFile.writeText(bundledVersion)
            Log.i(TAG, "Extracted $assetPath → ${targetFile.absolutePath}")
            targetFile
        } catch (e: Exception) {
            Log.e(TAG, "Failed to extract binary from $assetPath", e)
            null
        }
    }

    /**
     * Spawn the Go daemon process and start the monitor thread.
     */
    private fun startDaemonProcess(binary: File) {
        val portFile = File(filesDir, "daemon_port")
        val dataDir = filesDir.absolutePath

        val env = mapOf(
            "MOCODE_PORT_FILE" to portFile.absolutePath,
            "MOCODE_WORKDIR" to getExternalFilesDir(null)?.absolutePath ?: dataDir,
            "HOME" to dataDir,
            "TMPDIR" to cacheDir.absolutePath,
        )

        val pb = ProcessBuilder(binary.absolutePath)
        pb.directory(filesDir)
        pb.redirectErrorStream(true)
        pb.environment().putAll(env)

        val proc = pb.start()
        process = proc
        isRunning = true

        // Read port file with retry (daemon writes it on startup).
        daemonPort = waitForPort(portFile, timeoutMs = 10_000)
        if (daemonPort > 0) {
            Log.i(TAG, "Daemon started on port $daemonPort (pid unknown on Android)")
            updateNotification("Daemon running on port $daemonPort")
        } else {
            Log.w(TAG, "Daemon started but port file not found, using default 19280")
            daemonPort = 19280
            updateNotification("Daemon running (default port)")
        }

        // Monitor thread: restart if process dies while shouldRun is true.
        monitorThread = Thread {
            while (shouldRun) {
                try {
                    val exitCode = proc.waitFor()
                    if (!shouldRun) break
                    Log.w(TAG, "Daemon exited with code $exitCode, restarting...")
                    isRunning = false
                    updateNotification("Daemon restarting...")
                    Thread.sleep(2000)
                    if (shouldRun) {
                        startDaemonProcess(binary)
                    }
                    return@Thread
                } catch (_: InterruptedException) {
                    break
                }
            }
        }.apply {
            isDaemon = true
            name = "mocode-monitor"
            start()
        }

        // Log daemon stdout/stderr in a separate thread.
        Thread {
            try {
                proc.inputStream.bufferedReader().forEachLine { line ->
                    Log.d(TAG, line)
                }
            } catch (_: Exception) {
                // Process ended
            }
        }.apply {
            isDaemon = true
            name = "mocode-logger"
            start()
        }
    }

    private fun killDaemon() {
        process?.let { proc ->
            try {
                proc.destroy()
                // Give it a moment to exit gracefully.
                Thread.sleep(500)
                if (proc.isAlive) {
                    proc.destroyForcibly()
                }
            } catch (_: Exception) {
                // Best effort
            }
            process = null
            daemonPort = 0
        }
    }

    /**
     * Wait for the port file to appear and contain a valid port number.
     */
    private fun waitForPort(portFile: File, timeoutMs: Long): Int {
        val deadline = System.currentTimeMillis() + timeoutMs
        while (System.currentTimeMillis() < deadline) {
            if (portFile.exists()) {
                val port = portFile.readText().trim().toIntOrNull()
                if (port != null && port > 0) return port
            }
            Thread.sleep(200)
        }
        return 0
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "Mo-Code Daemon",
                NotificationManager.IMPORTANCE_LOW,
            ).apply {
                description = "Keeps the AI coding agent running in the background"
                setShowBadge(false)
            }
            val nm = getSystemService(NotificationManager::class.java)
            nm.createNotificationChannel(channel)
        }
    }

    private fun buildNotification(text: String): Notification {
        val intent = Intent(this, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_SINGLE_TOP
        }
        val pending = PendingIntent.getActivity(
            this, 0, intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )

        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, CHANNEL_ID)
                .setContentTitle("mo-code")
                .setContentText(text)
                .setSmallIcon(android.R.drawable.ic_menu_manage)
                .setContentIntent(pending)
                .setOngoing(true)
                .build()
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this)
                .setContentTitle("mo-code")
                .setContentText(text)
                .setSmallIcon(android.R.drawable.ic_menu_manage)
                .setContentIntent(pending)
                .setOngoing(true)
                .build()
        }
    }

    private fun updateNotification(text: String) {
        val nm = getSystemService(NotificationManager::class.java)
        nm.notify(NOTIFICATION_ID, buildNotification(text))
    }
}
