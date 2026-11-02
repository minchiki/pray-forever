# MediaPipe Tasks: нативный код обращается к Java-классам и protobuf по именам.
-keep class com.google.mediapipe.** { *; }
-keep class com.google.protobuf.** { *; }
-dontwarn com.google.mediapipe.proto.**
-dontwarn com.google.auto.value.**
-dontwarn javax.annotation.processing.**
-dontwarn javax.lang.model.**
# MediaPipe логирует через Flogger: FluentLogger.forEnclosingClass() ищет свои классы на стеке по имени.
-keep class com.google.common.flogger.** { *; }
-dontwarn com.google.common.flogger.**
