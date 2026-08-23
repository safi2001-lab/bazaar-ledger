# R8 is on for release. Flutter's own engine classes are kept by the plugin's
# bundled rules; these cover the plugins this app links against.

# --- SQLite (drift / sqlite3_flutter_libs) ---------------------------------
-keep class org.sqlite.** { *; }
-keep class com.tekartik.sqflite.** { *; }

# --- share_plus / path_provider -------------------------------------------
-keep class androidx.core.content.FileProvider { *; }

# Play Core is referenced by Flutter's deferred-components hooks even when the
# feature is unused. Without these, R8 warns and the build is noisier than it
# needs to be.
-dontwarn com.google.android.play.core.**

# Keep annotations that runtime reflection depends on.
-keepattributes *Annotation*, Signature, InnerClasses, EnclosingMethod

# Line numbers make a Play Console crash report readable; the source file name
# itself is stripped.
-keepattributes SourceFile,LineNumberTable
-renamesourcefileattribute SourceFile
