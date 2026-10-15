allprojects {
    repositories {
        maven { url = uri("https://maven.aliyun.com/repository/google") }
        maven { url = uri("https://maven.aliyun.com/repository/public") }
        maven { url = uri("https://maven.aliyun.com/repository/gradle-plugin") }
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

// 提取成一个独立函数，方便在“已求值”和“未求值”两种情况下复用
fun fixNamespaceIfMissing(project: Project) {
    if (project.plugins.hasPlugin("com.android.library") || project.plugins.hasPlugin("com.android.application")) {
        val android = project.extensions.findByName("android")
        if (android != null) {
            try {
                val getNamespace = android.javaClass.getMethod("getNamespace")
                if (getNamespace.invoke(android) == null) {
                    val setNamespace = android.javaClass.getMethod("setNamespace", String::class.java)
                    val defaultNs = if (project.group.toString().isNotEmpty() && project.group.toString() != "unspecified") {
                        project.group.toString()
                    } else {
                        "com.example.${project.name.replace("-", "_")}"
                    }
                    setNamespace.invoke(android, defaultNs)
                }
            } catch (_: Throwable) {}
        }
    }
}

subprojects {
    // 关键修复：如果项目（例如 :app）由于 evaluationDependsOn 已经被提前求值完毕，
    // 直接调用 fixNamespaceIfMissing；否则调用 afterEvaluate 会抛异常
    if (project.state.executed) {
        fixNamespaceIfMissing(project)
    } else {
        afterEvaluate {
            fixNamespaceIfMissing(project)
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}