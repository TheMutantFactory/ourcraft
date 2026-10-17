# Ourcraft stress test

- Date: 2026-10-17 13:44:17
- Godot 4.7-stable (official), macOS, Apple M1 Pro (Apple7), 8 cores
- Render size 2720x1710, vsync off, native extension on
- Minimum block 1 cm. Frame times are averages over 120 frames with everything in view.

## Carved 2 m block (1 cm cells, random cuts of 1–25 cm)

| cuts | generate ms | mesh + nodes ms | chunks | quads | nodes | regions | bodies | draw calls | frame ms (cpu / gpu) | fps | 1 edit ms | save ms / MB | load ms | +RAM MB | +VRAM MB |
|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| 10 | 17.8 | 41.7 | 343 | 340 | 234 | 1 | 222 | 973 | 0.5 / n/a | 122 | 3.5 | 3.2 / 0.0 | 1.3 | 4 | 0 |
| 100 | 14.4 | 41.0 | 343 | 1,091 | 290 | 1 | 278 | 1,207 | 0.6 / n/a | 123 | 3.5 | 3.5 / 0.1 | 1.3 | 4 | 0 |
| 1,000 | 64.1 | 55.6 | 382 | 8,244 | 394 | 1 | 382 | 1,680 | 0.8 / n/a | 121 | 4.9 | 5.3 / 0.2 | 1.7 | 9 | 0 |
| 10,000 | 535 | 113 | 492 | 47,356 | 504 | 1 | 492 | 2,180 | 0.8 / n/a | 116 | 0.2 | 5.7 / 0.3 | 2.4 | 23 | 5 |
| 100,000 | 4,799 | 125 | 512 | 60,238 | 524 | 1 | 512 | 2,276 | 0.8 / n/a | 114 | 2.9 | 5.5 / 0.3 | 2.3 | 28 | 7 |

## Random noise cube (50% filled 1 cm cells; worst case for meshing)

| cells | generate ms | mesh + nodes ms | chunks | quads | nodes | regions | bodies | draw calls | frame ms (cpu / gpu) | fps | 1 edit ms | save ms / MB | load ms | +RAM MB | +VRAM MB |
|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| 10,000 | 11.4 | 3.7 | 1 | 15,933 | 13 | 1 | 1 | 8 | 0.2 / n/a | 123 | 17.3 | 1.0 / 0.0 | 0.2 | 5 | 1 |
| 100,000 | 14.4 | 30.7 | 8 | 141,579 | 20 | 1 | 8 | 29 | 0.4 / n/a | 111 | 54.0 | 1.4 / 0.0 | 0.3 | 47 | 18 |
| 1,000,000 | 28.5 | 281 | 64 | 1,435,302 | 76 | 1 | 64 | 238 | 0.5 / n/a | 61 | 71.3 | 3.1 / 0.1 | 0.5 | 484 | 171 |
| 10,000,000 | skipped: next step projected at 14,353,020 quads |

## Many instances of one 10 cm object

| instances | generate ms | mesh + nodes ms | chunks | quads | nodes | regions | bodies | draw calls | frame ms (cpu / gpu) | fps | 1 edit ms | save ms / MB | load ms | +RAM MB | +VRAM MB |
|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| 10 | 0.3 | 0.5 | 1 | 14 | 13 | 1 | 10 | 9 | 0.4 / n/a | 125 | 0.9 | 2.8 / 0.0 | 0.5 | 0 | 0 |
| 100 | 0.4 | 1.2 | 1 | 14 | 13 | 1 | 100 | 10 | 0.2 / n/a | 122 | 0.6 | 2.1 / 0.0 | 0.7 | 0 | 0 |
| 1,000 | 2.1 | 7.2 | 1 | 14 | 13 | 1 | 1,000 | 10 | 0.3 / n/a | 118 | 1.4 | 9.3 / 0.1 | 4.3 | 4 | 0 |
| 10,000 | 17.6 | 70.3 | 1 | 14 | 13 | 1 | 8,136 | 8 | 0.3 / n/a | 103 | 5.5 | 33.4 / 0.8 | 42.1 | 45 | 0 |
| 100,000 | 165 | 736 | 1 | 14 | 13 | 1 | 8,180 | 7 | 0.2 / n/a | 68 | 1.9 | 317 / 8.5 | 458 | 318 | 9 |

## Many unique 10 cm objects

| objects | generate ms | mesh + nodes ms | chunks | quads | nodes | regions | bodies | draw calls | frame ms (cpu / gpu) | fps | 1 edit ms | save ms / MB | load ms | +RAM MB | +VRAM MB |
|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| 10 | 0.9 | 1.3 | 10 | 140 | 13 | 1 | 10 | 13 | 0.2 / n/a | 124 | 0.6 | 1.5 / 0.0 | 0.4 | 0 | 0 |
| 100 | 5.3 | 9.6 | 100 | 1,400 | 13 | 1 | 100 | 15 | 0.3 / n/a | 122 | 1.0 | 7.2 / 0.0 | 2.2 | 1 | 0 |
| 1,000 | 49.3 | 89.0 | 1,000 | 14,000 | 13 | 1 | 1,000 | 13 | 0.4 / n/a | 118 | 1.0 | 20.9 / 0.2 | 17.0 | 16 | 1 |
| 10,000 | 500 | 879 | 10,000 | 140,000 | 21 | 9 | 8,136 | 34 | 0.4 / n/a | 101 | 0.8 | 142 / 2.4 | 172 | 147 | 16 |
| 100,000 | 4,923 | 8,965 | 100,000 | 1,400,000 | 76 | 64 | 8,180 | 77 | 0.3 / n/a | 65 | 1.1 | 1,798 / 23.8 | 2,434 | 932 | 169 |
