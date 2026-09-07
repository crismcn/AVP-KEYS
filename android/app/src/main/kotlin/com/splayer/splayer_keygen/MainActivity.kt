package com.splayer.splayer_keygen

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.provider.OpenableColumns
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    // 「导入密钥」= 系统文件选择器（SAF）。自实现避免了 file_picker
    // 等原生插件在 AGP 9 / 内置 Kotlin 工具链下的构建问题，零额外依赖。
    private val pickRequest = 8123
    private var pending: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "splayer.keygen/file_pick",
        ).setMethodCallHandler { call, result ->
            if (call.method == "pickText") {
                pending = result
                startActivityForResult(
                    Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
                        addCategory(Intent.CATEGORY_OPENABLE)
                        type = "*/*"
                    },
                    pickRequest,
                )
            } else {
                result.notImplemented()
            }
        }
    }

    @Suppress("DEPRECATION") // startActivityForResult 对本工具足够，且不依赖 androidx activity 结果 API
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (requestCode == pickRequest) {
            val reply = pending
            pending = null
            val uri = data?.data
            if (resultCode == Activity.RESULT_OK && uri != null) {
                reply?.success(readKeyFile(uri))
            } else {
                reply?.success(mapOf("cancelled" to true)) // 用户取消
            }
        } else {
            super.onActivityResult(requestCode, resultCode, data)
        }
    }

    /// 读取所选文件的文本内容；成功返回 {text, name}，失败返回 {error}。
    private fun readKeyFile(uri: Uri): Map<String, Any> {
        return try {
            val resolver = contentResolver
            val name = resolver.query(
                uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null,
            )?.use { c -> if (c.moveToFirst()) c.getString(0) else null }
            val text = resolver.openInputStream(uri)?.bufferedReader()?.use { it.readText() }
            if (text == null) mapOf("error" to "读取所选文件失败")
            else mapOf("text" to text, "name" to (name ?: ""))
        } catch (e: Exception) {
            mapOf("error" to "文件读取失败：${e.message}")
        }
    }
}
