# Ourcraft stress test

- Date: 2026-10-17 13:03:46
- Godot 4.7-stable (official), macOS, Apple M1 Pro (Apple7), 8 cores
- Render size 2720x1710, vsync off, native extension on
- Minimum block 1 cm. Frame times are averages over 120 frames with everything in view.

## Carved 2 m block (1 cm cells, random cuts of 1–25 cm)

| cuts | generate ms | mesh + nodes ms | chunks | quads | nodes | bodies | draw calls | frame ms (cpu / gpu) | fps | 1 edit ms | save ms / MB | load ms | +RAM MB | +VRAM MB |
|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| 10 | 8.1 | 18.1 | 222 | 340 | 235 | 222 | 973 | 0.6 / n/a | 122 | 2.6 | 36.9 / 0.1 | 388 | 15 | 0 |
| 100 | 7.5 | 18.8 | 278 | 1,091 | 291 | 278 | 1,207 | 0.6 / n/a | 116 | 1.2 | 33.9 / 0.1 | 391 | 15 | 0 |
| 1,000 | 25.8 | 42.1 | 382 | 8,244 | 395 | 382 | 1,680 | 0.8 / n/a | 119 | 1.8 | 43.2 / 0.2 | 403 | 21 | 0 |
| 10,000 | 195 | 111 | 492 | 47,356 | 505 | 492 | 2,180 | 0.8 / n/a | 115 | 0.1 | 64.6 / 0.3 | 480 | 39 | 5 |
| 100,000 | 1,859 | 140 | 512 | 60,238 | 525 | 512 | 2,276 | 0.8 / n/a | 105 | 3.0 | 69.9 / 0.3 | 488 | 44 | 7 |

## Random noise cube (50% filled 1 cm cells; worst case for meshing)

| cells | generate ms | mesh + nodes ms | chunks | quads | nodes | bodies | draw calls | frame ms (cpu / gpu) | fps | 1 edit ms | save ms / MB | load ms | +RAM MB | +VRAM MB |
|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| 10,000 | 12.1 | 19.2 | 1 | 15,933 | 14 | 1 | 8 | 0.2 / n/a | 113 | 16.6 | 2.0 / 0.0 | 1.4 | 5 | 1 |
| 100,000 | 21.3 | 166 | 8 | 141,579 | 21 | 8 | 29 | 0.4 / n/a | 104 | 49.5 | 10.3 / 0.1 | 9.5 | 47 | 18 |
| 1,000,000 | 93.1 | 1,789 | 64 | 1,435,302 | 77 | 64 | 238 | 0.5 / n/a | 60 | 82.2 | 97.1 / 0.6 | 77.7 | 484 | 171 |
| 10,000,000 | skipped: next step projected at 14,353,020 quads |

## Many instances of one 10 cm object

| instances | generate ms | mesh + nodes ms | chunks | quads | nodes | bodies | draw calls | frame ms (cpu / gpu) | fps | 1 edit ms | save ms / MB | load ms | +RAM MB | +VRAM MB |
|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| 10 | 0.2 | 0.6 | 1 | 14 | 41 | 10 | 10 | 0.4 / n/a | 117 | 0.4 | 1.2 / 0.0 | 1.3 | 0 | 0 |
| 100 | 1.2 | 3.4 | 1 | 14 | 311 | 100 | 13 | 0.3 / n/a | 112 | 0.6 | 1.6 / 0.0 | 1.5 | 1 | 0 |
| 1,000 | 2.0 | 13.3 | 1 | 14 | 3,011 | 1,000 | 11 | 1.0 / n/a | 110 | 1.3 | 4.2 / 0.2 | 5.4 | 13 | 0 |
| 10,000 | 16.8 | 135 | 1 | 14 | 30,011 | 8,136 | 12 | 1.9 / n/a | 97 | 11.2 | 31.4 / 1.6 | 45.2 | 138 | 14 |
| 100,000 | 165 | 1,628 | 1 | 14 | 300,011 | 8,180 | 10 | 9.7 / n/a | 63 | 100 | 372 / 16.1 | 489 | 1267 | 40 |

## Many unique 10 cm objects

| objects | generate ms | mesh + nodes ms | chunks | quads | nodes | bodies | draw calls | frame ms (cpu / gpu) | fps | 1 edit ms | save ms / MB | load ms | +RAM MB | +VRAM MB |
|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| 10 | 1.3 | 2.2 | 10 | 140 | 41 | 10 | 39 | 0.4 / n/a | 117 | 0.7 | 7.1 / 0.0 | 9.9 | 0 | 0 |
| 100 | 3.0 | 13.2 | 100 | 1,400 | 311 | 100 | 414 | 0.3 / n/a | 113 | 0.3 | 31.6 / 0.1 | 107 | 6 | 0 |
| 1,000 | 27.3 | 99.9 | 1,000 | 14,000 | 3,011 | 1,000 | 4,026 | 1.3 / n/a | 109 | 0.3 | 306 / 0.6 | 979 | 63 | 1 |
| 10,000 | 284 | 1,088 | 10,000 | 140,000 | 30,011 | 8,136 | 27,153 | 8.2 / n/a | 45 | 0.8 | 3,028 / 6.4 | 10,203 | 647 | 17 |
| 100,000 | skipped: next step projected at 146s |
