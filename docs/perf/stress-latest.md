# Ourcraft stress test

- Date: 2026-10-17 12:42:35
- Godot 4.7-stable (official), macOS, Apple M1 Pro (Apple7), 8 cores
- Render size 2720x1710, vsync off, native extension on
- Minimum block 1 cm. Frame times are averages over 120 frames with everything in view.

## Carved 2 m block (1 cm cells, random cuts of 1–25 cm)

| cuts | generate ms | mesh + nodes ms | chunks | quads | nodes | draw calls | frame ms (cpu / gpu) | fps | 1 edit ms | save ms / MB | load ms | +RAM MB | +VRAM MB |
|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| 10 | 7.2 | 28.8 | 222 | 340 | 679 | 973 | 0.6 / n/a | 82 | 1.4 | 32.8 / 0.1 | 393 | 16 | 18 |
| 100 | 7.1 | 21.4 | 278 | 1,091 | 847 | 1,207 | 0.6 / n/a | 82 | 1.2 | 34.3 / 0.1 | 386 | 17 | 0 |
| 1,000 | 26.1 | 47.4 | 382 | 8,244 | 1,159 | 1,680 | 1.2 / n/a | 81 | 4.8 | 45.0 / 0.2 | 405 | 23 | 0 |
| 10,000 | 211 | 143 | 492 | 47,356 | 1,489 | 2,180 | 1.0 / n/a | 80 | 0.1 | 66.0 / 0.3 | 469 | 42 | 5 |
| 100,000 | 1,919 | 170 | 512 | 60,238 | 1,549 | 2,276 | 1.1 / n/a | 78 | 2.6 | 71.4 / 0.3 | 493 | 47 | 7 |

## Random noise cube (50% filled 1 cm cells; worst case for meshing)

| cells | generate ms | mesh + nodes ms | chunks | quads | nodes | draw calls | frame ms (cpu / gpu) | fps | 1 edit ms | save ms / MB | load ms | +RAM MB | +VRAM MB |
|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| 10,000 | 12.2 | 33.0 | 1 | 15,933 | 16 | 8 | 0.2 / n/a | 82 | 16.5 | 2.1 / 0.0 | 1.4 | 5 | 1 |
| 100,000 | 21.5 | 311 | 8 | 141,579 | 37 | 29 | 0.2 / n/a | 76 | 47.6 | 10.3 / 0.1 | 9.4 | 48 | 18 |
| 1,000,000 | 93.8 | 3,296 | 64 | 1,435,302 | 205 | 238 | 0.3 / n/a | 49 | 76.4 | 98.6 / 0.6 | 77.6 | 484 | 171 |
| 10,000,000 | skipped: next step projected at 14,353,020 quads |

## Many instances of one 10 cm object

| instances | generate ms | mesh + nodes ms | chunks | quads | nodes | draw calls | frame ms (cpu / gpu) | fps | 1 edit ms | save ms / MB | load ms | +RAM MB | +VRAM MB |
|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| 10 | 0.2 | 0.8 | 1 | 14 | 61 | 10 | 0.2 / n/a | 83 | 0.4 | 1.3 / 0.0 | 1.2 | 0 | 0 |
| 100 | 0.4 | 2.3 | 1 | 14 | 511 | 13 | 0.3 / n/a | 82 | 0.7 | 1.6 / 0.0 | 1.6 | 1 | 0 |
| 1,000 | 2.1 | 17.1 | 1 | 14 | 5,011 | 11 | 0.8 / n/a | 81 | 7.1 | 5.3 / 0.2 | 5.6 | 17 | 0 |
| 10,000 | 16.5 | 173 | 1 | 14 | 50,011 | 12 | 2.4 / n/a | 73 | 29.4 | 33.2 / 1.6 | 46.0 | 182 | 14 |
| 100,000 | 169 | 2,317 | 1 | 14 | 500,011 | 10 | 9.7 / n/a | 50 | 320 | 356 / 16.1 | 494 | 1822 | 40 |

## Many unique 10 cm objects

| objects | generate ms | mesh + nodes ms | chunks | quads | nodes | draw calls | frame ms (cpu / gpu) | fps | 1 edit ms | save ms / MB | load ms | +RAM MB | +VRAM MB |
|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| 10 | 0.8 | 5.5 | 10 | 140 | 61 | 39 | 0.4 / n/a | 83 | 1.0 | 6.3 / 0.0 | 10.3 | 0 | -18 |
| 100 | 4.1 | 16.0 | 100 | 1,400 | 511 | 414 | 0.4 / n/a | 82 | 0.5 | 32.1 / 0.1 | 97.9 | 6 | 0 |
| 1,000 | 26.7 | 114 | 1,000 | 14,000 | 5,011 | 4,026 | 1.3 / n/a | 79 | 0.4 | 313 / 0.6 | 998 | 68 | 1 |
| 10,000 | 294 | 1,141 | 10,000 | 140,000 | 50,011 | 27,153 | 9.6 / n/a | 35 | 1.1 | 3,093 / 6.4 | 9,960 | 695 | 17 |
| 100,000 | skipped: next step projected at 144s |
