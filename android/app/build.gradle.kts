import java.io.File
import java.net.URI
import java.security.MessageDigest

plugins {
    alias(libs.plugins.android.application)
    alias(libs.plugins.kotlin.android)
    alias(libs.plugins.kotlin.compose)
    alias(libs.plugins.kotlin.serialization)
}

// Корень репозитория: Android берёт звуки, шрифт и строки из iOS-ресурсов, чтобы не держать копии.
val repoRoot: File = rootDir.parentFile
val sharedResources = File(repoRoot, "Sajda/Resources")

// Версия одна на обе платформы — файл VERSION в корне репозитория.
val appVersion: String = File(repoRoot, "VERSION").readText().trim()
val appVersionCode: Int =
    appVersion.split(".").map { it.toInt() }.let { (major, minor, patch) ->
        major * 10_000 + minor * 100 + patch
    }

// Секреты подписи: переменные окружения, локально — ещё и файл .env в корне репозитория (он в .gitignore).
// .env читается построчно, без Properties: там обратный слэш — экранирование и ломает пути Windows.
val dotEnv: Map<String, String> =
    File(repoRoot, ".env")
        .takeIf { it.isFile }
        ?.readLines()
        ?.map { it.trim() }
        ?.filter { it.isNotEmpty() && !it.startsWith("#") && "=" in it }
        ?.associate { it.substringBefore('=').trim() to it.substringAfter('=').trim() }
        .orEmpty()

fun secret(name: String): String? = (System.getenv(name) ?: dotEnv[name])?.trim()?.takeIf { it.isNotEmpty() }

val keystorePath = secret("ANDROID_KEYSTORE_PATH")
val hasReleaseSigning =
    keystorePath != null && File(keystorePath).isFile &&
        listOf("ANDROID_KEYSTORE_PASSWORD", "ANDROID_KEY_ALIAS", "ANDROID_KEY_PASSWORD").all { secret(it) != null }
if (!hasReleaseSigning) {
    logger.warn("Release signing is not configured (ANDROID_KEYSTORE_*): release APK/AAB will be unsigned")
}

android {
    namespace = "com.prayforever.app"
    compileSdk = 36

    defaultConfig {
        applicationId = "com.prayforever.app"
        minSdk = 26
        targetSdk = 36
        versionCode = appVersionCode
        versionName = appVersion
        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
    }

    signingConfigs {
        if (hasReleaseSigning) {
            create("release") {
                storeFile = File(keystorePath!!)
                storePassword = secret("ANDROID_KEYSTORE_PASSWORD")
                keyAlias = secret("ANDROID_KEY_ALIAS")
                keyPassword = secret("ANDROID_KEY_PASSWORD")
            }
        }
    }

    buildTypes {
        debug {
            applicationIdSuffix = ".debug"
            versionNameSuffix = "-debug"
        }
        release {
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
            // Без ключа релиз собирается неподписанным — его можно подписать позже apksigner'ом.
            signingConfig = signingConfigs.findByName("release")
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    buildFeatures {
        compose = true
        buildConfig = true
    }

    // ML Kit и MediaPipe тянут нативные библиотеки под каждую архитектуру: APK собираются раздельно.
    // AAB (для Google Play) раздаётся по архитектурам самим магазином.
    // При сборке AAB разбиение выключено: AGP не умеет и то и другое сразу (issuetracker 402800800).
    val buildingBundle = gradle.startParameter.taskNames.any { it.contains("bundle", ignoreCase = true) }
    splits {
        abi {
            isEnable = !buildingBundle
            reset()
            include("arm64-v8a", "armeabi-v7a", "x86_64")
            isUniversalApk = false
        }
    }

    sourceSets["main"].assets.srcDirs(
        File(sharedResources, "Sounds"),
        File(sharedResources, "Fonts"),
    )

    androidResources {
        noCompress += "tflite"
    }

    packaging {
        resources.excludes += "/META-INF/{AL2.0,LGPL2.1}"
    }

    lint {
        warningsAsErrors = false
        abortOnError = true
        checkReleaseBuilds = true
        disable += setOf("MissingTranslation", "GradleDependency", "NewerVersionAvailable", "AndroidGradlePluginVersion")
    }

    testOptions {
        unitTests.isReturnDefaultValues = true
    }
}

kotlin {
    compilerOptions {
        jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17)
    }
}

/**
 * Строки берутся из iOS-файлов Localizable.strings: ключ "a.b" становится "a_b", %@ — %s,
 * несколько подстановок — позиционные. Ключи, переопределённые в src/main/res, пропускаются.
 */
abstract class GenerateSharedStrings : DefaultTask() {
    @get:InputDirectory
    abstract val sourceDir: DirectoryProperty

    @get:InputDirectory
    abstract val overridesDir: DirectoryProperty

    @get:OutputDirectory
    abstract val outputDir: DirectoryProperty

    @TaskAction
    fun generate() {
        val locales = mapOf("en" to "values", "ru" to "values-ru")
        val out = outputDir.get().asFile
        out.deleteRecursively()
        for ((locale, folder) in locales) {
            val source = sourceDir.get().file("$locale.lproj/Localizable.strings").asFile
            val overrides = overridesDir.get().file("$folder/strings.xml").asFile
            val overridden =
                if (overrides.isFile) {
                    Regex("""<string name="([^"]+)"""").findAll(overrides.readText()).map { it.groupValues[1] }.toSet()
                } else {
                    emptySet()
                }
            val entries =
                Regex("""^"([^"]+)"\s*=\s*"((?:[^"\\]|\\.)*)";""", RegexOption.MULTILINE)
                    .findAll(source.readText())
                    .map { it.groupValues[1].substringBefore(' ').replace('.', '_') to it.groupValues[2] }
                    .filter { (key, _) -> key !in overridden }
                    .toList()
            val xml =
                buildString {
                    appendLine("""<?xml version="1.0" encoding="utf-8"?>""")
                    appendLine("<!-- Сгенерировано из Sajda/Resources/$locale.lproj/Localizable.strings. Не редактировать. -->")
                    appendLine("<resources>")
                    for ((key, value) in entries) {
                        appendLine("""    <string name="$key">${convert(value)}</string>""")
                    }
                    appendLine("</resources>")
                }
            File(out, "$folder/strings_shared.xml").apply { parentFile.mkdirs() }.writeText(xml)
        }
    }

    private fun convert(raw: String): String {
        var text =
            raw
                .replace("\\\"", "\"")
                .replace("\\n", "\n")
                .replace("%lld", "%d")
                .replace("%@", "%s")
                .replace("&", "&amp;")
                .replace("<", "&lt;")
                .replace(">", "&gt;")
                .replace("'", "\\'")
                .replace("\"", "\\\"")
                .replace("\n", "\\n")
        val formats = Regex("%[ds]").findAll(text).count()
        if (formats > 1) {
            var index = 0
            text = Regex("%([ds])").replace(text) { "%${++index}$${it.groupValues[1]}" }
        }
        if (text.startsWith("@") || text.startsWith("?")) text = "\\" + text
        return text
    }
}

/** Модель эмбеддингов MediaPipe (MobileNet V3 small, Apache-2.0) для сравнения с эталонными фото. */
abstract class DownloadModel : DefaultTask() {
    @get:Input
    abstract val url: Property<String>

    @get:Input
    abstract val sha256: Property<String>

    @get:Input
    abstract val fileName: Property<String>

    @get:OutputDirectory
    abstract val outputDir: DirectoryProperty

    @TaskAction
    fun download() {
        val target = outputDir.get().file(fileName.get()).asFile
        if (!target.isFile || digest(target) != sha256.get()) {
            target.parentFile.mkdirs()
            URI(url.get()).toURL().openStream().use { input -> target.outputStream().use { input.copyTo(it) } }
        }
        val actual = digest(target)
        check(actual == sha256.get()) { "Checksum mismatch for ${fileName.get()}: $actual" }
    }

    private fun digest(file: File): String =
        MessageDigest
            .getInstance("SHA-256")
            .digest(file.readBytes())
            .joinToString("") { "%02x".format(it) }
}

val generateSharedStrings =
    tasks.register<GenerateSharedStrings>("generateSharedStrings") {
        sourceDir.set(layout.projectDirectory.dir("../../Sajda/Resources"))
        overridesDir.set(layout.projectDirectory.dir("src/main/res"))
        outputDir.set(layout.buildDirectory.dir("generated/sharedStrings"))
    }

val downloadEmbedderModel =
    tasks.register<DownloadModel>("downloadEmbedderModel") {
        url.set("https://storage.googleapis.com/mediapipe-models/image_embedder/mobilenet_v3_small/float32/1/mobilenet_v3_small.tflite")
        sha256.set("bbbb4c51a55a53905af1daec995ca1aae355046f8839bb8c9f5ce9271394bc40")
        fileName.set("image_embedder.tflite")
        outputDir.set(layout.buildDirectory.dir("generated/models"))
    }

androidComponents {
    onVariants { variant ->
        variant.sources.res?.addGeneratedSourceDirectory(generateSharedStrings, GenerateSharedStrings::outputDir)
        variant.sources.assets?.addGeneratedSourceDirectory(downloadEmbedderModel, DownloadModel::outputDir)
    }
}

dependencies {
    implementation(libs.androidx.core.ktx)
    implementation(libs.androidx.activity.compose)
    implementation(libs.androidx.lifecycle.runtime.compose)
    implementation(libs.androidx.lifecycle.process)
    implementation(libs.androidx.core.splashscreen)
    implementation(platform(libs.compose.bom))
    implementation(libs.compose.ui)
    implementation(libs.compose.ui.tooling.preview)
    implementation(libs.compose.material3)
    implementation(libs.compose.material.icons)
    implementation(libs.camerax.camera2)
    implementation(libs.camerax.lifecycle)
    implementation(libs.camerax.view)
    implementation(libs.glance.appwidget)
    implementation(libs.glance.material3)
    implementation(libs.mlkit.image.labeling)
    implementation(libs.mediapipe.tasks.vision)
    implementation(libs.adhan)
    implementation(libs.kotlinx.coroutines.android)
    implementation(libs.kotlinx.serialization.json)
    debugImplementation(libs.compose.ui.tooling)

    testImplementation(libs.junit)
    testImplementation(libs.kotlinx.coroutines.test)
    androidTestImplementation(libs.androidx.test.runner)
    androidTestImplementation(libs.androidx.test.junit)
}
