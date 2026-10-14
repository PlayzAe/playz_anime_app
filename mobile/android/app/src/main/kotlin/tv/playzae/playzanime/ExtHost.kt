package tv.playzae.playzanime

import android.app.Application
import android.content.Context
import android.content.pm.PackageInfo
import android.content.pm.PackageManager
import android.os.Build
import android.util.Log
import dalvik.system.DelegateLastClassLoader
import dalvik.system.PathClassLoader
import eu.kanade.tachiyomi.network.GET
import eu.kanade.tachiyomi.network.JavaScriptEngine
import eu.kanade.tachiyomi.network.NetworkHelper
import eu.kanade.tachiyomi.source.CatalogueSource
import eu.kanade.tachiyomi.source.Source
import eu.kanade.tachiyomi.source.SourceFactory
import eu.kanade.tachiyomi.source.model.FilterList
import eu.kanade.tachiyomi.source.model.MangasPage
import eu.kanade.tachiyomi.source.model.Page
import eu.kanade.tachiyomi.source.model.SChapter
import eu.kanade.tachiyomi.source.model.SManga
import eu.kanade.tachiyomi.source.online.HttpSource
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.serialization.json.Json
import okhttp3.Request
import org.json.JSONArray
import org.json.JSONObject
import uy.kohesive.injekt.Injekt
import uy.kohesive.injekt.api.addSingleton
import uy.kohesive.injekt.api.addSingletonFactory
import uy.kohesive.injekt.api.get
import java.io.File
import java.security.MessageDigest

/**
 * Runs real Mihon/Tachiyomi extension APKs inside PlayzAnime.
 *
 * Extensions are downloaded into the app's private storage and loaded with a class
 * loader whose parent is this app, so the `eu.kanade.tachiyomi.*`, OkHttp, Jsoup,
 * RxJava, Injekt and kotlinx.serialization classes they were compiled against come
 * from here. Nothing is installed as a separate Android app, so no install prompt.
 *
 * Built for hundreds of installs: startup only reads `manifest.json`; a package's
 * code is loaded the first time one of its sources is used.
 */
object ExtHost {
    private const val TAG = "PlayzExt"
    private const val FEATURE = "tachiyomi.extension"
    private const val META_CLASS = "tachiyomi.extension.class"
    private const val META_NSFW = "tachiyomi.extension.nsfw"
    private const val META_LIB = "tachiyomix.extensionLib"
    private val LIB_RANGE = 1.2..1.69

    private lateinit var app: Application
    private var ready = false

    /** Source id -> live source, for packages whose code is loaded. */
    private val sources = java.util.concurrent.ConcurrentHashMap<Long, CatalogueSource>()
    /** Source id -> package, from the manifest (loaded or not). */
    private val sourcePkg = java.util.concurrent.ConcurrentHashMap<Long, String>()
    /** Package -> summary, persisted in manifest.json. */
    private val packages = linkedMapOf<String, JSONObject>()
    private val loadedPkgs = hashSetOf<String>()

    private val dir by lazy { File(app.filesDir, "exts").apply { mkdirs() } }
    private val manifest by lazy { File(dir, "manifest.json") }
    private val imgDir by lazy { File(app.cacheDir, "ext-img").apply { mkdirs() } }

    @Synchronized
    fun init(application: Application) {
        if (ready) return
        app = application
        Injekt.addSingleton<Application>(app)
        Injekt.addSingleton<Context>(app)
        Injekt.addSingletonFactory { NetworkHelper(app) }
        Injekt.addSingletonFactory { JavaScriptEngine(app) }
        Injekt.addSingletonFactory {
            Json {
                ignoreUnknownKeys = true
                explicitNulls = false
            }
        }
        ready = true
        runCatching {
            if (manifest.exists()) {
                val arr = JSONArray(manifest.readText())
                for (i in 0 until arr.length()) remember(arr.getJSONObject(i))
            }
        }.onFailure { Log.e(TAG, "manifest", it) }
        // An apk with no manifest entry (older build, or a crash mid-write) is read once now.
        dir.listFiles { f -> f.name.endsWith(".apk") }?.forEach { file ->
            if (file.nameWithoutExtension !in packages) {
                runCatching { remember(load(file)) }.onFailure { Log.e(TAG, "load ${file.name}", it) }
            }
        }
        save()
    }

    private val network: NetworkHelper get() = Injekt.get()

    private fun remember(summary: JSONObject) {
        val pkg = summary.getString("pkg")
        packages[pkg] = summary
        val list = summary.optJSONArray("sources") ?: JSONArray()
        for (i in 0 until list.length()) {
            sourcePkg[list.getJSONObject(i).getString("id").toLong()] = pkg
        }
    }

    @Synchronized
    private fun save() {
        val arr = JSONArray()
        packages.values.forEach { arr.put(it) }
        val tmp = File(dir, "manifest.tmp")
        tmp.writeText(arr.toString())
        tmp.renameTo(manifest)
    }

    fun installed(): List<Map<String, Any?>> = packages.values.map { toMap(it) }

    /** Downloads [url] and loads it. Returns the package summary, or throws with a readable reason. */
    fun install(url: String, pkg: String): Map<String, Any?> {
        val tmp = File(dir, "$pkg.tmp")
        network.client.newCall(GET(url)).execute().use { res ->
            if (!res.isSuccessful) throw IllegalStateException("Download failed (HTTP ${res.code})")
            tmp.outputStream().use { out -> res.body.byteStream().copyTo(out) }
        }
        // Check the new file loads before replacing a working older version.
        val probe = File(dir, "$pkg.new.apk")
        tmp.renameTo(probe)
        probe.setReadOnly()
        val summary = try {
            load(probe, register = false)
        } catch (e: Throwable) {
            probe.setWritable(true)
            probe.delete()
            throw e
        }
        val real = summary.getString("pkg")
        synchronized(this) {
            drop(real)
            val file = File(dir, "$real.apk")
            if (file.exists()) {
                file.setWritable(true)
                file.delete()
            }
            if (!probe.renameTo(file)) throw IllegalStateException("Could not save the extension")
            summary.put("file", file.name)
            remember(summary)
            save()
        }
        return toMap(summary)
    }

    @Synchronized
    fun uninstall(pkg: String) {
        drop(pkg)
        packages.remove(pkg)
        File(dir, "$pkg.apk").let {
            if (it.exists()) {
                it.setWritable(true)
                it.delete()
            }
        }
        save()
    }

    /** Forgets the live sources of [pkg] so the next use loads the current apk. */
    private fun drop(pkg: String) {
        loadedPkgs.remove(pkg)
        sourcePkg.filterValues { it == pkg }.keys.forEach {
            sources.remove(it)
            sourcePkg.remove(it)
        }
    }

    @Synchronized
    private fun ensureLoaded(pkg: String) {
        if (pkg in loadedPkgs) return
        val file = File(dir, "$pkg.apk")
        if (!file.exists()) throw IllegalStateException("Extension not installed")
        load(file, register = true)
        loadedPkgs += pkg
    }

    @Suppress("DEPRECATION")
    private fun load(file: File, register: Boolean = true): JSONObject {
        val pm = app.packageManager
        val flags = PackageManager.GET_CONFIGURATIONS or PackageManager.GET_META_DATA
        val info: PackageInfo = pm.getPackageArchiveInfo(file.absolutePath, flags)
            ?: throw IllegalStateException("Not a valid extension file")
        val appInfo = info.applicationInfo ?: throw IllegalStateException("Malformed extension")
        appInfo.sourceDir = appInfo.sourceDir ?: file.absolutePath
        appInfo.publicSourceDir = appInfo.publicSourceDir ?: file.absolutePath
        val pkg = info.packageName
        val meta = appInfo.metaData ?: throw IllegalStateException("Malformed extension")
        if (info.reqFeatures.orEmpty().none { it.name == FEATURE }) {
            throw IllegalStateException("Not a Mihon extension")
        }
        val version = info.versionName.orEmpty()
        val lib = meta.getFloat(META_LIB).takeUnless { it == 0f }?.toString()?.toDouble()
            ?: version.substringBeforeLast('.').toDoubleOrNull()
        if (lib == null || lib !in LIB_RANGE) {
            throw IllegalStateException("Extension library $lib is not supported")
        }
        val name = pm.getApplicationLabel(appInfo).toString().substringAfter("Tachiyomi: ")
        val loader = if (Build.VERSION.SDK_INT >= 27) {
            DelegateLastClassLoader(file.absolutePath, null, app.classLoader)
        } else {
            PathClassLoader(file.absolutePath, null, app.classLoader)
        }
        val classes = meta.getString(META_CLASS)?.split(";")?.map { it.trim() }?.filter { it.isNotEmpty() }
            ?: throw IllegalStateException("Malformed extension")
        val loaded = classes.flatMap { cls ->
            val full = if (cls.startsWith(".")) pkg + cls else cls
            when (val obj = Class.forName(full, false, loader).getDeclaredConstructor().newInstance()) {
                is Source -> listOf(obj)
                is SourceFactory -> obj.createSources()
                else -> emptyList()
            }
        }.filterIsInstance<CatalogueSource>()
        if (loaded.isEmpty()) throw IllegalStateException("Extension has no catalogue sources")
        if (register) {
            loaded.forEach {
                sources[it.id] = it
                sourcePkg[it.id] = pkg
            }
        }
        val code = if (Build.VERSION.SDK_INT >= 28) info.longVersionCode else info.versionCode.toLong()
        return JSONObject().apply {
            put("pkg", pkg)
            put("name", name)
            put("version", version)
            put("versionCode", code)
            put("nsfw", meta.getInt(META_NSFW) == 1)
            put("sources", JSONArray(loaded.map { JSONObject(describe(it)) }))
        }
    }

    private fun describe(s: CatalogueSource): Map<String, Any?> = mapOf(
        "id" to s.id.toString(),
        "name" to s.name,
        "lang" to s.lang,
        "baseUrl" to (s as? HttpSource)?.baseUrl,
        "supportsLatest" to s.supportsLatest,
    )

    private fun toMap(o: JSONObject): Map<String, Any?> {
        val list = o.optJSONArray("sources") ?: JSONArray()
        return mapOf(
            "pkg" to o.optString("pkg"),
            "name" to o.optString("name"),
            "version" to o.optString("version"),
            "versionCode" to o.optLong("versionCode"),
            "nsfw" to o.optBoolean("nsfw"),
            "sources" to (0 until list.length()).map { i ->
                val s = list.getJSONObject(i)
                mapOf(
                    "id" to s.optString("id"),
                    "name" to s.optString("name"),
                    "lang" to s.optString("lang"),
                    "baseUrl" to s.optString("baseUrl"),
                    "supportsLatest" to s.optBoolean("supportsLatest"),
                )
            },
        )
    }

    private fun source(id: Any?): CatalogueSource {
        val key = id.toString().toLong()
        sources[key]?.let { return it }
        val pkg = sourcePkg[key] ?: throw IllegalStateException("Extension not installed")
        ensureLoaded(pkg)
        return sources[key] ?: throw IllegalStateException("Extension not installed")
    }

    private fun SManga.toMap(): Map<String, Any?> = mapOf(
        "url" to url,
        "title" to title,
        "thumbnail" to thumbnail_url,
        "description" to description,
        "author" to author,
        "artist" to artist,
        "genre" to genre,
        "status" to status,
    )

    private fun MangasPage.toMap() = mapOf(
        "mangas" to mangas.map { it.toMap() },
        "hasNextPage" to hasNextPage,
    )

    suspend fun popular(id: Any?, page: Int) = source(id).getPopularManga(page).toMap()

    suspend fun latest(id: Any?, page: Int) = source(id).getLatestUpdates(page).toMap()

    suspend fun search(id: Any?, query: String, page: Int): Map<String, Any?> {
        val s = source(id)
        return s.getSearchManga(page, query, if (query.isBlank()) s.getFilterList() else FilterList()).toMap()
    }

    private fun manga(url: String, title: String?) = SManga.create().apply {
        this.url = url
        this.title = title.orEmpty()
    }

    /**
     * Extensions on lib 1.6 refuse two getMangaUpdate calls for the same title
     * at once, so every call for a title goes through one lock.
     */
    private val locks = java.util.concurrent.ConcurrentHashMap<String, Mutex>()

    private suspend fun <T> locked(id: Any?, url: String, block: suspend () -> T): T =
        locks.getOrPut("$id|$url") { Mutex() }.withLock { block() }

    private fun SChapter.toMap(): Map<String, Any?> = mapOf(
        "url" to url,
        "name" to name,
        "number" to chapter_number.toDouble(),
        "date" to date_upload,
        "scanlator" to scanlator,
    )

    /** Details and chapters in one call, the way Mihon asks for them. */
    suspend fun update(id: Any?, url: String, title: String?, details: Boolean, chapters: Boolean): Map<String, Any?> =
        locked(id, url) {
            val m = manga(url, title)
            val u = source(id).getMangaUpdate(m, emptyList(), fetchDetails = details, fetchChapters = chapters)
            val d = u.manga
            d.url = url
            if (runCatching { d.title }.getOrNull().isNullOrEmpty()) d.title = m.title
            mapOf(
                "manga" to if (details) d.toMap() else null,
                "chapters" to if (chapters) u.chapters.map { it.toMap() } else null,
            )
        }

    @Suppress("UNCHECKED_CAST")
    suspend fun details(id: Any?, url: String, title: String?): Map<String, Any?> =
        update(id, url, title, details = true, chapters = false)["manga"] as Map<String, Any?>

    @Suppress("UNCHECKED_CAST")
    suspend fun chapters(id: Any?, url: String, title: String?): List<Map<String, Any?>> =
        update(id, url, title, details = false, chapters = true)["chapters"] as List<Map<String, Any?>>

    suspend fun pages(id: Any?, url: String, name: String?): List<Map<String, Any?>> {
        val ch = SChapter.create().apply {
            this.url = url
            this.name = name.orEmpty()
        }
        return source(id).getPageList(ch).map {
            mapOf("index" to it.index, "url" to it.url, "imageUrl" to it.imageUrl)
        }
    }

    /**
     * Fetches one page image through the source's own client, so its headers,
     * cookies and any de-scrambling interceptor apply. Returns a cached file path.
     */
    suspend fun image(id: Any?, index: Int, url: String?, imageUrl: String?): String {
        val s = source(id) as? HttpSource ?: throw IllegalStateException("Source has no images")
        val key = sha1("${s.id}|${url.orEmpty()}|${imageUrl.orEmpty()}")
        val out = File(imgDir, key)
        if (out.exists() && out.length() > 0) return out.absolutePath
        val page = Page(index, url.orEmpty(), imageUrl)
        if (page.imageUrl.isNullOrEmpty()) page.imageUrl = s.getImageUrl(page)
        s.getImage(page).use {
            if (!it.isSuccessful) throw IllegalStateException("Image failed (HTTP ${it.code})")
            val tmp = File(imgDir, "$key.part")
            tmp.outputStream().use { o -> it.body.byteStream().copyTo(o) }
            tmp.renameTo(out)
        }
        trimCache()
        return out.absolutePath
    }

    /** A cover or any plain URL fetched with the source's headers. */
    fun fetch(id: Any?, url: String): String {
        val s = source(id) as? HttpSource ?: throw IllegalStateException("Source has no images")
        val key = sha1("${s.id}|cover|$url")
        val out = File(imgDir, key)
        if (out.exists() && out.length() > 0) return out.absolutePath
        s.client.newCall(Request.Builder().url(url).headers(s.headers).build()).execute().use {
            if (!it.isSuccessful) throw IllegalStateException("Image failed (HTTP ${it.code})")
            val tmp = File(imgDir, "$key.part")
            tmp.outputStream().use { o -> it.body.byteStream().copyTo(o) }
            tmp.renameTo(out)
        }
        trimCache()
        return out.absolutePath
    }

    fun headers(id: Any?): Map<String, String> =
        (source(id) as? HttpSource)?.headers?.toMap() ?: emptyMap()

    private var trims = 0
    private fun trimCache() {
        if (++trims % 40 != 0) return
        val files = imgDir.listFiles()?.sortedBy { it.lastModified() } ?: return
        var total = files.sumOf { it.length() }
        val cap = 300L * 1024 * 1024
        for (f in files) {
            if (total <= cap) break
            total -= f.length()
            f.delete()
        }
    }

    private fun sha1(s: String): String =
        MessageDigest.getInstance("SHA-1").digest(s.toByteArray()).joinToString("") { "%02x".format(it) }
}
