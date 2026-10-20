plugins {
    id("com.gtnewhorizons.gtnhconvention")
}

// jar 文件名：crop-helper-0.1.0.jar
base {
    archivesName.set("crop-helper")
}

// 版本来源：gradle.properties 的 RELEASE_VERSION（gtnh.modules.gitVersion = false 时生效）。
project.ext.set("modVersion", project.findProperty("RELEASE_VERSION") as String? ?: "0.1.0")
