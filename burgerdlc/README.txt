BUILD:
1) Install JDK 21.
2) Copy gradlew, gradlew.bat and the "gradle" folder from the Fabric template
   (https://fabricmc.net/develop/template/ -> Generate -> unzip) into this folder.
   OR just open this folder in IntelliJ IDEA and let it import the Gradle project.
3) Run:  gradlew build        (Windows: gradlew.bat build)
4) Jar: build/libs/burger-dlc-1.0.0.jar  -> put into .minecraft/mods
   (needs Fabric Loader + Fabric API for 1.21.11)

Right Shift = menu. Module binds are set in the menu (click the key pill or middle-click a card); AimBot defaults to R.
Settings are saved to .minecraft/config/burgerdlc.properties.
