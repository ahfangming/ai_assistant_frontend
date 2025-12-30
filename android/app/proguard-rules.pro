# Google ML Kit Text Recognition
-keep class com.google.mlkit.vision.text.** { *; }
-keep class com.google.android.gms.internal.** { *; }

# Keep all ML Kit language models
-dontwarn com.google.mlkit.vision.text.chinese.**
-dontwarn com.google.mlkit.vision.text.devanagari.**
-dontwarn com.google.mlkit.vision.text.japanese.**
-dontwarn com.google.mlkit.vision.text.korean.**
