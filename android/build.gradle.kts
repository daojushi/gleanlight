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
    if (project.name == "cronet_http") {
        // Always use the package's official embedded-Cronet switch. A normal
        // flutter build must work on ColorOS without Google Play Services.
        val defines = (project.findProperty("dart-defines") as? String).orEmpty()
        val embedded = java.util.Base64.getEncoder()
            .encodeToString("cronetHttpNoPlay=true".toByteArray(Charsets.UTF_8))
        project.extensions.extraProperties.set(
            "dart-defines", listOf(defines, embedded).filter { it.isNotEmpty() }.joinToString(",")
        )
    }
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}
subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
