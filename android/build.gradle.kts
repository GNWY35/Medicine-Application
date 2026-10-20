buildscript {
    repositories {
        google()
        mavenCentral()
    }
    dependencies {
        classpath("com.google.gms:google-services:4.3.15")
    }
}

allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory = rootProject.layout.buildDirectory.dir("../../build").get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}
subprojects {
    project.evaluationDependsOn(":app")
}

// Workaround: androidx.camera:camera-core:1.5.3 pulls in
// androidx.concurrent:concurrent-futures only as an `implementation` dependency,
// so it's hidden from camera_android_camerax's own compile classpath even though
// it's present at runtime. javac needs the actual class for type-annotation
// processing on SurfaceRequest, so compilation fails without this.
gradle.projectsEvaluated {
    project(":camera_android_camerax").dependencies.add(
        "implementation",
        "androidx.concurrent:concurrent-futures:1.2.0",
    )
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
