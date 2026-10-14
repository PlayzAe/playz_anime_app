# R8 rules for the release build.
#
# Flutter's own Dart code is AOT-compiled by the engine and is not touched by
# R8; this file only protects the Java/Kotlin layers that the plugins bring in
# and that reach the native side through reflection or JNI.

# ── Flutter engine ───────────────────────────────────────────────────────────
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }
-dontwarn io.flutter.embedding.**

# The Play Store split-install machinery Flutter injects; harmless to keep.
-keep class io.flutter.app.FlutterPlayStoreSplitApplication { *; }

# ── Plugins ──────────────────────────────────────────────────────────────────
# video_player / ExoPlayer: the media session and player classes are built by
# name from the platform side.
-keep class com.google.android.exoplayer2.** { *; }
-keep class androidx.media3.** { *; }
-dontwarn com.google.android.exoplayer2.**

# share_plus, file_picker, url_launcher, connectivity_plus, wakelock_plus and
# path_provider are all reached through the generated plugin registrant, which
# names them reflectively.
-keep class dev.fluttercommunity.plus.** { *; }
-keep class com.mr.flutter.plugin.filepicker.** { *; }
-keep class io.flutter.plugins.urllauncher.** { *; }
-keep class io.flutter.plugins.pathprovider.** { *; }

# Kotlin metadata and coroutines: R8 likes to strip the builders the plugins use.
-keep class kotlin.Metadata { *; }
-keepclassmembers class kotlinx.coroutines.** { volatile <fields>; }
-keepclassmembers class kotlin.coroutines.** { *; }
-dontwarn kotlinx.coroutines.**

# ── Desugaring ───────────────────────────────────────────────────────────────
-dontwarn java.lang.invoke.**
-dontwarn java.time.**

# Keep the line numbers so a crash report from a sideloaded build is readable.
-keepattributes SourceFile,LineNumberTable
-renamesourcefileattribute SourceFile

# ── Mihon extension host ─────────────────────────────────────────────────────
# Extension APKs are loaded at runtime and link against these classes by name, so
# R8 must keep their public API intact. Taken from Mihon (Apache-2.0).
# Types extensions implement, extend or construct
-keep class eu.kanade.tachiyomi.source.Source { public protected *; }
-keep class eu.kanade.tachiyomi.source.Source$DefaultImpls { public protected *; }
-keep class eu.kanade.tachiyomi.source.CatalogueSource { public protected *; }
-keep class eu.kanade.tachiyomi.source.CatalogueSource$DefaultImpls { public protected *; }
-keep class eu.kanade.tachiyomi.source.ConfigurableSource { public protected *; }
-keep class eu.kanade.tachiyomi.source.SourceFactory { public protected *; }
-keep class eu.kanade.tachiyomi.source.UnmeteredSource { public protected *; }
-keep class eu.kanade.tachiyomi.source.model.Filter { public protected *; }
-keep class eu.kanade.tachiyomi.source.model.Filter$* { public protected *; }
-keep class eu.kanade.tachiyomi.source.model.FilterList { public protected *; }
-keep class eu.kanade.tachiyomi.source.model.MangasPage { public protected *; }
-keep class eu.kanade.tachiyomi.source.model.Page { public protected *; }
-keep class eu.kanade.tachiyomi.source.model.SChapter { public protected *; }
-keep class eu.kanade.tachiyomi.source.model.SChapter$Companion { public protected *; }
-keep class eu.kanade.tachiyomi.source.model.SManga { public protected *; }
-keep class eu.kanade.tachiyomi.source.model.SManga$Companion { public protected *; }
-keep class eu.kanade.tachiyomi.source.model.SMangaUpdate { public protected *; }
-keep class eu.kanade.tachiyomi.source.model.UpdateStrategy { public protected *; }
-keep class eu.kanade.tachiyomi.source.online.HttpSource { public protected *; }
-keep class eu.kanade.tachiyomi.source.online.ParsedHttpSource { public protected *; }

# Final classes and top-level functions extensions only call into
-keep,allowoptimization class eu.kanade.tachiyomi.AppInfo { public protected *; }
-keep,allowoptimization class eu.kanade.tachiyomi.network.HttpException { public protected *; }
-keep,allowoptimization class eu.kanade.tachiyomi.network.JavaScriptEngine { public protected *; }
-keep,allowoptimization class eu.kanade.tachiyomi.network.NetworkHelper { public protected *; }
-keep,allowoptimization class eu.kanade.tachiyomi.network.OkHttpExtensionsKt { public protected *; }
-keep,allowoptimization class eu.kanade.tachiyomi.network.RequestsKt { public protected *; }
-keep,allowoptimization class eu.kanade.tachiyomi.network.interceptor.RateLimitInterceptorKt { public protected *; }
-keep,allowoptimization class eu.kanade.tachiyomi.network.interceptor.SpecificHostRateLimitInterceptorKt { public protected *; }
-keep,allowoptimization class eu.kanade.tachiyomi.util.JsoupExtensionsKt { public protected *; }
-keep class eu.kanade.tachiyomi.** { public protected *; }
-keep class tachiyomi.core.common.util.lang.** { public protected *; }
-keep class tv.playzae.playzanime.** { *; }
-dontwarn sun.misc.**
-dontwarn org.conscrypt.**
-dontwarn org.bouncycastle.**
-dontwarn org.openjsse.**
-dontwarn com.oracle.svm.**
-dontwarn org.jspecify.**
-dontwarn com.google.re2j.**
-keepattributes Signature, *Annotation*, InnerClasses, EnclosingMethod
-keepclassmembers class rx.internal.util.unsafe.*ArrayQueue*Field* { long producerIndex; long consumerIndex; }
-keepclassmembers class kotlinx.serialization.json.** { *** Companion; }

# Final classes and top-level functions extensions call into (Mihon app rules).
-keep,allowoptimization class eu.kanade.tachiyomi.AppInfo { public protected *; }
-keep,allowoptimization class eu.kanade.tachiyomi.network.** { public protected *; }
-keep,allowoptimization class eu.kanade.tachiyomi.util.** { public protected *; }
-keepattributes Signature
-keep,allowshrinking class * extends uy.kohesive.injekt.api.FullTypeReference

# Libraries extensions are compiled against but don't ship: keep their public API.
-keep,allowoptimization class androidx.preference.** { public protected *; }
-keep,allowoptimization class kotlin.** { public protected *; }
-keep,allowoptimization class kotlinx.coroutines.** { public protected *; }
-keep,allowoptimization class kotlinx.serialization.** { public protected *; }
-keep,allowoptimization class okhttp3.** { public protected *; }
-keep,allowoptimization class okio.** { public protected *; }
-keep,allowoptimization class org.jsoup.** { public protected *; }
-keep,allowoptimization class rx.** { public protected *; }
-keep,allowoptimization class uy.kohesive.injekt.** { public protected *; }
-keep,allowoptimization class com.squareup.zstd.** { public protected *; }
-keepclasseswithmembers class kotlinx.serialization.json.** { kotlinx.serialization.KSerializer serializer(...); }
-keepclassmembers class * implements java.io.Serializable { java.lang.Object writeReplace(); java.lang.Object readResolve(); }
-dontwarn androidx.window.extensions.**
-dontwarn androidx.window.sidecar.**

# Extensions reach private Kotlin members too (e.g. HttpSource.headers$delegate): keep the API whole, no renaming or removal.
-keep class eu.kanade.tachiyomi.** { *; }
-keep class tachiyomi.** { *; }
-keepclassmembers class eu.kanade.tachiyomi.** { *; }
