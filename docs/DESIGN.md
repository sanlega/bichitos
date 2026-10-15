# Sistema de diseño de Bichitos: "Terrario"

Bichitos en pixel art, crujientes y llenos de color, viviendo en un mundo moderno, suave y casi vacío.
El contraste es intencionado: el mundo es un terrario de cristal limpio y los bichitos son lo único
pixelado, así que son los protagonistas.

## Principios

1. **Los bichitos primero.** El mundo y la interfaz son tranquilos y de poco contraste; el color
   fuerte y el pixel art son solo de los bichitos.
2. **Píxeles honestos.** Un píxel del bichito es siempre un cuadrado entero en pantalla: nunca
   se suaviza, nunca se escala a tamaños no enteros dentro del mismo sprite, nunca se rota.
3. **Exagerar con píxeles.** El squash & stretch, los saltos y las expresiones se hacen generando
   píxeles nuevos, no deformando la textura.
4. **Se lee sin menús.** Lo que siente un bichito se ve en su cara, su forma y su burbuja.
5. **Zona del pulgar.** Las acciones viven en una bandeja inferior; arriba solo hay título del barrio y ajustes.

## Pixel art de los bichitos

| Regla | Valor |
|---|---|
| Rejilla | 24×24 por bichito (el squash puede ocupar hasta 28×28; el lienzo es de 32×32 con el bichito centrado y apoyado en el suelo) |
| Filtrado | `.nearest` siempre |
| Escala en pantalla | El zoom del mapa redondea el tamaño del píxel del bichito a entero (×3 a ×8, ver Zoom) |
| Luz | Arriba a la izquierda |
| Contorno | 1 px, del tono más oscuro de la paleta (no negro puro) |

### Paletas indexadas

Cada píxel guarda un índice, no un color. Una paleta asigna color a cada índice:

| Índice | Uso |
|---|---|
| 0 | Transparente |
| 1 | Contorno |
| 2 | Sombra |
| 3 | Base |
| 4 | Brillo |
| 5 | Acento (mofletes, antenas, cuernos) |
| 6 | Blanco del ojo |
| 7 | Pupila |

12 paletas iniciales de 4 tonos (contorno → brillo) con un acento que contrasta: fresa, mandarina,
limón, menta, aguacate, cielo, lavanda, chicle, cacao, pizarra, coral y lima. Los índices 6 y 7 son
comunes a todas. Las necesidades bajas mezclan la paleta hacia gris (máximo 40%).

### Expresiones

Cada expresión es una variación paramétrica de ojos y boca, no un dibujo:

| Estado | Ojos | Boca |
|---|---|---|
| Normal | Pupila mirando hacia donde va | Pequeña línea |
| Parpadeo | Línea horizontal (2 frames) | Igual |
| Dormido | Arco hacia abajo | Abierta, pequeña |
| Enamorado | Pupila en forma de corazón | Sonrisa |
| Enfadado | Párpado superior inclinado hacia dentro | Línea en zigzag |
| Asustado | Ojos +1 px, pupila de 1 px | O abierta |
| Hambriento | Ojos grandes mirando la comida | Babita (acento) |
| Contento | Arcos hacia arriba | Sonrisa grande |
| Mareado | Espirales | Ondulada |

## Los dos mundos

Todo lo que se ve pertenece a uno de dos lenguajes, y nunca se mezclan dentro de un mismo objeto:

| | Pixel art | Mundo suave |
|---|---|---|
| Qué | Bichitos y lo que comen, ponen o sienten: comida, huevos, efectos e iconos de estado (zzz, corazones, estrellitas de mareo) | Suelo, agua, plantas, caminos, edificaciones, notas de escapada, interfaz |
| Técnica | Rejilla indexada, `.nearest`, escala entera | Formas vectoriales redondeadas, antialias, escala continua |
| Contorno | 1 px del tono más oscuro | Nunca |
| Color | Saturado (12 paletas) | Apagado, cerca del gris cálido de `mist` |
| Rotación | Nunca | Permitida (notas, hojas que caen) |

Regla rápida: si un bichito se lo come, lo pone o le sale de la cabeza, es pixel art. Si estaba ahí antes que él, es suave.

## El mapa

### Perspectiva y unidades

- **Maqueta vista desde arriba**: el suelo se ve en planta y todo lo que tiene altura (bichitos,
  edificios, árboles) se dibuja de frente, apoyado en su base. Se ordena por la `y` de la base:
  lo que está más abajo en pantalla tapa a lo de arriba. Así un bichito puede esconderse detrás de una casita.
- **Unidad `u`** = 1 píxel de bichito. Un bichito mide unos 24 u; su lienzo, 32 u.
- **Rejilla de colocación** de 8 u. Una **casilla** son 32 u (un lienzo de bichito).
- Luz arriba a la izquierda, como en los bichitos: las sombras caen abajo a la derecha.

### Zoom

El zoom fija cuántos puntos de pantalla mide una `u`, y por tanto un píxel de bichito. Al pellizcar
el mundo escala de forma continua (los bichitos usan el entero más cercano); al soltar, encaja en
el nivel más próximo con un muelle (`response 0.4, damping 0.8`).

| Nivel | 1 u = | Se ve |
|---|---|---|
| Mapa | 0,25 pt (el anillo entero cabe en un iPhone de 375 pt) | Barrios como manchas de su tinte con el nombre encima y caminos entre ellos; cada bichito es un punto redondo de 6 pt de su color base |
| Barrio | 3 pt | Edificios y bichitos; los estados solo como icono pixel sobre la cabeza |
| Calle | 5 pt | Además, nombres pixel y bocadillos |
| Cerca | 8 pt | El máximo detalle; para seguir a un bichito se usa «Seguir» en `BichitoPeek` |

Los nombres, bocadillos e iconos de estado tienen tamaño fijo en pantalla: no crecen con el zoom.

### Capas

De atrás adelante:

1. Fondo `mist` con el tinte del barrio.
2. Terreno: pradera, arena, agua, roca.
3. Caminos.
4. Cosas planas en el suelo: sombras, comida, notas de escapada.
5. **Capa ordenada por `y`**: bichitos, huevos, edificios, plantas, rocas.
6. Efectos de estado pixel.
7. Nombres, bocadillos, iconos de estado.
8. Luz ambiente (ver Ambiente).
9. Interfaz SwiftUI.

### Terreno

| Token | Hex | Uso |
|---|---|---|
| `mist` | `#F3F1EC` | Fondo de la app, suelo general y espacio entre barrios |
| `ground` | `#E7E3DA` | Caminos y claros |
| `meadow` | `#DDE6D0` | Pradera |
| `sand` | `#EEE4CE` | Arena |
| `rock` | `#D7D3CB` | Roca y muros |
| `water` | `#CFE2E7` | Agua |
| `waterEdge` | `#B7D1D8` | Orilla del agua, 2 u |
| `foliage` | `#B9CCA9` | Copas y arbustos |
| `foliageShade` | `#A1B791` | Sombra de copas y arbustos |
| `bark` | `#C9B9A3` | Troncos y madera |
| `groundShadow` | ink al 10% | Sombras proyectadas |

- Las manchas de terreno salen de ruido suavizado con la semilla del barrio; radio de curva mínimo 16 u, nada de esquinas.
- Caminos de 24 u de ancho, curvas Bézier con extremos redondos. Los bichitos prefieren caminar por ellos.
- El agua no se pisa. Dos reflejos (línea de 6×2 u, `card` al 60%) aparecen y se desvanecen cada ~4 s.
- Las sombras proyectadas son elipses `groundShadow` bajo la base, desplazadas 4 u a la derecha.
- Entre barrios el mundo es `mist` casi vacío, con alguna planta suelta; los caminos los unen.

### Barrios

Un barrio es una receta, como un bichito: `(nombre, tinte, terreno dominante, monumento, personalidad afín, semilla)`.
Ocupa una mancha de unas 12×9 casillas. Su tinte se mezcla al 8% sobre `mist` en todo su suelo y
al 45% en los tejados de sus edificios.

| Barrio | Afín a | Tinte | Terreno | Monumento |
|---|---|---|---|---|
| Plaza Mayor (inicial) | nadie | `#F2B48C` | Arena y caminos en estrella | Fuente redonda |
| Villa Charco | curiosa | `#7FB8C9` | Charcos | Telescopio |
| Las Esquinas | territorial | `#C9907F` | Roca, muritos en L | Torre con banderita |
| Almohadilla | dormilona | `#A99BD6` | Pradera en lomas | Hamaca gigante |
| Pista Loca | hiperactiva | `#E6C55A` | Un camino en circuito | Rueda de hámster |
| El Matorral | nerviosa | `#8DB88A` | Arbustos densos | Caja con agujero (escondite) |
| La Rosaleda | romántica | `#E89BB0` | Flores | Glorieta con banco |

- **Bloqueado**: en el nivel Mapa, contorno discontinuo `hairline` con candado y la población que falta («faltan 4 bichitos»). No se dibuja su interior.
- **Desbloqueo**: una niebla `mist` se disipa desde el centro (1,2 s) y aparece el cartel del barrio.
- **Cartel**: poste `bark` con tabla `card` y el nombre en 15 Heavy; uno en cada entrada de camino.

## Edificaciones

No hay personas: todo está construido a escala de bichito, como juguetes de madera pintada.
Cada edificio da sitio a un estado de la simulación; lo que no tiene uso es **decoración**.

### Catálogo

| Edificio | Tamaño (u) | Para | Detalle |
|---|---|---|---|
| Casita | 48×48 | Dormir | Caben 2. Los zzz salen por la chimenea; de noche la ventana se enciende |
| Comedero | 40×24 | Comer | Cuenco bajo; la comida que cae dentro se ve asomar |
| Banco | 40×20 | Enamorarse, descansar | Dos bichitos sentados se miran |
| Nido | 32×16 | Incubar | Cuenco de paja (`bark`) donde se ponen los huevos |
| Monumento | 96–128 de ancho | Identidad del barrio | Uno por barrio (ver Barrios); los afines se reúnen alrededor |

| Decoración | Tamaño (u) | Bloquea el paso |
|---|---|---|
| Árbol | 40×56 | Solo el tronco |
| Arbusto | 24×16 | No (los nerviosos se esconden dentro) |
| Roca | 16–32 | Sí |
| Flor | 8×12 | No |
| Valla, murito | 8 de fondo, largo libre | Sí |
| Farola | 8×40 | No |

El usuario no construye en el primer lanzamiento: cada barrio coloca sus edificios a partir de su semilla.

### Cómo se dibujan

Un edificio es una receta `(tipo, semilla, barrio)` → formas vectoriales; determinista, como los bichitos.

- **Piezas**: base (rectángulo de radio 4 u), cuerpo (radio 8 u), tejado (cúpula, triángulo romo
  o plano con alero), puerta en arco de 20×26 u (un bichito cabe justo), ventanas redondas de 8 u
  o cuadradas de radio 3 u, y un extra (chimenea, banderita o antena).
- **Tres tonos**: `face` = `card` mezclado al 15% con el tinte del barrio; `side` = `face` oscurecido
  un 8%, en una franja del 25% del ancho a la derecha; tejado = tinte del barrio al 45% sobre `mist`.
  Puertas y ventanas en `ink` al 70%; de noche, ventanas en `warmLight`.
- **Sin contorno.** Ningún trazo de menos de 2 u; esquinas de radio 4 u como mínimo.
- **Variación por semilla**: forma del tejado, posición de puertas y ventanas, extra y luminosidad ±4%.
- **Ocupado**: la puerta se cierra y encima asoma el icono de estado de quien está dentro.
- Se rasterizan a textura una vez por nivel de zoom y se cachean (`SKShapeNode` en vivo es caro).

## Ambiente

**Día y noche** con el reloj real: una capa de color multiplicado sobre el mundo, nunca sobre la
interfaz. Los bichitos la reciben a mitad de intensidad para seguir leyéndose.

| Fase | Horas | Capa |
|---|---|---|
| Día | 8–19 | Ninguna |
| Atardecer y amanecer | 19–21, 6–8 | `#FFB38A` al 12% |
| Noche | 21–6 | `night` `#3B3F6B` al 35% |

- De noche, ventanas y farolas se encienden: círculo `warmLight` al 40% en modo suma, radio 24 u.
- **Nubes**: sombras `ink` al 6%, manchas grandes que cruzan el mapa despacio (el pretexto para que los bichitos sospechen de ellas).
- Con **Reducir movimiento**: sin nubes ni reflejos, y los cambios de fase son fundidos.

## La interfaz

### Color

Los tokens del mapa, más:

| Token | Hex | Uso |
|---|---|---|
| `card` | `#FFFFFF` | Tarjetas, bandeja, hojas |
| `ink` | `#2B2A33` | Texto e iconos |
| `inkDim` | ink al 55% | Texto secundario |
| `hairline` | ink al 10% | Bordes finos |
| `fill` | ink al 6% | Botones secundarios y pistas de barras |
| `accent` | `#FF6B4A` | Marca, botón principal, modo activo |
| `hunger` | `#FFA45B` | Hambre |
| `sleep` | `#9C8FE0` | Sueño |
| `love` | `#FF7FA8` | Cariño |
| `warmLight` | `#FFD27A` | Luces de noche |

Sobre `accent` el texto va en `ink` (contraste 5:1); el blanco no llega a 3:1.

La app es **solo clara** (`.preferredColorScheme(.light)`): la noche la pone el mundo, no el sistema.

### Tipografía

SF Pro **Rounded** en toda la interfaz. Los nombres de los bichitos sobre el mapa van en una
fuente pixel (bitmap 5×7 propia, generada como los sprites) para enlazarlos con su bichito.

| Rol | Estilo |
|---|---|
| Título del barrio | 22 Heavy |
| Título de tarjeta / nombre en la ficha | 18 Heavy |
| Botón principal | 17 Heavy |
| Cuerpo / chips | 15 Semibold |
| Descripción absurda | 15 Medium, cursiva |
| Pista / pie | 13 Medium, `inkDim` |
| Nombre sobre el mapa | Pixel 5×7 a ×2 (Calle) o ×3 (Cerca) |

### Forma y espacio

- Radios: **12** chips, **20** tarjetas y bandeja, **28** hojas; cápsula en botones de texto; círculos de 44 pt para botones de icono.
- Espaciado: 4 · 8 · 12 · 16 · 24 · 32. Margen de pantalla: 16.
- Sombras suaves y difusas (y 4, blur 16, ink al 8%) en todo lo que flota sobre el mapa.
- Los bichitos tienen una sombra pixel de 1 fila bajo los pies.

### Iconos

SF Symbols, peso semibold, escala media, color `ink` (o el de su necesidad).

| Acción | Símbolo |
|---|---|
| Comida | `carrot.fill` |
| Susto | `bolt.fill` |
| Nuevo bichito | `plus` |
| Noticias | `newspaper.fill` |
| Mapa | `map.fill` |
| Ajustes | `gearshape.fill` |
| Acariciar | `hand.raised.fill` |
| Lanzar | `arrow.up.forward` |
| Dado | `dice.fill` |
| Hambre / sueño / cariño | `fork.knife` / `moon.fill` / `heart.fill` |

Los iconos de estado **sobre el mapa** no son SF Symbols: son pixel art, porque son del bichito.

### Pantalla del mundo

```
┌──────────────────────────────┐
│ (Villa Charco · 14)     (⚙)  │  píldora del barrio · ajustes
│ ( Ramona puso un huevo )     │  aviso
│                              │
│             mapa             │
│                              │
│ ┌──────────────────────────┐ │
│ │ comida susto (+) noti mapa│ │  bandeja
│ └──────────────────────────┘ │
└──────────────────────────────┘
```

- Arriba solo la píldora del barrio (nombre y población; tocarla abre `BarrioPicker`) y ajustes.
- La bandeja flota a 16 pt sobre la zona segura, con 5 botones como máximo; el del centro es el principal (`accent`, 56 pt).
- Tocar un bichito sube `BichitoPeek` sobre la bandeja con sus acciones; mantener pulsado abre `BichitoCard`.

### Modos

Solo hay un modo activo a la vez y siempre se sale con «Hecho».

- **Modo comida**: la bandeja se convierte en `FoodPicker`, el borde de la pantalla se marca con
  3 pt de `accent` y aparece la pista «Toca el suelo para soltar comida». Cada toque suelta la comida elegida.

### Botones

| Tipo | Aspecto |
|---|---|
| Principal | Cápsula `accent`, texto `ink` 17 Heavy, alto 50 |
| Secundario | Cápsula `fill`, texto `ink` 15 Semibold, alto 44 |
| Icono | Círculo de 44 pt: `card` con sombra sobre el mapa, `fill` dentro de hojas |
| Chip | Cápsula con borde `hairline`; seleccionado = relleno `ink` con texto `card` |

Al pulsar: escala 0.94 con muelle y háptico ligero. Deshabilitado: opacidad 35%.

### Movimiento y háptica

- Muelles de la interfaz: `response 0.35, damping 0.7`. Cámara que viaja a un bichito o a un barrio: `response 0.5, damping 0.85`.
- Los bichitos se animan con su propia simulación, nunca con animaciones de SwiftUI.
- Con **Reducir movimiento** los muelles pasan a fundidos de 0,2 s.

| Momento | Háptico |
|---|---|
| Acariciar | `soft` |
| Soltar al lanzar | `medium` |
| Aterrizaje, *boing* | `rigid` ligero |
| Nace una cría, se desbloquea un barrio | `success` |

## Componentes

| Componente | Descripción |
|---|---|
| `WorldView` | Mapa a pantalla completa con paneo y zoom, píldora del barrio, avisos y bandeja |
| `BarrioPill` | Cápsula `card` arriba a la izquierda: nombre del barrio (22 Heavy) y población |
| `BarrioPicker` | Hoja con los barrios: muestra de su tinte, población y afinidad; los bloqueados con candado y lo que falta. Tocar uno viaja a él |
| `Tray` | Bandeja inferior flotante: tarjeta `card` de radio 20 con botones de icono y el principal en el centro |
| `Toast` | Aviso de un evento («Ramona puso un huevo»): cápsula `card` bajo la píldora, 15 Semibold, 3 s, de uno en uno; tocarlo lleva la cámara al sitio |
| `NewsFeed` | Hoja de noticias del terrario: eventos en orden cronológico con los bichitos implicados en pixel ×2 |
| `Bubble` | Bocadillo `card` con cola sobre el bichito; el texto aparece letra a letra al ritmo de la voz |
| `BichitoPeek` | Tarjeta compacta sobre la bandeja: sprite, nombre, tres `NeedBar` y los botones Acariciar, Dar de comer, Seguir y Ficha |
| `BichitoCard` | Ficha (mantener pulsado): sprite grande, nombre, descripción, barras de necesidades, parientes, amigos y rivales |
| `NeedBar` | Pista `fill` de 8 pt de alto y radio 4 con relleno del color de la necesidad, icono a la izquierda y número a la derecha; por debajo del 25% el relleno pasa a `accent` |
| `FoodPicker` | La bandeja en modo comida: los tipos de comida en pixel ×3 y «Hecho» |
| `CreatorSheet` | Hoja del editor: vista previa grande arriba, chips por categoría, ajustes plegables, dado, Soltar |
| `Chip` | Ver Botones |
| `Dice` | Botón de icono redondo; tocar cambia la semilla, mantener pulsado lo aleatoriza todo |
| `Note` | Nota de escapada: papelito `card` de 20×16 u girado ±6° con sombra, donde estaba el bichito; tocarla abre el texto |
| `AwaySummary` | Hoja de «mientras no estabas» al abrir la app |
| `UnlockBanner` | Tarjeta al desbloquear un barrio: nombre, tinte y a quién atrae; «Ir a verlo» viaja con la cámara |

Las hojas usan los tamaños `.medium` y `.large` con agarradera, salvo `CreatorSheet`, que es siempre `.large`.

## Accesibilidad

- Todas las acciones con gestos tienen también un botón (acariciar, lanzar, dar de comer, asustar).
- Cada bichito expone su nombre y su estado actual a VoiceOver («Pocholo, durmiendo, con hambre»);
  cada edificio, su tipo y quién está dentro («Casita, dentro: Pocholo»).
- Las necesidades se muestran como barras con número, no solo por el aspecto del sprite.
- Texto de la interfaz con contraste de 4,5:1 como mínimo; la luz de noche nunca cubre la interfaz.
- Dynamic Type en hojas y tarjetas; el mapa usa tamaños fijos.
- Reducir movimiento se respeta en el mapa y en la interfaz (ver Ambiente y Movimiento).
- Hápticos y voz se pueden desactivar por separado.
