package com.signalscope.app

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {

    private var channelHandler: NativeChannelHandler? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        channelHandler?.dispose()
        channelHandler = NativeChannelHandler(this, flutterEngine.dartExecutor.binaryMessenger).also {
            it.register()
        }
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        // Unregister every system listener so nothing leaks past the engine.
        channelHandler?.dispose()
        channelHandler = null
        super.cleanUpFlutterEngine(flutterEngine)
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        channelHandler?.onRequestPermissionsResult(requestCode, permissions)
    }
}
