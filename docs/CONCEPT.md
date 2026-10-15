# Bichitos: un terrario de criaturas ridículas

Un sandbox para iPhone donde diseñas bichitos en pixel art, los sueltas en un mundo y observas
cómo se comportan, se relacionan y generan situaciones inesperadas. Un Tamagotchi, pero con
muchos bichitos que viven su vida aunque no mires.

SwiftUI + SpriteKit, iOS 17+. Todo es procedural: el pixel art, el comportamiento y la voz.
Sin samples, sin sprites dibujados a mano, sin dependencias de terceros.

## El bichito

Cada bichito es una **receta**: unos pocos genes que el motor convierte en píxeles, comportamiento y voz.

| Gen | Valores | Afecta a |
|---|---|---|
| Cuerpo | gota, alubia, torre, cuadradito, pera, estrella blanda | Silueta |
| Ajustes de cuerpo | redondez, altura, bultos (0…1) | Silueta |
| Ojos | normales, saltones, cíclope, tres, adormilados | Cara |
| Ajustes de ojos | tamaño, separación (0…1) | Cara |
| Patas | 0, 2, 4, 6 + largo (0…1) | Silueta, forma de andar |
| Paleta | 12 paletas | Color |
| Personalidad | curiosa, nerviosa, dormilona, hiperactiva, territorial, romántica | Comportamiento, rasgos de forma, voz |
| Semilla | UInt64 | Variaciones dentro de lo elegido |
| Versión del motor | Int | Qué generador lo dibuja (ver abajo) |

Además, cada bichito tiene un **nombre** generado y una **descripción absurda**:
«Pocholo, 3 años, odia las esquinas y sospecha de las nubes». Las listas de nombres y manías
existen en español e inglés.

## El editor

1. Elige categorías con chips: cuerpo, ojos, patas, paleta, personalidad. La vista previa se
   anima en vivo (respira, parpadea, reacciona al cambiar de personalidad).
2. Debajo de cada categoría, 2–3 **ajustes finos** opcionales (plegados por defecto).
3. El **dado** cambia la semilla: misma receta, otros detalles. Mantener pulsado el dado lo aleatoriza todo.
4. Nombre y descripción salen solos; un botón los vuelve a tirar. El nombre se puede editar.
5. **Soltar**: el bichito cae al mapa con un *boing*.

## Motor de sprites

`(receta, estado) → rejilla de 24×24 índices de paleta → textura`. Es una función pura y determinista:
la misma receta y el mismo estado dan siempre los mismos píxeles.

Capas, en orden:

1. **Silueta**: un campo de distancia (SDF) por tipo de cuerpo, deformado por los ajustes y por
   bultos sembrados con la semilla, simétrico en horizontal. Se rasteriza a la rejilla.
2. **Squash & stretch**: la silueta se escala (`sx`, `sy`) conservando el área *antes* de rasterizar,
   así que el aplastado es pixel art limpio. 8 niveles cacheados por bichito, de 0.7 a 1.3.
3. **Patas**: segmentos bajo la silueta; 2 frames de paso.
4. **Rasgos de personalidad**: nerviosa = pelos de punta, dormilona = cuerpo más caído,
   territorial = cuernitos, hiperactiva = antenas, romántica = mofletes, curiosa = una antena con bolita.
5. **Necesidades visibles**: con hambre, la silueta adelgaza y la paleta se apaga; bien cuidado,
   más rechoncho y con más brillo.
6. **Cara**: ojos paramétricos (tamaño, separación, pupila que mira hacia donde va) y boca,
   con **expresiones** por estado: normal, parpadeo, dormido, enamorado, enfadado, asustado,
   hambriento, contento, mareado.
7. **Contorno y sombreado automáticos**: los píxeles del borde son contorno; el resto se sombrea
   según el gradiente del SDF con luz arriba a la izquierda (sombra, base, brillo).

Las texturas se cachean por `(receta, squash, expresión, frame de patas, nivel de necesidades)`.

### Versionado

Solo se guarda la receta. Cada versión del generador se conserva en el código (`GeneratorV1`,
`GeneratorV2`…) y cada bichito se dibuja siempre con la suya: una actualización nunca le cambia
la cara a nadie. Los bichitos nuevos y las crías usan la versión más reciente.

Code: `Recipe.swift`, `Generator.swift`, `Sprites.swift` (caché + `SKTexture` con `.nearest`).

## El mundo

- Un **mapa continuo** con paneo y zoom (pellizco). Los bichitos son pixel art sobre un mundo
  e interfaz modernos (ver DESIGN.md).
- El mapa tiene **barrios** ("ciudades"): zonas con nombre y ambiente propio. Se desbloquean
  barrios nuevos según crece la población, para que siempre haya sitio. Los bichitos **emigran**
  caminando entre barrios según afinidades ("Pocholo se fue a vivir con los territoriales").
- Comida, objetos sencillos y ningún otro protagonista que los bichitos.

## Comportamiento

Cada bichito es una máquina de estados: pasear, dormir, comer, enamorarse, pelear, perseguir,
huir, imitar, asustarse, contento, cogido, incubando.

- **Encuentros**: al cruzarse dos bichitos, se elige qué pasa con pesos según la personalidad
  (territorial pelea, romántica se enamora, nerviosa huye, curiosa imita, hiperactiva persigue)
  y según su **afinidad** previa.
- **Afinidad**: cada bichito recuerda a los demás (−1…1). Cada pelea la baja, cada mimo compartido
  la sube. De ahí salen rivales y parejas que duran semanas.
- **Crías**: dos bichitos con afinidad alta pueden poner un huevo. La cría hereda cada gen de uno
  de los padres; los ajustes continuos se promedian y mutan un poco; con baja probabilidad muta
  una categoría. Hereda también la voz.

## Interacciones del usuario

| Gesto | Qué pasa |
|---|---|
| Tocar | Acariciar: se aplasta de gusto (o se queja si dormía) |
| Arrastrar y soltar | Cogerlo y lanzarlo: rebota en el suelo y se marea |
| Tocar el suelo en modo comida | Cae comida; los hambrientos corren a por ella |
| Agitar el móvil | Susto general |
| Mantener pulsado | Ficha: nombre, descripción, personalidad, necesidades, parientes, amigos y rivales |

Todas las acciones existen también como botones (accesibilidad).

## Necesidades y escapadas

Hambre, sueño y cariño bajan con el reloj real. Un bichito muy descuidado **se escapa**: deja una
nota de despedida absurda ("Me voy a buscar una esquina que me quiera. — Pocholo") y desaparece
del mapa. Se recupera dejando su comida favorita junto a la nota. Nadie muere.

## Mientras no estás

Al abrir la app, la misma simulación se ejecuta **acelerada** desde la última vez:

- Las últimas **2 horas** se simulan completas (encuentros, peleas, romances, huevos, emigraciones).
- El resto, hasta **7 días**, solo necesidades y escapadas (cálculo directo).
- Después se muestra un resumen: "Mientras no estabas: Chencho y Ramona se pelearon 14 veces,
  nació Gominola, Peluso se mudó a Villa Charco."

## Voz

Balbuceo procedural tipo Animal Crossing: cada bichito **pronuncia** la frase de su burbuja letra
a letra con sílabas sintetizadas (formantes). Tono, velocidad y timbre salen de la receta
(tamaño → tono, personalidad → ritmo y entonación). Las frases se generan según el estado y la
personalidad ("¡esa nube me mira!") en español e inglés.

## Fuera del primer lanzamiento

Crecimiento con la edad, modelo de negocio (se decide con algo jugable en TestFlight), compartir
bichitos entre usuarios, widgets, notificaciones.

## Hoja de ruta

1. **Laboratorio del generador**: motor receta → píxeles y un test de CI que exporta una galería
   en PNG (100 semillas × expresiones). Nada más avanza hasta que la galería sea mona.
2. **Simulación sin pantalla** con tests: cerebro, encuentros, afinidad, necesidades, avance rápido.
3. **Mundo + gestos + editor**: primera build en TestFlight.
4. Crías, mapa con barrios y emigración, escapadas.
5. Voz y frases (es/en).
