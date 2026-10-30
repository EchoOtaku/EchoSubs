package dev.echootaku.echo_subs

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import android.content.Intent

class MainActivity : FlutterActivity() {
    private var reminderPersistence: ReminderPersistenceChannel? = null
    private var documentAccess: DocumentAccess? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        reminderPersistence?.close()
        reminderPersistence = ReminderPersistenceChannel(this, flutterEngine.dartExecutor.binaryMessenger)
        documentAccess?.close()
        documentAccess = DocumentAccess(this, flutterEngine.dartExecutor.binaryMessenger)
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        reminderPersistence?.close()
        reminderPersistence = null
        documentAccess?.close()
        documentAccess = null
        super.cleanUpFlutterEngine(flutterEngine)
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (documentAccess?.onActivityResult(requestCode, resultCode, data) == true) return
        super.onActivityResult(requestCode, resultCode, data)
    }
}
