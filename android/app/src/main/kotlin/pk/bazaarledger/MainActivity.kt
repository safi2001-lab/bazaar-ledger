package pk.bazaarledger

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // The key the books are encrypted with. Asked for once, before the
        // database opens; an error answers "no key", and the books then open
        // in the clear rather than not at all.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "pk.bazaarledger/books_key")
            .setMethodCallHandler { call, result ->
                if (call.method != "databaseKey") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                try {
                    result.success(BooksKey(applicationContext.noBackupFilesDir).hex())
                } catch (e: Exception) {
                    result.error("unavailable", e.message, null)
                }
            }
    }
}
