package com.brr.brr

import android.content.pm.PackageManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // ช่องทางอ่าน Google Maps API key จาก manifest meta-data —
        // Dart ฝั่ง thumbnail ดาวเทียมใช้เรียก Static Maps API
        // key อยู่ใน local.properties เท่านั้น ไม่ hardcode ในโค้ด
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "brr/maps")
            .setMethodCallHandler { call, result ->
                if (call.method == "apiKey") {
                    val info = packageManager.getApplicationInfo(
                        packageName,
                        PackageManager.GET_META_DATA,
                    )
                    result.success(
                        info.metaData?.getString("com.google.android.geo.API_KEY"),
                    )
                } else {
                    result.notImplemented()
                }
            }
    }
}
