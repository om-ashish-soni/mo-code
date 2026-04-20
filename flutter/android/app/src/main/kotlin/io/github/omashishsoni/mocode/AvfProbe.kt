package io.github.omashishsoni.mocode

import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import android.util.Log
import org.json.JSONObject
import java.io.File

/**
 * Detects whether the Android Virtualization Framework (AVF) and Microdroid
 * are usable on this device. Designed to run cheaply at app startup.
 *
 * Bridge to Go: [probeAndPersist] writes a JSON file at
 * `${context.filesDir}/avf_probe.json` which the Go-side `avf-microdroid`
 * sandbox backend reads (path passed via `cfg.Options["avf.probe_file"]` or
 * `MOCODE_AVF_PROBE_FILE` env var). Wiring lives in `DaemonService` — see
 * `docs/SANDBOX_AVF.md`.
 */
object AvfProbe {
    const val TAG = "AvfProbe"
    const val PROBE_FILE_NAME = "avf_probe.json"

    private const val FEATURE_VIRTUALIZATION_FRAMEWORK = "android.software.virtualization_framework"
    private const val VMM_CLASS = "android.system.virtualmachine.VirtualMachineManager"
    private const val MIN_API = 34

    data class Result(val available: Boolean, val reason: String)

    /** Pure check; no side effects. Safe to call from any thread. */
    fun probe(context: Context): Result {
        if (Build.VERSION.SDK_INT < MIN_API) {
            return Result(false, "API ${Build.VERSION.SDK_INT} < $MIN_API (UPSIDE_DOWN_CAKE)")
        }

        val pm = context.packageManager
        if (!pm.hasSystemFeature(FEATURE_VIRTUALIZATION_FRAMEWORK)) {
            return Result(false, "$FEATURE_VIRTUALIZATION_FRAMEWORK not present")
        }

        // VirtualMachineManager is restricted on some OEM builds; reach it via
        // reflection so a missing class never throws at link time.
        return try {
            val cls = Class.forName(VMM_CLASS)
            val getSystemService = Context::class.java.getMethod("getSystemService", Class::class.java)
            val mgr = getSystemService.invoke(context, cls)
            if (mgr == null) {
                Result(false, "VirtualMachineManager system service returned null")
            } else {
                Result(true, "")
            }
        } catch (t: Throwable) {
            Result(false, "VirtualMachineManager unavailable: ${t.javaClass.simpleName}: ${t.message ?: ""}")
        }
    }

    /**
     * Probe and persist the result for the Go daemon to consume.
     * Returns the result and the file written. Failures to persist are logged
     * but do not throw — the daemon will then see "probe file not present" and
     * the avf backend Factory will return ErrBackendUnavailable, which is the
     * correct behaviour for unsupported devices.
     */
    fun probeAndPersist(context: Context): Pair<Result, File> {
        val r = probe(context)
        val f = File(context.filesDir, PROBE_FILE_NAME)
        try {
            val json = JSONObject().apply {
                put("available", r.available)
                put("reason", r.reason)
                put("api_level", Build.VERSION.SDK_INT)
                put("device", "${Build.MANUFACTURER} ${Build.MODEL}")
            }
            f.writeText(json.toString())
            Log.i(TAG, "AVF probe: available=${r.available} reason=\"${r.reason}\" -> ${f.absolutePath}")
        } catch (t: Throwable) {
            Log.w(TAG, "Failed to persist AVF probe to ${f.absolutePath}: $t")
        }
        return r to f
    }
}
