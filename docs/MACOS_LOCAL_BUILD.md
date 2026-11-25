# Cinematic Metal — preparación de compilación local en macOS

Esta guía es para compilar primero el MCOpt/Metal base sin modificar su renderer. No instala nada, no toca tus instancias de Minecraft y no sube cambios a GitHub.

## Requisitos

- Mac con Apple Silicon (arm64).
- macOS 15 o posterior: el target nativo del MCOpt pin utiliza `-mmacosx-version-min=15.0`.
- Xcode Command Line Tools seleccionadas, con Apple clang y macOS SDK disponibles (`xcode-select`, `xcrun`). No hace falta compilar manualmente archivos `.metal`: el bridge nativo compila el MSL en tiempo de ejecución.
- JDK ARM64 25 o posterior, con `java` y `javac` en `PATH`.
- Git y conexión de red para que Gradle pueda descargar dependencias en la primera compilación.

## Descargar el fork y cambiar a la rama de trabajo

Abre Terminal y ejecuta:

```sh
git clone https://github.com/lolojijoio/minecraft-metal-shaders.git
cd minecraft-metal-shaders
git switch cinematic-metal
```

Comprueba que estás en la rama correcta:

```sh
git branch --show-current
```
Debe mostrar `cinematic-metal`.

## Ejecutar el diagnóstico

```sh
/tools/cinematic-metal/macos-preflight.sh
```
El diagnóstico comprueba arquitectura, versión de macOS, Xcode Command Line Tools, Apple clang, SDK, Java/Javac, archivos del build y rama Git. No ejecuta Gradle ni modifica archivos.

## Compilar el renderer base

Cuando el diagnóstico termine sin errores:

```sh
./gradlew --no-daemon --no-parallel :metal:build
```
O ejecuta diagnóstico y compilación con un solo comando:

```sh
./tools/cinematic-metal/macos-preflight.sh --build
```

La primera compilación puede descargar herramientas/dependencias y necesita conexión a Internet. La tarea crea el bridge nativo para arm64 y el JAR del módulo `metal`.

## Qué resultado revisar

- Salida Gradle: debe terminar con `BUILD SUCCESSFUL`.
- JAR: `metal/build/libs/`.
- Bridge nativo dentro del JAR: lista su contenido con `jar tf metal/build/libs/<archivo>.jar | grep -E 'libmcmetal\.dylib|fabric.mod.json'`.

Un `BUILD SUCCESSFUL` confirma la compilación de ese módulo en esa máquina. **No confirma todaviía** que Minecraft arranque, que se vea correctamente el mundo, que funcionen todas las funciones de Metal ni que el rendimiento sea bueno en un M2. Eso requiere una instancia DEV aislada, las pruebas de juego y capturas/medidas en tu Mac.

## Aislamiento y seguridad

- No instales esta compilación sobre tu instancia habitual ni sobre mundos importantes.
- No ejecutes benchmarks mientras juegas en otra instancia.
- No compartas logs completos sin revisar rutas, nombre de usuario, tokens o información privada.
- No subas JARs, logs ni packs de shaders con copyright a GitHub.
- El script no instala Xcode, Java, Gradle ni paquetes Homebrew; solo comprueba el entorno y, con `--build`, ejecuta `:metal:build`.

## Si falla

Copia el mensaje de error completo desde el primer `FAIL` o desde el primer error Gradle, junto con:

```sh
sw_vers
uname -m
java -version
javac -version
xcode-select -p
xcrun --sdk macosx --show-sdk-version
```

Redacta cualquier dato privado antes de compartirlo.
