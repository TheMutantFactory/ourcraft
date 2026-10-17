# Ourcraft stress test

- Date: 2026-10-17 13:21:30
- Godot 4.7-stable (official), macOS, Apple M1 Pro (Apple7), 8 cores
- Render size 2720x1710, vsync off, native extension on
- Minimum block 1 cm. Frame times are averages over 120 frames with everything in view.

## Carved 2 m block (1 cm cells, random cuts of 1–25 cm)

| cuts | generate ms | mesh + nodes ms | chunks | quads | nodes | regions | bodies | draw calls | frame ms (cpu / gpu) | fps | 1 edit ms | save ms / MB | load ms | +RAM MB | +VRAM MB |
|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| 10 | 6.9 | 17.8 | 222 | 340 | 234 | 1 | 222 | 973 | 0.5 / n/a | 122 | 1.2 | 33.5 / 0.1 | 24.8 | 15 | 0 |
| 100 | 8.3 | 19.0 | 278 | 1,091 | 290 | 1 | 278 | 1,207 | 0.6 / n/a | 121 | 1.0 | 32.8 / 0.1 | 22.6 | 15 | 0 |
| 1,000 | 24.5 | 41.5 | 382 | 8,244 | 394 | 1 | 382 | 1,680 | 0.7 / n/a | 120 | 1.7 | 43.4 / 0.2 | 22.6 | 21 | 0 |
| 10,000 | 197 | 117 | 492 | 47,356 | 504 | 1 | 492 | 2,180 | 0.8 / n/a | 116 | 0.2 | 64.3 / 0.3 | 30.5 | 39 | 5 |
| 100,000 | 1,806 | 134 | 512 | 60,238 | 524 | 1 | 512 | 2,276 | 0.8 / n/a | 114 | 2.8 | 70.1 / 0.3 | 30.0 | 44 | 7 |

## Random noise cube (50% filled 1 cm cells; worst case for meshing)

| cells | generate ms | mesh + nodes ms | chunks | quads | nodes | regions | bodies | draw calls | frame ms (cpu / gpu) | fps | 1 edit ms | save ms / MB | load ms | +RAM MB | +VRAM MB |
|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| 10,000 | 11.3 | 18.5 | 1 | 15,933 | 13 | 1 | 1 | 8 | 0.2 / n/a | 123 | 20.9 | 1.8 / 0.0 | 0.4 | 5 | 1 |
| 100,000 | 11.6 | 165 | 8 | 141,579 | 20 | 1 | 8 | 29 | 0.3 / n/a | 112 | 50.1 | 9.8 / 0.1 | 1.8 | 47 | 18 |
| 1,000,000 | 15.2 | 1,800 | 64 | 1,435,302 | 76 | 1 | 64 | 238 | 0.3 / n/a | 61 | 70.7 | 97.8 / 0.6 | 13.7 | 484 | 171 |
| 10,000,000 | skipped: next step projected at 14,353,020 quads |

## Many instances of one 10 cm object

| instances | generate ms | mesh + nodes ms | chunks | quads | nodes | regions | bodies | draw calls | frame ms (cpu / gpu) | fps | 1 edit ms | save ms / MB | load ms | +RAM MB | +VRAM MB |
|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| 10 | 0.1 | 0.6 | 1 | 14 | 13 | 1 | 10 | 9 | 0.3 / n/a | 126 | 0.4 | 0.9 / 0.0 | 0.4 | 0 | 0 |
| 100 | 0.4 | 1.1 | 1 | 14 | 13 | 1 | 100 | 10 | 0.3 / n/a | 122 | 0.4 | 1.6 / 0.0 | 0.8 | 0 | 0 |
| 1,000 | 2.0 | 7.2 | 1 | 14 | 13 | 1 | 1,000 | 10 | 0.4 / n/a | 116 | 0.8 | 4.3 / 0.2 | 4.7 | 4 | 0 |
| 10,000 | 17.0 | 70.8 | 1 | 14 | 13 | 1 | 8,136 | 8 | 0.3 / n/a | 103 | 5.5 | 33.3 / 1.6 | 44.7 | 44 | 0 |
| 100,000 | 166 | 732 | 1 | 14 | 13 | 1 | 8,180 | 7 | 0.2 / n/a | 68 | 1.7 | 305 / 16.1 | 467 | 316 | 9 |

## Many unique 10 cm objects

| objects | generate ms | mesh + nodes ms | chunks | quads | nodes | regions | bodies | draw calls | frame ms (cpu / gpu) | fps | 1 edit ms | save ms / MB | load ms | +RAM MB | +VRAM MB |
|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| 10 | 0.5 | 1.3 | 10 | 140 | 13 | 1 | 10 | 13 | 0.2 / n/a | 125 | 0.3 | 2.8 / 0.0 | 1.6 | 0 | 0 |
| 100 | 2.9 | 10.2 | 100 | 1,400 | 13 | 1 | 100 | 15 | 0.3 / n/a | 122 | 0.5 | 24.0 / 0.1 | 14.6 | 5 | 0 |
| 1,000 | 27.3 | 97.6 | 1,000 | 14,000 | 13 | 1 | 1,000 | 13 | 0.4 / n/a | 117 | 0.9 | 196 / 0.6 | 144 | 54 | 3 |
| 10,000 | 279 | 1,111 | 10,000 | 140,000 | 21 | 9 | 8,136 | 34 | 0.3 / n/a | 101 | 0.9 | 1,958 / 6.4 | 1,527 | 543 | 34 |
| 100,000 | skipped: next step projected at 5 GB RAM |
