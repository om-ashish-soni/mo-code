package io.github.omashishsoni.mocode

import android.app.ForegroundServiceStartNotAllowedException
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.util.Log
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

class DaemonBridge(
    private val context: Context,
    messenger: BinaryMessenger,
) : MethodChannel.MethodCallHandler {

    companion object {
        const val CHANNEL = "io.mocode/daemon"
        const val TAG = "DaemonBridge"
        const val MAX_START_RETRIES = 3
        const val RETRY_DELAY_MS = 500L
    }

    private val channel = MethodChannel(messenger, CHANNEL)
    private val handler = Handler(Looper.getMainLooper())

    init {
        channel.setMethodCallHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "startDaemon" -> {
                startDaemonWithRetry(0, result)
            }
            "stopDaemon" -> {
                context.stopService(Intent(context, DaemonService::class.java))
                result.success(true)
            }
            "isRunning" -> {
                result.success(DaemonService.isRunning)
            }
            "getPort" -> {
                result.success(DaemonService.daemonPort)
            }
            "getPortFile" -> {
                val portFile = java.io.File(context.filesDir, "daemon_port")
                result.success(portFile.absolutePath)
            }
            "getRuntimeStatus" -> {
                val bootstrap = RuntimeBootstrap(context)
                val paths = bootstrap.paths()
                result.success(mapOf(
                    "bootstrapped" to RuntimeBootstrap.isBootstrapped,
                    "progress" to RuntimeBootstrap.bootstrapProgress,
                    "progress_percent" to RuntimeBootstrap.bootstrapPercent,
                    "proot_bin" to (paths?.prootBin ?: ""),
                    "rootfs" to (paths?.rootFS ?: ""),
                    "projects_dir" to (paths?.projectsDir ?: ""),
                    "size_bytes" to bootstrap.runtimeSize(),
                ))
            }
            "getLogs" -> {
                val logFile = java.io.File(context.filesDir, "daemon.log")
                if (logFile.exists()) {
                    // Return last 200 lines
                    val lines = logFile.readLines()
                    val tail = lines.takeLast(200).joinToString("\n")
                    result.success(tail)
                } else {
                    result.success("No log file found")
                }
            }
            "resetRuntime" -> {
                Thread {
                    val bootstrap = RuntimeBootstrap(context)
                    val paths = bootstrap.reset()
                    val handler = android.os.Handler(android.os.Looper.getMainLooper())
                    handler.post {
                        result.success(paths != null)
                    }
                }.start()
            }
            else -> result.notImplemented()
        }
    }

    private fun startDaemonWithRetry(attempt: Int, result: MethodChannel.Result) {
        val intent = Intent(context, DaemonService::class.java)
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(intent)
            } else {
                context.startService(intent)
            }
            Log.i(TAG, "Foreground service started (attempt ${attempt + 1})")
            result.success(true)
        } catch (e: Exception) {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S &&
                e is ForegroundServiceStartNotAllowedException &&
                attempt < MAX_START_RETRIES
            ) {
                Log.w(TAG, "FG service not allowed yet (attempt ${attempt + 1}/$MAX_START_RETRIES), retrying in ${RETRY_DELAY_MS}ms")
                handler.postDelayed({ startDaemonWithRetry(attempt + 1, result) }, RETRY_DELAY_MS)
            } else {
                Log.e(TAG, "Failed to start daemon service after ${attempt + 1} attempts", e)
                result.error("start_failed", e.message, null)
            }
        }
    }

    fun dispose() {
        channel.setMethodCallHandler(null)
    }
}
