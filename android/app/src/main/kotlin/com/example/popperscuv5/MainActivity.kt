package com.example.popperscuv5

import android.content.ContentValues
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import androidx.annotation.NonNull
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity: FlutterActivity() {
    private val CHANNEL = "pdv/files"

    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "saveToDownloads" -> {
                    val filename = call.argument<String>("filename") ?: run {
                        result.error("ARG", "filename requerido", null); return@setMethodCallHandler
                    }
                    val bytes = call.argument<ByteArray>("bytes") ?: run {
                        result.error("ARG", "bytes requeridos", null); return@setMethodCallHandler
                    }
                    val mime = call.argument<String>("mime")
                        ?: "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"

                    try {
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                            val resolver = applicationContext.contentResolver
                            val values = ContentValues().apply {
                                put(MediaStore.Downloads.DISPLAY_NAME, filename)
                                put(MediaStore.Downloads.MIME_TYPE, mime)
                            }
                            val collection = MediaStore.Downloads.getContentUri(MediaStore.VOLUME_EXTERNAL_PRIMARY)
                            val uri = resolver.insert(collection, values)
                                ?: throw Exception("No se pudo crear entrada en MediaStore")
                            resolver.openOutputStream(uri)?.use { it.write(bytes) }
                                ?: throw Exception("No se pudo abrir OutputStream")
                            result.success(uri.toString()) // content:// URI
                        } else {
                            // API < 29: usa almacenamiento externo directo
                            val dir = Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS)
                            if (!dir.exists()) dir.mkdirs()
                            val file = File(dir, filename)
                            file.outputStream().use { it.write(bytes) }
                            result.success(file.absolutePath)
                        }
                    } catch (e: Exception) {
                        result.error("IO", e.message, null)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }
}