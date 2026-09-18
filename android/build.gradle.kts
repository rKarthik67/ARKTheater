allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)

    // media_kit_libs_android_video downloads four native .jar files from
    // GitHub Releases while Gradle is still CONFIGURING the project, and a
    // timeout there hard-fails the entire build before a single line is
    // compiled. Those jars land in that project's buildDir - which the
    // redirect just above moves into this app's own build/ folder - so
    // `flutter clean` deletes them and the next build needs GitHub
    // reachable all over again.
    //
    // Seed them instead from whichever copy is already on disk: a
    // deliberately checked-in/kept one under android/prebuilt/ first, then
    // the plugin's own untouched build/ folder inside the pub cache (which
    // flutter clean can't reach). Only copies what's missing or the wrong
    // size, so a legitimately updated jar still wins.
    if (project.name == "media_kit_libs_android_video") {
        val target = newSubprojectBuildDir.dir("v1.1.7").asFile
        val sources = listOf(
            rootProject.file("prebuilt/media_kit_v1.1.7"),
            project.projectDir.resolve("build/v1.1.7"),
        )
        for (source in sources) {
            if (!source.isDirectory) continue
            source.listFiles()?.forEach { jar ->
                if (!jar.isFile || !jar.name.endsWith(".jar") || jar.length() == 0L) return@forEach
                val copy = target.resolve(jar.name)
                if (!copy.exists() || copy.length() != jar.length()) {
                    target.mkdirs()
                    jar.copyTo(copy, overwrite = true)
                    println("Seeded ${jar.name} from ${source.path} (skipping GitHub download)")
                }
            }
        }
    }
}
subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
