# Ourcraft stress test

- Date: 2026-10-17 13:09:52
- Godot 4.7-stable (official), macOS, Apple M1 Pro (Apple7), 8 cores
- Render size 2720x1710, vsync off, native extension on
- Minimum block 1 cm. Frame times are averages over 120 frames with everything in view.

## Carved 2 m block (1 cm cells, random cuts of 1–25 cm)

| cuts | generate ms | mesh + nodes ms | chunks | quads | nodes | bodies | draw calls | frame ms (cpu / gpu) | fps | 1 edit ms | save ms / MB | load ms | +RAM MB | +VRAM MB |
|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| 10 | 6.2 | 15.3 | 222 | 340 | 232 | 222 | 973 | 0.6 / n/a | 118 | 1.1 | 32.9 / 0.1 | 386 | 15 | 18 |
| 100 | 7.8 | 18.3 | 278 | 1,091 | 288 | 278 | 1,207 | 0.6 / n/a | 119 | 0.9 | 33.6 / 0.1 | 391 | 15 | 0 |
| 1,000 | 24.5 | 43.0 | 382 | 8,244 | 392 | 382 | 1,680 | 0.7 / n/a | 117 | 1.7 | 43.3 / 0.2 | 403 | 21 | 0 |
| 10,000 | 195 | 110 | 492 | 47,356 | 502 | 492 | 2,180 | 0.8 / n/a | 112 | 0.1 | 65.3 / 0.3 | 474 | 39 | 5 |
| 100,000 | 1,924 | 139 | 512 | 60,238 | 522 | 512 | 2,276 | 0.8 / n/a | 110 | 2.5 | 70.4 / 0.3 | 492 | 44 | 7 |

## Random noise cube (50% filled 1 cm cells; worst case for meshing)

| cells | generate ms | mesh + nodes ms | chunks | quads | nodes | bodies | draw calls | frame ms (cpu / gpu) | fps | 1 edit ms | save ms / MB | load ms | +RAM MB | +VRAM MB |
|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| 10,000 | 12.1 | 18.0 | 1 | 15,933 | 11 | 1 | 8 | 0.3 / n/a | 116 | 17.0 | 2.3 / 0.0 | 1.5 | 5 | 1 |
| 100,000 | 21.9 | 174 | 8 | 141,579 | 18 | 8 | 29 | 0.3 / n/a | 106 | 47.5 | 10.4 / 0.1 | 9.7 | 47 | 18 |
| 1,000,000 | 92.7 | 1,884 | 64 | 1,435,302 | 74 | 64 | 238 | 0.4 / n/a | 59 | 72.7 | 98.2 / 0.6 | 77.2 | 484 | 171 |
| 10,000,000 | skipped: next step projected at 14,353,020 quads |

## Many instances of one 10 cm object

| instances | generate ms | mesh + nodes ms | chunks | quads | nodes | bodies | draw calls | frame ms (cpu / gpu) | fps | 1 edit ms | save ms / MB | load ms | +RAM MB | +VRAM MB |
|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| 10 | 0.3 | 0.6 | 1 | 14 | 11 | 10 | 9 | 0.4 / n/a | 120 | 0.4 | 1.9 / 0.0 | 1.1 | 0 | 0 |
| 100 | 1.8 | 3.1 | 1 | 14 | 11 | 100 | 10 | 0.2 / n/a | 117 | 0.3 | 1.6 / 0.0 | 1.6 | 0 | 0 |
| 1,000 | 2.0 | 5.9 | 1 | 14 | 11 | 1,000 | 10 | 0.4 / n/a | 113 | 3.1 | 7.7 / 0.2 | 5.7 | 4 | 0 |
| 10,000 | 17.6 | 56.6 | 1 | 14 | 11 | 8,136 | 8 | 0.4 / n/a | 100 | 2.4 | 33.1 / 1.6 | 61.4 | 44 | 0 |
| 100,000 | 162 | 558 | 1 | 14 | 11 | 8,180 | 7 | 0.2 / n/a | 67 | 1.9 | 312 / 16.1 | 477 | 316 | 9 |

## Many unique 10 cm objects

| objects | generate ms | mesh + nodes ms | chunks | quads | nodes | bodies | draw calls | frame ms (cpu / gpu) | fps | 1 edit ms | save ms / MB | load ms | +RAM MB | +VRAM MB |
|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| 10 | 0.4 | 1.4 | 10 | 140 | 20 | 10 | 39 | 0.3 / n/a | 120 | 0.4 | 4.0 / 0.0 | 10.1 | 0 | 0 |
| 100 | 3.2 | 10.4 | 100 | 1,400 | 110 | 100 | 414 | 0.4 / n/a | 117 | 0.2 | 30.4 / 0.1 | 97.0 | 6 | 0 |
| 1,000 | 27.6 | 96.5 | 1,000 | 14,000 | 1,010 | 1,000 | 4,026 | 1.3 / n/a | 112 | 0.4 | 303 / 0.6 | 980 | 62 | 1 |
| 10,000 | 277 | 1,040 | 10,000 | 140,000 | 10,010 | 8,136 | 27,153 | 7.9 / n/a | 44 | 0.6 | 2,975 / 6.4 | 9,850 | 635 | 32 |
| 100,000 | skipped: next step projected at 141s |
