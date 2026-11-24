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
}
subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}


// flutter_appauth 9.0.1 still declares compileSdk 33. Raise it when the Android plugin is applied.
subprojects {
    pluginManager.withPlugin("com.android.library") {
        @Suppress("UNCHECKED_CAST")
        val ext = extensions.getByName("android")
        val setter = ext.javaClass.methods.firstOrNull { it.name == "setCompileSdk" && it.parameterCount == 1 }
            ?: ext.javaClass.methods.firstOrNull { it.name == "setCompileSdkVersion" && it.parameterCount == 1 }
        setter?.invoke(ext, 35)
    }
}
