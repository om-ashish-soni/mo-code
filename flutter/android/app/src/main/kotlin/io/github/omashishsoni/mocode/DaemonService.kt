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

class DaemonService : Service() {

    companion object {
        const val TAG = "MoCodeDaemon"
        const val CHANNEL_ID = "mocode_daemon"
        const val NOTIFICATION_ID = 1

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
                updateNotification("Setting up runtime...")
                val bootstrap = RuntimeBootstrap(this)
                val runtimePaths = bootstrap.bootstrap { msg, pct ->
                    if (pct in 0..100) {
                        updateNotification(msg)
                    }
                }
                if (runtimePaths == null) {
                    Log.w(TAG, "Runtime bootstrap failed, daemon will run without proot")
                }

                val binary = findBinary()
                if (binary == null) {
                    Log.e(TAG, "Failed to find daemon binary")
                    updateNotification("Daemon failed: binary not found")
                    stopSelf()
                    return@Thread
                }

                startDaemonProcess(binary, runtimePaths)
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

    private fun findBinary(): File? {
        val nativeLibDir = applicationInfo.nativeLibraryDir
        val binary = File(nativeLibDir, "libmocode.so")
        if (binary.exists() && binary.canExecute()) {
            Log.i(TAG, "Using native lib binary: ${binary.absolutePath}")
            return binary
        }
        Log.e(TAG, "Native lib binary not found at ${binary.absolutePath}")
        return null
    }

    private fun getSystemDnsServers(): String {
        try {
            val cm = getSystemService(CONNECTIVITY_SERVICE) as? android.net.ConnectivityManager
            val network = cm?.activeNetwork
            val lp = cm?.getLinkProperties(network)
            val servers = lp?.dnsServers?.map { it.hostAddress }?.filterNotNull()
            if (!servers.isNullOrEmpty()) {
                Log.i(TAG, "System DNS servers: $servers")
                return servers.joinToString(",")
            }
        } catch (e: Exception) {
            Log.w(TAG, "Could not read system DNS: $e")
        }
        return "8.8.8.8,8.8.4.4"
    }

    private fun startDaemonProcess(binary: File, runtimePaths: RuntimeBootstrap.RuntimePaths? = null) {
        val portFile = File(filesDir, "daemon_port")
        val dataDir = filesDir.absolutePath
        val workDir: String = getExternalFilesDir(null)?.absolutePath ?: dataDir
        val dnsServers = getSystemDnsServers()

        // Android's system CA certificates for Go's TLS stack.
        // Go's crypto/x509 reads PEM files from SSL_CERT_DIR; Android 14+ moved certs to the
        // APEX path, so try both and use whichever exists.
        val sslCertDir = when {
            java.io.File("/apex/com.android.conscrypt/cacerts").isDirectory ->
                "/apex/com.android.conscrypt/cacerts"
            java.io.File("/system/etc/security/cacerts").isDirectory ->
                "/system/etc/security/cacerts"
            else -> null
        }

        val env = mutableMapOf(
            "MOCODE_PORT_FILE" to portFile.absolutePath,
            "MOCODE_WORKDIR" to workDir,
            "HOME" to dataDir,
            "TMPDIR" to cacheDir.absolutePath,
            "MOCODE_DNS" to dnsServers,
        )
        if (sslCertDir != null) {
            env["SSL_CERT_DIR"] = sslCertDir
            Log.i(TAG, "TLS: using CA certs from $sslCertDir")
        } else {
            Log.w(TAG, "TLS: no system CA cert directory found — HTTPS may fail")
        }

        if (runtimePaths != null) {
            env["MOCODE_PROOT_BIN"] = runtimePaths.prootBin
            env["MOCODE_PROOT_ROOTFS"] = runtimePaths.rootFS
            env["MOCODE_PROOT_PROJECTS"] = runtimePaths.projectsDir
            // libproot-loader.so lives in nativeLibraryDir (apk_data_file SELinux context = executable).
            // proot uses this loader to exec binaries from filesDir (app_data_file = not exec-able directly).
            val loaderPath = File(applicationInfo.nativeLibraryDir, "libproot-loader.so")
            if (loaderPath.exists()) {
                env["MOCODE_PROOT_LOADER"] = loaderPath.absolutePath
                Log.i(TAG, "proot loader: ${loaderPath.absolutePath}")
            } else {
                Log.w(TAG, "proot loader not found at ${loaderPath.absolutePath}, SELinux exec may fail")
            }
            Log.i(TAG, "proot enabled: bin=${runtimePaths.prootBin} rootfs=${runtimePaths.rootFS}")
        }

        val pb = ProcessBuilder(binary.absolutePath)
        pb.directory(filesDir)
        pb.redirectErrorStream(true)
        pb.environment().putAll(env)

        val proc = pb.start()
        process = proc
        isRunning = true

        daemonPort = waitForPort(portFile, timeoutMs = 10000)
        if (daemonPort > 0) {
            Log.i(TAG, "Daemon started on port $daemonPort")
            updateNotification("Daemon running on port $daemonPort")
        } else {
            Log.w(TAG, "Port file not found, using default 19280")
            daemonPort = 19280
            updateNotification("Daemon running (default port)")
        }

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
                        startDaemonProcess(binary, runtimePaths)
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

        val logFile = File(filesDir, "daemon.log")
        Thread {
            try {
                val writer = logFile.bufferedWriter()
                proc.inputStream.bufferedReader().forEachLine { line ->
                    Log.d(TAG, line)
                    try {
                        writer.write(line)
                        writer.newLine()
                        writer.flush()
                    } catch (_: Exception) { }
                }
                writer.close()
            } catch (_: Exception) { }
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
                Thread.sleep(500)
                if (proc.isAlive) {
                    proc.destroyForcibly()
                }
            } catch (_: Exception) { }
            process = null
            daemonPort = 0
        }
    }

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
                NotificationManager.IMPORTANCE_LOW
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
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
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
