# Ourcraft stress test

- Date: 2026-10-17 13:16:41
- Godot 4.7-stable (official), macOS, Apple M1 Pro (Apple7), 8 cores
- Render size 2720x1710, vsync off, native extension on
- Minimum block 1 cm. Frame times are averages over 120 frames with everything in view.

## Carved 2 m block (1 cm cells, random cuts of 1–25 cm)

| cuts | generate ms | mesh + nodes ms | chunks | quads | nodes | regions | bodies | draw calls | frame ms (cpu / gpu) | fps | 1 edit ms | save ms / MB | load ms | +RAM MB | +VRAM MB |
|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| 10 | 6.3 | 16.1 | 222 | 340 | 234 | 1 | 222 | 973 | 0.5 / n/a | 122 | 1.3 | 32.3 / 0.1 | 390 | 15 | 0 |
| 100 | 7.0 | 18.3 | 278 | 1,091 | 290 | 1 | 278 | 1,207 | 0.5 / n/a | 123 | 1.1 | 33.5 / 0.1 | 382 | 15 | 0 |
| 1,000 | 25.1 | 40.8 | 382 | 8,244 | 394 | 1 | 382 | 1,680 | 0.7 / n/a | 122 | 3.6 | 44.1 / 0.2 | 405 | 21 | 0 |
| 10,000 | 194 | 113 | 492 | 47,356 | 504 | 1 | 492 | 2,180 | 0.8 / n/a | 117 | 0.1 | 65.7 / 0.3 | 477 | 39 | 5 |
| 100,000 | 1,868 | 138 | 512 | 60,238 | 524 | 1 | 512 | 2,276 | 0.8 / n/a | 114 | 2.8 | 73.1 / 0.3 | 504 | 44 | 7 |

## Random noise cube (50% filled 1 cm cells; worst case for meshing)

| cells | generate ms | mesh + nodes ms | chunks | quads | nodes | regions | bodies | draw calls | frame ms (cpu / gpu) | fps | 1 edit ms | save ms / MB | load ms | +RAM MB | +VRAM MB |
|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| 10,000 | 12.3 | 19.0 | 1 | 15,933 | 13 | 1 | 1 | 8 | 0.3 / n/a | 123 | 21.1 | 2.1 / 0.0 | 1.3 | 5 | 1 |
| 100,000 | 21.8 | 167 | 8 | 141,579 | 20 | 1 | 8 | 29 | 0.4 / n/a | 112 | 45.2 | 9.5 / 0.1 | 9.4 | 47 | 18 |
| 1,000,000 | 92.6 | 1,812 | 64 | 1,435,302 | 76 | 1 | 64 | 238 | 0.6 / n/a | 61 | 70.6 | 98.4 / 0.6 | 77.4 | 484 | 171 |
| 10,000,000 | skipped: next step projected at 14,353,020 quads |

## Many instances of one 10 cm object

| instances | generate ms | mesh + nodes ms | chunks | quads | nodes | regions | bodies | draw calls | frame ms (cpu / gpu) | fps | 1 edit ms | save ms / MB | load ms | +RAM MB | +VRAM MB |
|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| 10 | 0.2 | 0.7 | 1 | 14 | 13 | 1 | 10 | 9 | 0.2 / n/a | 124 | 0.5 | 1.3 / 0.0 | 1.1 | 0 | 0 |
| 100 | 0.4 | 1.3 | 1 | 14 | 13 | 1 | 100 | 10 | 0.3 / n/a | 122 | 0.5 | 1.5 / 0.0 | 1.6 | 0 | 0 |
| 1,000 | 5.8 | 7.4 | 1 | 14 | 13 | 1 | 1,000 | 10 | 0.3 / n/a | 117 | 1.6 | 9.1 / 0.2 | 5.7 | 4 | 0 |
| 10,000 | 17.0 | 70.2 | 1 | 14 | 13 | 1 | 8,136 | 8 | 0.3 / n/a | 104 | 2.2 | 32.4 / 1.6 | 57.2 | 44 | 0 |
| 100,000 | 167 | 719 | 1 | 14 | 13 | 1 | 8,180 | 7 | 0.3 / n/a | 68 | 1.8 | 327 / 16.1 | 478 | 316 | 9 |

## Many unique 10 cm objects

| objects | generate ms | mesh + nodes ms | chunks | quads | nodes | regions | bodies | draw calls | frame ms (cpu / gpu) | fps | 1 edit ms | save ms / MB | load ms | +RAM MB | +VRAM MB |
|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| 10 | 0.5 | 2.1 | 10 | 140 | 13 | 1 | 10 | 13 | 0.2 / n/a | 125 | 0.4 | 4.2 / 0.0 | 10.4 | 0 | 0 |
| 100 | 2.9 | 10.6 | 100 | 1,400 | 13 | 1 | 100 | 15 | 0.3 / n/a | 122 | 0.3 | 31.9 / 0.1 | 97.1 | 5 | 0 |
| 1,000 | 27.8 | 102 | 1,000 | 14,000 | 13 | 1 | 1,000 | 13 | 0.3 / n/a | 118 | 1.8 | 305 / 0.6 | 996 | 54 | 3 |
| 10,000 | 278 | 1,139 | 10,000 | 140,000 | 21 | 9 | 8,136 | 34 | 0.4 / n/a | 102 | 0.9 | 2,971 / 6.4 | 9,781 | 543 | 34 |
| 100,000 | skipped: next step projected at 141s |
