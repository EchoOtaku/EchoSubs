package dev.echootaku.echo_subs

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.io.IOException
import java.util.concurrent.Executors

/** Only user-selected SAF documents. No raw paths, storage permissions or URI logs. */
class DocumentAccess(private val activity: Activity, messenger: BinaryMessenger) : MethodChannel.MethodCallHandler {
    private val channel = MethodChannel(messenger, "echosubs/document_access")
    private val executor = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())
    private var result: MethodChannel.Result? = null
    private var content: ByteArray? = null
    private var saving = false
    private var closed = false
    companion object {
        private const val REQUEST = 6120
        private const val MAX = 100 * 1024 * 1024
    }
    init { channel.setMethodCallHandler(this) }
    override fun onMethodCall(call: MethodCall, reply: MethodChannel.Result) {
        if (call.method != "save" && call.method != "pick") { reply.notImplemented(); return }
        if (closed || result != null) { reply.error("unavailable", "文件选择正在进行", null); return }
        saving = call.method == "save"
        val bytes = call.argument<ByteArray>("bytes")
        val name = call.argument<String>("suggestedName")
        if (saving && (bytes == null || bytes.isEmpty() || bytes.size > MAX || name.isNullOrEmpty() ||
            name.length > 200 || name.any { it < ' ' || it == '/' || it == '\\' })) {
            reply.error("validation", "文件或文件名无效", null); return
        }
        result = reply
        content = bytes?.copyOf()
        val intent = Intent(if (saving) Intent.ACTION_CREATE_DOCUMENT else Intent.ACTION_OPEN_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            type = if (saving && name!!.endsWith(".json")) "application/json" else "application/octet-stream"
            if (saving) putExtra(Intent.EXTRA_TITLE, name)
            // Providers may label backup files differently; the format authenticates the selection.
            if (!saving) type = "*/*"
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            if (saving) addFlags(Intent.FLAG_GRANT_WRITE_URI_PERMISSION)
        }
        try { activity.startActivityForResult(intent, REQUEST) }
        catch (_: Exception) { finishError("unavailable") }
    }
    fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        if (requestCode != REQUEST) return false
        if (result == null) return true
        if (resultCode == Activity.RESULT_CANCELED) { finish(if (saving) false else null); return true }
        val uri = data?.data
        if (resultCode != Activity.RESULT_OK || uri == null || uri.scheme != "content") {
            finishError("unavailable"); return true
        }
        val save = saving
        val bytes = content
        executor.execute {
            try {
                val answer: Any? = if (save) {
                    val expected = bytes ?: throw IOException()
                    activity.contentResolver.openOutputStream(uri, "wt")?.use {
                        it.write(expected)
                        it.flush()
                    } ?: throw IOException()
                    // Close and read back before acknowledging success, including provider truncation.
                    verify(uri, expected)
                    true
                } else read(uri)
                main.post { finish(answer) }
            } catch (_: TooLarge) { main.post { finishError("validation") }
            } catch (_: Exception) { main.post { finishError("unavailable") } }
        }
        return true
    }
    private class TooLarge : IOException()
    private fun read(uri: Uri): ByteArray {
        val output = ByteArrayOutputStream()
        activity.contentResolver.openInputStream(uri)?.use { input ->
            val buffer = ByteArray(65536)
            while (true) {
                val count = input.read(buffer)
                if (count < 0) break
                if (output.size().toLong() + count > MAX) throw TooLarge()
                output.write(buffer, 0, count)
            }
        } ?: throw IOException()
        if (output.size() == 0) throw TooLarge()
        return output.toByteArray()
    }
    private fun verify(uri: Uri, expected: ByteArray) {
        activity.contentResolver.openInputStream(uri)?.use { input ->
            val buffer = ByteArray(65536)
            var offset = 0
            while (true) {
                val count = input.read(buffer)
                if (count < 0) break
                if (offset.toLong() + count > expected.size) throw IOException()
                for (i in 0 until count) if (buffer[i] != expected[offset + i]) throw IOException()
                offset += count
            }
            if (offset != expected.size) throw IOException()
        } ?: throw IOException()
    }
    private fun finish(value: Any?) {
        val pending = result
        result = null; content = null
        if (!closed) pending?.success(value)
    }
    private fun finishError(code: String) {
        val pending = result
        result = null; content = null
        if (!closed) pending?.error(code, "文件读写未完成，请检查权限与可用空间", null)
    }
    fun close() {
        finishError("cancelled")
        closed = true
        channel.setMethodCallHandler(null)
        executor.shutdownNow()
    }
}
