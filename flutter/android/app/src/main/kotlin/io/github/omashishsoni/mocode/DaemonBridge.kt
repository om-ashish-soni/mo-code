package io.github.omashishsoni.mocode

import android.content.Context
import android.content.Intent
import android.os.Build
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * Platform channel bridge between Dart and the DaemonService.
 *
 * Channel: "io.mocode/daemon"
 *
 * Methods:
 *   startDaemon()  → starts the foreground service + Go process
 *   stopDaemon()   → stops the service and kills the process
 *   isRunning()    → returns bool
 *   getPort()      → returns int (0 if not running)
 *   getPortFile()  → returns String path to the port file
 */
class DaemonBridge(
    private val context: Context,
    messenger: BinaryMessenger,
) : MethodChannel.MethodCallHandler {

    companion object {
        const val CHANNEL = "io.mocode/daemon"
    }

    private val channel = MethodChannel(messenger, CHANNEL)

    init {
        channel.setMethodCallHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "startDaemon" -> {
                val intent = Intent(context, DaemonService::class.java)
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    context.startForegroundService(intent)
                } else {
                    context.startService(intent)
                }
                result.success(true)
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
            else -> result.notImplemented()
        }
    }

    fun dispose() {
        channel.setMethodCallHandler(null)
    }
}
