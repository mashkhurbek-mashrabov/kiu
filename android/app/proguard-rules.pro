# R8 keep rules for KIU.
#
# Scope matters here. An over-broad `-keep class pkg.** { *; }` does not just
# fail to shrink -- combined with proguard-android-optimize it measurably grows
# the dex. So keep only what is genuinely reached by *name* (manifest
# instantiation, reflection), and let R8 shrink everything else.

# --- Components named in AndroidManifest.xml -------------------------------
# Instantiated reflectively by the framework, so the class and its no-arg
# constructor must survive. Their *members* do not need keeping.
-keep class com.mashkhurbek.kiu.MainActivity
-keep class com.mashkhurbek.kiu.LessonCallActivity
-keep class com.mashkhurbek.kiu.LessonCallReceiver
-keep class com.mashkhurbek.kiu.LessonCallBootReceiver
-keep class com.mashkhurbek.kiu.KiuLessonWidgetProvider
-keep class com.mashkhurbek.kiu.KiuLessonWidgetService

# Android instantiates every manifest component through its default
# constructor; without this R8 may strip the constructor itself.
-keepclassmembers class com.mashkhurbek.kiu.** {
  public <init>(...);
}

# The update installer's FileProvider is named in AndroidManifest.xml, so R8
# cannot see the reference. Without this the provider is stripped and
# getUriForFile fails at runtime with no build-time warning.
-keep class androidx.core.content.FileProvider

# home_widget's background receiver is named in the manifest, and the plugin
# resolves its prefs accessor by name from the widget provider.
-keep class es.antonborri.home_widget.HomeWidgetBackgroundReceiver
-keep class es.antonborri.home_widget.HomeWidgetScheduledUpdateReceiver
-keep class es.antonborri.home_widget.HomeWidgetPlugin { *; }
-keep class es.antonborri.home_widget.HomeWidgetProvider

# flutter_local_notifications names its receivers in the manifest and
# round-trips its persisted models through Gson (reflection-driven).
-keep class com.dexterous.flutterlocalnotifications.ScheduledNotificationReceiver
-keep class com.dexterous.flutterlocalnotifications.ScheduledNotificationBootReceiver
-keep class com.dexterous.flutterlocalnotifications.models.** { *; }
-keepattributes Signature, *Annotation*
-keep class * extends com.google.gson.TypeAdapter
-keep class * implements com.google.gson.TypeAdapterFactory
-keepclassmembers,allowobfuscation class * {
  @com.google.gson.annotations.SerializedName <fields>;
}

# WorkManager instantiates Worker subclasses by class name.
-keep class * extends androidx.work.ListenableWorker {
  public <init>(...);
}

# Flutter's embedding references Play Core for deferred components. KIU does
# not use deferred components and does not depend on Play Core, so those
# classes are legitimately absent -- without this R8 treats the dangling
# references as a hard error and refuses to build.
-dontwarn com.google.android.play.core.**
