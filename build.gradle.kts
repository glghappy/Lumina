import org.gradle.api.tasks.testing.logging.TestExceptionFormat
import org.gradle.api.tasks.testing.logging.TestLogEvent

plugins {
    java
    id("io.papermc.paperweight.patcher") version "2.0.0-beta.24"
}

paperweight {
    filterPatches = false
    upstreams.register("folia") {
        repo = github("PaperMC", "Folia")
        ref = providers.gradleProperty("foliaRef")

        patchFile {
            path = "folia-server/build.gradle.kts"
            outputFile = file("lumina-server/build.gradle.kts")
            patchFile = file("lumina-server/build.gradle.kts.patch")
        }
        patchFile {
            path = "folia-api/build.gradle.kts"
            outputFile = file("lumina-api/build.gradle.kts")
            patchFile = file("lumina-api/build.gradle.kts.patch")
        }

        patchRepo("paperApi") {
            upstreamPath = "paper-api"
            patchesDir = file("lumina-api/paper-patches")
            outputDir = file("paper-api")
        }

        patchDir("foliaApi") {
            upstreamPath = "folia-api"
            excludes = listOf("build.gradle.kts", "build.gradle.kts.patch", "paper-patches")
            patchesDir = file("lumina-api/folia-patches")
            outputDir = file("folia-api")
        }
    }
}

val paperMavenPublicUrl = "https://repo.papermc.io/repository/maven-public/"
val leavesMavenReleasesUrl = "https://repo.leavesmc.org/releases/"

subprojects {
    apply(plugin = "java-library")
    apply(plugin = "maven-publish")

    extensions.configure<JavaPluginExtension> {
        toolchain {
            languageVersion = JavaLanguageVersion.of(25)
        }
    }

    repositories {
        mavenCentral()
        maven(paperMavenPublicUrl)
        maven(leavesMavenReleasesUrl)
    }

    dependencies {
        "testRuntimeOnly"("org.junit.platform:junit-platform-launcher")
    }

    tasks.withType<AbstractArchiveTask>().configureEach {
        isPreserveFileTimestamps = false
        isReproducibleFileOrder = true
    }
    tasks.withType<JavaCompile>().configureEach {
        options.encoding = Charsets.UTF_8.name()
        options.release = 25
        options.isFork = true
    }
    tasks.withType<Javadoc>().configureEach {
        options.encoding = Charsets.UTF_8.name()
    }
    tasks.withType<ProcessResources>().configureEach {
        filteringCharset = Charsets.UTF_8.name()
    }
    tasks.withType<Test>().configureEach {
        testLogging {
            showStackTraces = true
            exceptionFormat = TestExceptionFormat.FULL
            events(TestLogEvent.STANDARD_OUT)
        }
    }
}

// Lumina version stage override: Implementation-Version in jar manifest
// Applied AFTER each subproject configures its jar task, so it takes precedence.
// Format: {mcVersion}-{stage}.{buildNum}-{gitHash}  (stage omitted for release)
// e.g. 26.3-beta.1-abc1234  |  26.3-rc.3-abc1234  |  26.3-abc1234
gradle.afterProject {
    if (name != rootProject.name) {
        tasks.withType<Jar>().configureEach {
            manifest {
                val luminaStage = rootProject.providers.gradleProperty("luminaStage").getOrElse("beta")
                val luminaBuildNum = rootProject.providers.gradleProperty("luminaBuildNum").getOrElse("1")
                val stagePart = if (luminaStage == "release") "" else "-${luminaStage}.${luminaBuildNum}"
                val mcVersion = rootProject.providers.gradleProperty("mcVersion").get()
                val gitHash = providers.exec {
                    commandLine("git", "rev-parse", "--short=7", "HEAD")
                }.standardOutput.asText.get().trim()

                attributes(
                    "Implementation-Version" to "$mcVersion$stagePart-$gitHash"
                )
            }
        }
    }
}
