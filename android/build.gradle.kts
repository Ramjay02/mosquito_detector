allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

subprojects {
    afterEvaluate {
        tasks.withType<JavaCompile>().configureEach {
            sourceCompatibility = "17"
            targetCompatibility = "17"
        }

        try {
            val ext = extensions.findByName("kotlin")
            if (ext != null) {
                val cc = ext.javaClass.getMethod("getCompilerOptions").invoke(ext)
                val jtProp = cc.javaClass.getMethod("getJvmTarget").invoke(cc)
                val enumCls = cc.javaClass.classLoader
                    .loadClass("org.jetbrains.kotlin.gradle.dsl.JvmTarget")
                val jvm17 = enumCls.enumConstants
                    .first { (it as Enum<*>).name == "JVM_17" }
                jtProp.javaClass.getMethod("set", Any::class.java).invoke(jtProp, jvm17)
            }
        } catch (_: Exception) {
            // fall back to task-level override below
        }
        tasks.withType<org.jetbrains.kotlin.gradle.tasks.KotlinCompile>().configureEach {
            compilerOptions {
                jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17)
            }
        }
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
