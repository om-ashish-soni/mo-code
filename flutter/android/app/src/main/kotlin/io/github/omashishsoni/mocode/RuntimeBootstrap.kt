package io.github.omashishsoni.mocode

import android.content.Context
import android.util.Log
import java.io.File
import java.io.FileOutputStream
import java.security.MessageDigest
import java.util.zip.GZIPInputStream

/**
 * Extracts proot binary and Alpine Linux rootfs from APK assets on first launch.
 *
 * Layout after extraction:
 *   filesDir/
 *     runtime/
 *       proot              (static ARM64 binary, executable)
 *       rootfs/            (Alpine Linux filesystem)
 *         bin/ usr/ etc/ home/developer/
 *       RUNTIME_VERSION    (version marker to skip re-extraction)
 *     projects/            (user project files, bind-mounted into proot)
 *
 * Thread-safe: designed to be called from a background thread.
 */
class RuntimeBootstrap(private val context: Context) {

    companion object {
        const val TAG = "RuntimeBootstrap"
        const val RUNTIME_DIR = "runtime"
        const val PROOT_ASSET = "runtime/proot-arm64"
        const val ROOTFS_ASSET = "runtime/alpine-minirootfs.tar.gz"
        const val VERSION_ASSET = "runtime/RUNTIME_VERSION"
        const val CHECKSUMS_ASSET = "runtime/CHECKSUMS"

        /** Volatile state readable from any thread. */
        @Volatile
        var isBootstrapped = false
            private set

        @Volatile
        var bootstrapProgress: String = ""
            private set

        @Volatile
        var bootstrapPercent: Int = 0
            private set
    }

    data class RuntimePaths(
        val prootBin: String,
        val rootFS: String,
        val projectsDir: String,
    )

    /**
     * Bootstrap the runtime environment. Idempotent — skips if already extracted
     * and version matches. Returns paths for the Go daemon, or null on failure.
     *
     * @param onProgress callback for progress updates (message, percent 0-100)
     */
    fun bootstrap(onProgress: ((String, Int) -> Unit)? = null): RuntimePaths? {
        val runtimeDir = File(context.filesDir, RUNTIME_DIR)
        val prootFile = File(runtimeDir, "proot")
        val rootfsDir = File(runtimeDir, "rootfs")
        val versionFile = File(runtimeDir, "RUNTIME_VERSION")
        val projectsDir = File(context.getExternalFilesDir(null) ?: context.filesDir, "projects")

        fun progress(msg: String, pct: Int) {
            bootstrapProgress = msg
            bootstrapPercent = pct
            onProgress?.invoke(msg, pct)
            Log.d(TAG, "[$pct%] $msg")
        }

        // Check if already bootstrapped with matching version.
        val bundledVersion = try {
            context.assets.open(VERSION_ASSET).bufferedReader().readLine()?.trim() ?: "0"
        } catch (_: Exception) {
            "0"
        }

        if (prootFile.exists() && rootfsDir.exists() && versionFile.exists() &&
            versionFile.readText().trim() == bundledVersion) {
            Log.d(TAG, "Runtime already bootstrapped (version $bundledVersion)")
            isBootstrapped = true
            progress("Ready", 100)
            return RuntimePaths(
                prootBin = prootFile.absolutePath,
                rootFS = rootfsDir.absolutePath,
                projectsDir = projectsDir.absolutePath,
            )
        }

        progress("Setting up development environment...", 0)

        try {
            // Create directories.
            runtimeDir.mkdirs()
            projectsDir.mkdirs()

            // Load expected checksums.
            val checksums = loadChecksums()

            // --- Extract proot binary (5%) ---
            progress("Extracting proot binary...", 5)
            context.assets.open(PROOT_ASSET).use { input ->
                FileOutputStream(prootFile).use { output ->
                    input.copyTo(output)
                }
            }
            prootFile.setExecutable(true, false)

            // Verify proot checksum.
            val prootExpected = checksums["proot-arm64"]
            if (prootExpected != null) {
                val actual = sha256(prootFile)
                if (actual != prootExpected) {
                    Log.e(TAG, "proot checksum mismatch: expected=$prootExpected actual=$actual")
                    return null
                }
            }
            progress("proot extracted", 10)

            // --- Extract Alpine rootfs tar.gz (10-90%) ---
            progress("Extracting Alpine Linux rootfs...", 15)

            // Wipe existing rootfs to ensure clean state.
            if (rootfsDir.exists()) {
                rootfsDir.deleteRecursively()
            }
            rootfsDir.mkdirs()

            // Copy tar.gz to a temp file so we can extract with system tar.
            val tmpTarGz = File(runtimeDir, "rootfs.tar.gz")
            context.assets.open(ROOTFS_ASSET).use { input ->
                FileOutputStream(tmpTarGz).use { output ->
                    input.copyTo(output)
                }
            }
            progress("Extracting rootfs...", 30)

            // Use system tar to extract (available on Android).
            val proc = ProcessBuilder("tar", "xzf", tmpTarGz.absolutePath, "-C", rootfsDir.absolutePath)
                .redirectErrorStream(true)
                .start()
            val tarOutput = proc.inputStream.bufferedReader().readText()
            val exitCode = proc.waitFor()

            if (exitCode != 0) {
                Log.e(TAG, "tar extraction failed (exit $exitCode): $tarOutput")
                // Fallback: try Java-based extraction.
                progress("Fallback extraction...", 35)
                extractWithJava(tmpTarGz, rootfsDir, onProgress = { msg, pct -> progress(msg, pct) })
            }

            // Clean up temp file.
            tmpTarGz.delete()

            progress("Rootfs extracted", 92)

            // Create /home/developer inside rootfs (mount point for projects).
            File(rootfsDir, "home/developer").mkdirs()

            // --- Write version marker (95%) ---
            progress("Finalizing...", 95)
            versionFile.writeText(bundledVersion)

            isBootstrapped = true
            progress("Ready", 100)

            Log.i(TAG, "Runtime bootstrapped: proot=${prootFile.absolutePath} rootfs=${rootfsDir.absolutePath}")

            return RuntimePaths(
                prootBin = prootFile.absolutePath,
                rootFS = rootfsDir.absolutePath,
                projectsDir = projectsDir.absolutePath,
            )
        } catch (e: Exception) {
            Log.e(TAG, "Bootstrap failed", e)
            progress("Bootstrap failed: ${e.message}", -1)
            return null
        }
    }

    /**
     * Wipe the runtime and re-extract from assets.
     */
    fun reset(onProgress: ((String, Int) -> Unit)? = null): RuntimePaths? {
        isBootstrapped = false
        val runtimeDir = File(context.filesDir, RUNTIME_DIR)
        if (runtimeDir.exists()) {
            runtimeDir.deleteRecursively()
        }
        return bootstrap(onProgress)
    }

    /**
     * Get the total size of the runtime directory in bytes.
     */
    fun runtimeSize(): Long {
        val runtimeDir = File(context.filesDir, RUNTIME_DIR)
        if (!runtimeDir.exists()) return 0
        return runtimeDir.walkTopDown().filter { it.isFile }.sumOf { it.length() }
    }

    /**
     * Get current runtime paths if bootstrapped, null otherwise.
     */
    fun paths(): RuntimePaths? {
        if (!isBootstrapped) return null
        val runtimeDir = File(context.filesDir, RUNTIME_DIR)
        val projectsDir = File(context.getExternalFilesDir(null) ?: context.filesDir, "projects")
        return RuntimePaths(
            prootBin = File(runtimeDir, "proot").absolutePath,
            rootFS = File(runtimeDir, "rootfs").absolutePath,
            projectsDir = projectsDir.absolutePath,
        )
    }

    // --- Private helpers ---

    private fun loadChecksums(): Map<String, String> {
        return try {
            val lines = context.assets.open(CHECKSUMS_ASSET).bufferedReader().readLines()
            lines.associate { line ->
                val parts = line.split(" ", limit = 2)
                parts[0] to parts.getOrElse(1) { "" }
            }
        } catch (_: Exception) {
            emptyMap()
        }
    }

    private fun sha256(file: File): String {
        val digest = MessageDigest.getInstance("SHA-256")
        file.inputStream().buffered().use { input ->
            val buffer = ByteArray(8192)
            var read: Int
            while (input.read(buffer).also { read = it } != -1) {
                digest.update(buffer, 0, read)
            }
        }
        return digest.digest().joinToString("") { "%02x".format(it) }
    }

    /**
     * Fallback Java-based tar.gz extraction if system tar is unavailable.
     * Uses only java.util.zip (no external dependencies).
     *
     * This is a simplified tar parser that handles regular files, directories,
     * and symlinks. Alpine minirootfs only uses these entry types.
     */
    private fun extractWithJava(tarGzFile: File, targetDir: File, onProgress: (String, Int) -> Unit) {
        var entryCount = 0
        tarGzFile.inputStream().buffered().use { fileIn ->
            GZIPInputStream(fileIn).use { gzIn ->
                // Tar format: 512-byte headers followed by data blocks.
                val headerBuf = ByteArray(512)
                while (true) {
                    val headerRead = readFully(gzIn, headerBuf)
                    if (headerRead < 512) break

                    // Check for end-of-archive (two zero blocks).
                    if (headerBuf.all { it == 0.toByte() }) break

                    val name = extractString(headerBuf, 0, 100)
                    if (name.isEmpty()) break

                    val sizeOctal = extractString(headerBuf, 124, 12)
                    val size = sizeOctal.trimEnd('\u0000', ' ').toLongOrNull(8) ?: 0L
                    val typeFlag = headerBuf[156].toInt().toChar()
                    val linkName = extractString(headerBuf, 157, 100)

                    // Handle USTAR prefix for long names.
                    val prefix = extractString(headerBuf, 345, 155)
                    val fullName = if (prefix.isNotEmpty()) "$prefix/$name" else name

                    val outFile = File(targetDir, fullName)

                    // Zip-slip protection.
                    if (!outFile.canonicalPath.startsWith(targetDir.canonicalPath)) {
                        skipBytes(gzIn, alignTo512(size))
                        continue
                    }

                    when (typeFlag) {
                        '5', 'D' -> {
                            // Directory.
                            outFile.mkdirs()
                        }
                        '2' -> {
                            // Symlink.
                            outFile.parentFile?.mkdirs()
                            try {
                                Runtime.getRuntime().exec(
                                    arrayOf("ln", "-sf", linkName, outFile.absolutePath)
                                ).waitFor()
                            } catch (_: Exception) {
                                Log.w(TAG, "Symlink failed: $fullName -> $linkName")
                            }
                        }
                        '1' -> {
                            // Hard link — copy as regular file (Android doesn't support hard links well).
                            outFile.parentFile?.mkdirs()
                            val linkTarget = File(targetDir, linkName)
                            if (linkTarget.exists()) {
                                linkTarget.copyTo(outFile, overwrite = true)
                            }
                        }
                        else -> {
                            // Regular file (type '0' or '\0').
                            outFile.parentFile?.mkdirs()
                            FileOutputStream(outFile).use { fos ->
                                var remaining = size
                                val buf = ByteArray(8192)
                                while (remaining > 0) {
                                    val toRead = minOf(remaining, buf.size.toLong()).toInt()
                                    val read = gzIn.read(buf, 0, toRead)
                                    if (read <= 0) break
                                    fos.write(buf, 0, read)
                                    remaining -= read
                                }
                            }
                            // Skip padding to 512-byte boundary.
                            val padding = alignTo512(size) - size
                            if (padding > 0) skipBytes(gzIn, padding)

                            // Set executable if needed.
                            val modeOctal = extractString(headerBuf, 100, 8)
                            val mode = modeOctal.trimEnd('\u0000', ' ').toIntOrNull(8) ?: 0
                            if (mode and 0x49 != 0) { // 0111 — any execute bit
                                outFile.setExecutable(true, false)
                            }
                        }
                    }

                    // For directories/symlinks, no data blocks to skip.
                    if (typeFlag == '5' || typeFlag == 'D' || typeFlag == '2' || typeFlag == '1') {
                        // No data to skip.
                    }

                    entryCount++
                    if (entryCount % 50 == 0) {
                        val pct = 35 + (entryCount.coerceAtMost(500) * 55 / 500)
                        onProgress("Extracting rootfs ($entryCount files)...", pct)
                    }
                }
            }
        }
        Log.i(TAG, "Java tar extraction: $entryCount entries")
    }

    private fun readFully(input: java.io.InputStream, buf: ByteArray): Int {
        var offset = 0
        while (offset < buf.size) {
            val read = input.read(buf, offset, buf.size - offset)
            if (read <= 0) break
            offset += read
        }
        return offset
    }

    private fun extractString(buf: ByteArray, offset: Int, len: Int): String {
        val end = buf.indexOf(0, offset).let { if (it in offset until offset + len) it else offset + len }
        return String(buf, offset, end - offset, Charsets.US_ASCII).trimEnd('\u0000')
    }

    private fun ByteArray.indexOf(byte: Byte, fromIndex: Int): Int {
        for (i in fromIndex until size) {
            if (this[i] == byte) return i
        }
        return -1
    }

    private fun alignTo512(size: Long): Long {
        val rem = size % 512
        return if (rem == 0L) size else size + (512 - rem)
    }

    private fun skipBytes(input: java.io.InputStream, count: Long) {
        var remaining = count
        val buf = ByteArray(512)
        while (remaining > 0) {
            val toRead = minOf(remaining, buf.size.toLong()).toInt()
            val read = input.read(buf, 0, toRead)
            if (read <= 0) break
            remaining -= read
        }
    }
}
