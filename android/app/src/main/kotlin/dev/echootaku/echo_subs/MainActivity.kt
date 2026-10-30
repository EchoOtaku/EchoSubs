package dev.echootaku.echo_subs

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    private var reminderPersistence: ReminderPersistenceChannel? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        reminderPersistence?.close()
        reminderPersistence = ReminderPersistenceChannel(this, flutterEngine.dartExecutor.binaryMessenger)
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        reminderPersistence?.close()
        reminderPersistence = null
        super.cleanUpFlutterEngine(flutterEngine)
    }
}
