# Cinematic Metal — auditoría de shaderpacks y arquitectura

**Fecha:** 2026-11-25  
**Base de MCOpt:** `GaelQuinta/minecraft-metal-shaders` en `24967cb7ec593d24efbcbe72c97c8908b50bf49b`  
**Rama de desarrollo:** `lolojijoio/minecraft-metal-shaders:cinematic-metal`

## Conclusión ejecutiva

Hay shaders nativos escritos para el renderer Metal de MCOpt, pero eso no significa que el proyecto ya ejecute shaderpacks tradicionales de Iris/OptiFine sobre Metal. Son dos sistemas diferentes:

- **Sí existe sombreado nativo de MCOpt:** código MSL incluido en el mod, enlazado a sus pipelines y a los pases de renderizado propios.
- **Sí existe una ruta Iris/OpenGL separada:** las pruebas del repositorio preparan una instancia `DEV-IRIS` con `mcopt.metal=false`, Iris y Complementary. No es Iris ejecutándose sobre el backend Metal.
- **No hay un runtime genérico de shaderpacks Iris/OptiFine integrado en MCOpt en el commit auditado:** existen puntos de extensión internos para uno, pero el runtime no está publicado en ese árbol.
- **Ya existe una implementación externa de packs GLSL sobre un backend Metal de RenderPearl:** `Kausik-Velaga/minecraft-metal-renderer` con su módulo separado `Minecraft Shader Loader`. Es la referencia más útil para Cinematic Metal, pero no es un complemento directo de MCOpt.

Por tanto, el camino recomendado es **adaptar la arquitectura del loader externo a MCOpt**, reutilizando los hooks existentes del fork y manteniendo el runtime de packs separado de los shaders nativos Cinematic Metal. No se debe añadir Iris al backend Metal ni copiar el loader entero sin auditar sus dependencias.

## 1. Qué ya hace MCOpt

### 1.1 Shaders nativos Metal

El renderer convierte los shaders normales de Minecraft desde GLSL a SPIR-V mediante shaderc y, en el backend Metal, usa SPIRV-Cross para producir MSL y compilar una biblioteca Metal. Además, los pipelines de terreno de MCOpt tienen etapas MSL escritas a mano. El fork `minecraft-metal-shaders` añade un sistema de sombreado propio bajo `metal/src/main/java/mcopt/metal/shade/` y `metal/src/main/resources/mcopt/shade/*.metal`.

El sombreado integrado incluye, entre otras cosas, iluminación, sombras, agua, reflejos, atmósfera, nubes volumétricas, postprocesado HDR y salida EDR. Es una implementación de renderer propia; no es un intérprete general para los programas `gbuffers_*`, `shadow_*`, `composite*` de packs OptiFine/Iris.

### 1.2 Packs de Iris en OpenGL

El harness del propio repositorio define una instancia `mcopt DEV-IRIS` separada, con OpenGL (`mcopt.metal=false`), Iris y Complementary Reimagined. Esto sirve como referencia visual y de rendimiento contra el renderer Metal. No demuestra compatibilidad de Iris con Metal.

La investigación interna `docs/research/iris-internals.md` describe por qué Iris no funciona en el backend Metal: su capa de ejecución usa llamadas OpenGL directas, clases internas del backend OpenGL, FBOs y programas GL. En esa configuración no hay un contexto GL para satisfacer esas llamadas. **No intentar arreglarlo cambiando solo una opción de Iris.** Haría falta portar/forkear gran parte del runtime o crear otro loader.

### 1.3 Las costuras de integración ya presentes

El commit base contiene elementos diseñados para que un runtime externo pueda hacerse cargo de pases:

- `MetalHooks`: registro encadenable de `PassRedirector`, redirección de attachments y opción de mantener los attachments originales.
- `PassDelegate`: permite enlazar un pipeline propio, remapear sus recursos y decidir qué draws se aceptan dentro del pase redirigido.
- `MetalBridge`: expone operaciones del backend que no están en la API portable.
- `MetalPipeline` y `MetalRenderPass`: puntos donde se crean pipelines MSL y se delegan los draws.

Los comentarios de estos componentes mencionan explícitamente el futuro runtime de shaderpacks. En el commit auditado no están presentes las clases del runtime de packs ni el puente nativo que lo completaría. Esos hooks son la base correcta para implementar la integración; no son prueba de que el soporte esté terminado.

## 2. Qué opciones externas existen

### 2.1 Minecraft Metal + Minecraft Shader Loader (la referencia principal)

Repositorio: <https://github.com/Kausik-Velaga/minecraft-metal-renderer>  
Documentación del loader: <https://github.com/Kausik-Velaga/minecraft-metal-renderer/blob/main/docs/shader-loader.md>  
Licencia del proyecto: MIT.

La versión publicada consultada es Minecraft Metal `0.2.2` + Shader Loader `0.1.3` + Scene Optimizer `0.1.0`. El loader tiene su propio módulo Fabric, separado del backend, y carga un ZIP/carpeta de shaderpack suministrado localmente. Su compilador adapta GLSL heredado de OptiFine y usa el frontend RenderPearl/shaderc para generar SPIR-V; el backend Metal convierte esos módulos a MSL.

**Límites documentados actualmente:**

- No está pensado para cualquier pack sin validación. BSL 10.1.8 fue el primer objetivo probado; BSL no se distribuye con el proyecto.
- Compute shaders, storage images, geometry/tessellation stages y texturas 3D no están soportados por el loader.
- Algunas directivas/pases de setup, formatos de shadow-color y ciertos modos de autofocus DOF son rechazados.
- Hay límites de materiales/atlas, glint combinado y rutas de entidades. Combinarlo con otros reemplazos de renderizado no está validado.
- No tiene todavía pantalla de ajustes propia ni cambio de pack en vivo; usa archivo de configuración y reinicio.
- La validación histórica de BSL 0.1.2 documenta 583 compilaciones de pipelines, pero la propia documentación indica que la validación final de build/juego/paquete de la rama 0.1.3 aún está pendiente.
- El proyecto informa haber sido generado completamente con Codex y no presenta esa prueba como auditoría independiente de código/seguridad.

**Qué reutilizar como diseño:** separar `shader-loader` del renderer; tener un parser/config de pack; preprocesar GLSL y normalizar uniforms/atributos; convertir el pack a un plan de pases; renderizar sombras, geometría opaca/transparente, deferred/composite/final con targets ping-pong; reiniciar el historial temporal tras cambios de mundo/tamaño; y crear pruebas específicas de compilación y escenas reales.

**Por qué no copiarlo literalmente:** el loader más reciente todavía importa contratos propios del backend (`dev.kausik.metal.*`) y del scene optimizer (`dev.kausik.scene.*`); su `fabric.mod.json` exige `minecraft_metal ~0.2.2`, no MCOpt. Su `PackPipeline` usa ayudantes específicos del renderer. La arquitectura de passes y el adaptador GLSL son referencias, pero requieren una capa de compatibilidad para `MetalHooks`, `PassDelegate`, `MetalBridge`, los bindings de MCOpt y su formato de geometría.

### 2.2 Vitrail Shaders (ruta Vulkan, no Metal nativo)

Proyecto: <https://modrinth.com/mod/vitrail-shaders>  
Licencia: LGPL-3.0-only.  
La versión para MC 26.3 consultada es `0.13.0-beta`.

Vitrail adapta packs OptiFine a GLSL apto para el backend Vulkan de Minecraft y deja que el compilador del juego genere SPIR-V. En un Mac, esa ruta usa Vulkan a través de MoltenVK. Es importante para la compatibilidad de packs clásicos, pero **no ejecuta los shaders directamente en el backend nativo Metal de MCOpt**. Además, necesita Sodium y el backend Vulkan experimental.

**Uso recomendado:** referencia externa y futura batería de compatibilidad (por ejemplo, comparar la salida de Complementary/BSL), no base directa de nuestro runtime Metal.

### 2.3 Iris / Aperture

Iris sigue siendo una ruta OpenGL para los packs clásicos. Aperture es un motor nuevo dirigido a Vulkan y a un formato de packs Slang distinto; no es un puente que haga funcionar los packs Iris actuales sobre Metal. No basar el desarrollo en que Iris vaya a añadir compatibilidad Metal.

## 3. Pipeline propuesto para Cinematic Metal

El flujo objetivo es:

1. Abrir el ZIP/carpeta del pack y leer `shaders.properties`, opciones, includes y programas.
2. Expandir includes y procesar macros/opciones; adaptar GLSL legado de OptiFine a la interfaz que espera RenderPearl.
3. Compilar GLSL a SPIR-V con shaderc usando las reglas relajadas/ubicaciones necesarias para este dialecto; reflejar uniforms y samplers.
4. Pasar SPIR-V por SPIRV-Cross a MSL, utilizando el backend Metal existente. No enviar GLSL del pack a OpenGL.
5. Convertir cada grupo de programas del pack en un grafo de pases con sus targets, depth snapshots, matrices, uniforms, samplers e historial temporal.
6. Usar `MetalHooks` + `PassDelegate` para redirigir los pases y ejecutar los pipelines del pack. Reservar `MetalBridge` para capacidades Metal que RenderPearl no expone.
7. Desactivar o adaptar, cuando haya un pack activo, el reemplazo de terreno MSL de MCOpt y su ruta rápida de geometría. El terreno Metal actual asume un layout propio; no se debe permitir que sobrescriba silenciosamente los programas `gbuffers_terrain` del pack.
8. Mantener dos modos claros: `Cinematic Metal Native` (efectos nativos del renderer) y `Shaderpack Compatibility` (runtime de pack). No activar ambos sobre los mismos attachments sin un diseño de composición y orden explícito.

### Etapas de compatibilidad sugeridas

- **Etapa A — BSL default:** pack de prueba obtenido por el usuario; sin cómputo de iluminación multicolor. Validar opacos, cutout, agua/transparencia, mano, entidades, sombras, post y cambio de dimensión.
- **Etapa B — pack clásico adicional:** Complementary Reimagined con un perfil conservador. Comparar contra Iris/OpenGL en la misma escena y el mismo Mac; una compilación correcta no demuestra equivalencia visual.
- **Etapa C — capacidades Metal:** añadir compute, imágenes/SSBOs y comparación de sombras solo tras crear contratos explícitos en `MetalBridge`, límites de dispositivo y pruebas GPU. La iluminación coloreada de Complementary pertenece a una etapa posterior.
- **Etapa D — producto:** selector de pack/opciones, diagnósticos, perfiles y pruebas de regresión. Los presets propios Cinematic Metal permanecen separados del sistema de opciones del pack.

## 4. Riesgos técnicos y de licencia

- Un pack puede compilar y, aun así, verse mal por matrices, reversed-Z, alpha test, lightmap, coordenadas de atlas, buffer flipping, blending, depth snapshots, sombras, orden de pases o temporales. Cada uno requiere prueba visual y de GPU.
- RenderPearl por sí solo no representa todas las capacidades que algunos packs piden. No afirmar soporte de compute/SSBO/storage images porque shaderc haya traducido un módulo: también deben existir allocations, bindings, sincronización y ejecución correctas en Metal.
- La ruta rápida de terreno MSL de MCOpt puede colisionar con el vertex format y los programas de un shaderpack. Primero debe haber un modo seguro que la desactive o la adapte.
- El código externo MIT se puede estudiar como referencia; si se incorpora código, se deben conservar avisos MIT y revisar cada dependencia/archivo. No se copiará código AGPL/LGPL de Iris/glsl-transformer ni LGPL de Vitrail sin una decisión explícita de licencia y distribución.
- Los packs son propiedad de sus autores. No incluir ZIPs, GLSL o texturas de BSL/Complementary en este repositorio ni precompilar sus MSL para redistribuirlos. Las pruebas locales deben usar archivos que el usuario obtenga legalmente.

## 5. Decisión adoptada

**No integrar Iris directamente, no hacer un port Vulkan/MoltenVK y no copiar sin revisión el loader externo.** La vía seleccionada es desarrollar un módulo de compatibilidad de shaderpacks para MCOpt, inspirado por la división de responsabilidades y el flujo de pruebas de Minecraft Shader Loader, pero implementado sobre las APIs/hook points de MCOpt.

Antes del primer port de runtime se debe compilar sin cambios el módulo `:metal` en un Mac Apple Silicon, guardar los resultados de referencia de MCOpt nativo y confirmar las rutas de fallback. El script `tools/cinematic-metal/macos-preflight.sh` comprueba los prerrequisitos y puede ejecutar ese build.

## Referencias verificadas

- MCOpt pin: <https://github.com/GaelQuinta/minecraft-metal-shaders/tree/24967cb7ec593d24efbcbe72c97c8908b50bf49b>
- Hooks MCOpt: `metal/src/main/java/mcopt/metal/MetalHooks.java`, `PassDelegate.java`, `MetalBridge.java`, `MetalPipeline.java`, `MetalRenderPass.java` en el pin anterior.
- Investigación Iris interna: `docs/research/iris-internals.md` en el pin anterior.
- Investigación RenderPearl interna: `docs/research/mc-renderer.md` en el pin anterior.
- Minecraft Metal / Shader Loader: <https://github.com/Kausik-Velaga/minecraft-metal-renderer>
- Shader Loader guide: <https://github.com/Kausik-Velaga/minecraft-metal-renderer/blob/main/docs/shader-loader.md>
- Shader validation: <https://github.com/Kausik-Velaga/minecraft-metal-renderer/blob/main/docs/shader-validation.md>
- Vitrail 26.3: <https://modrinth.com/mod/vitrail-shaders/version/0.13.0-beta%2Bmc26.3>