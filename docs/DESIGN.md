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
| Escala en pantalla | El zoom del mapa redondea el tamaño del píxel del bichito a entero (×3 a ×8) |
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

## El mundo y la interfaz

### Color

Fondo claro y suave. Los tonos del mundo nunca compiten con las paletas de los bichitos.

| Token | Hex | Uso |
|---|---|---|
| `mist` | `#F3F1EC` | Fondo de la app y del mapa |
| `ground` | `#E7E3DA` | Suelo y caminos del mapa |
| `card` | `#FFFFFF` | Tarjetas, bandeja, hojas |
| `ink` | `#2B2A33` | Texto e iconos |
| `inkDim` | ink al 55% | Texto secundario |
| `hairline` | ink al 10% | Bordes finos |
| `accent` | `#FF6B4A` | Marca, botón principal |

Cada barrio tiene un **tinte** propio muy suave (mezcla del 8% sobre `mist`) para distinguirlos al hacer zoom out.

### Tipografía

SF Pro **Rounded** en toda la interfaz. Los nombres de los bichitos sobre el mapa van en una
fuente pixel (bitmap 5×7 propia, generada como los sprites) para enlazarlos con su bichito.

| Rol | Estilo |
|---|---|
| Título del barrio | 22 Heavy |
| Título de tarjeta / nombre en la ficha | 18 Heavy |
| Cuerpo / chips | 15 Semibold |
| Descripción absurda | 15 Medium, cursiva |
| Pista / pie | 13 Medium, `inkDim` |
| Nombre sobre el mapa | Pixel 5×7 a escala entera |

### Forma, espacio, movimiento

- Radios: **12** chips, **20** tarjetas y bandeja, **28** hojas; círculos de 44pt para botones de icono.
- Espaciado: 4 · 8 · 12 · 16 · 24 · 32.
- Sombras suaves y difusas (y 4, blur 16, ink al 8%) en tarjetas y bandeja; los bichitos tienen una
  sombra pixel de 1 fila bajo los pies.
- Muelles de la interfaz: `response 0.35, damping 0.7`. Los bichitos se animan con su propia
  simulación, nunca con animaciones de SwiftUI.

## Componentes

| Componente | Descripción |
|---|---|
| `WorldView` | Mapa a pantalla completa con paneo y zoom; bandeja inferior con comida, susto y nuevo bichito |
| `Tray` | Bandeja inferior flotante: tarjeta blanca de radio 20 con botones de icono |
| `Bubble` | Bocadillo blanco con cola sobre el bichito; el texto aparece letra a letra al ritmo de la voz |
| `BichitoCard` | Ficha (mantener pulsado): sprite grande, nombre, descripción, barras de necesidades, parientes, amigos y rivales |
| `CreatorSheet` | Hoja del editor: vista previa grande arriba, chips por categoría, ajustes plegables, dado, Soltar |
| `Chip` | Cápsula con borde `hairline`; seleccionado = relleno `ink` con texto `card` |
| `Dice` | Botón de icono redondo; tocar cambia la semilla, mantener pulsado lo aleatoriza todo |
| `Note` | Nota de escapada: papelito en el mapa donde estaba el bichito |
| `AwaySummary` | Hoja de "mientras no estabas" al abrir la app |

## Accesibilidad

- Todas las acciones con gestos tienen también un botón (acariciar, lanzar, dar de comer, asustar).
- Cada bichito expone su nombre y su estado actual a VoiceOver ("Pocholo, durmiendo, con hambre").
- Las necesidades se muestran como barras con número, no solo por el aspecto del sprite.
- Dynamic Type en hojas y tarjetas; el mapa usa tamaños fijos.
- Hápticos y voz se pueden desactivar por separado.
