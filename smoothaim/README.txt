BUILD:
1) Install JDK 21.
2) Copy gradlew, gradlew.bat and the "gradle" folder from the Fabric template
   (https://fabricmc.net/develop/template/ -> Generate -> unzip) into this folder.
   OR just open this folder in IntelliJ IDEA and let it import the Gradle project.
3) Run:  gradlew build        (Windows: gradlew.bat build)
4) Jar: build/libs/smoothaim-1.0.0.jar  -> put into .minecraft/mods
   (needs Fabric Loader + Fabric API for 1.21.4)

Right Shift = menu, R = toggle AimBot. TriggerBot key can be bound in Controls.
Settings are saved to .minecraft/config/smoothaim.properties.
