package io.github.omashishsoni.mocode

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {

    private var daemonBridge: DaemonBridge? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        daemonBridge = DaemonBridge(this, flutterEngine.dartExecutor.binaryMessenger)
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        daemonBridge?.dispose()
        daemonBridge = null
        super.cleanUpFlutterEngine(flutterEngine)
    }
}
