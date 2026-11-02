plugins {
    alias(libs.plugins.android.application) apply false
    alias(libs.plugins.kotlin.android) apply false
    alias(libs.plugins.kotlin.compose) apply false
    alias(libs.plugins.kotlin.serialization) apply false
    alias(libs.plugins.spotless)
}

spotless {
    // Общий .editorconfig в корне репозитория (ниже android/).
    val editorConfig = rootDir.resolve("../.editorconfig")
    kotlin {
        target("app/src/**/*.kt")
        ktlint(libs.versions.ktlint.get()).setEditorConfigPath(editorConfig)
    }
    kotlinGradle {
        target("*.gradle.kts", "app/*.gradle.kts")
        ktlint(libs.versions.ktlint.get()).setEditorConfigPath(editorConfig)
    }
}
