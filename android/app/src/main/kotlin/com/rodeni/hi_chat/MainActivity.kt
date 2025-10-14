package com.rodeni.hi_chat

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    private lateinit var smsPlugin: SmsPlugin

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        
        // Initialize SMS plugin
        smsPlugin = SmsPlugin(this)
        smsPlugin.initialize(flutterEngine)
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (::smsPlugin.isInitialized) {
            smsPlugin.onRequestPermissionsResult(requestCode, permissions, grantResults)
        }
    }
}