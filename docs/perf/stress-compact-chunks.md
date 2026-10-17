# Ourcraft stress test

- Date: 2026-10-17 13:30:40
- Godot 4.7-stable (official), macOS, Apple M1 Pro (Apple7), 8 cores
- Render size 2720x1710, vsync off, native extension on
- Minimum block 1 cm. Frame times are averages over 120 frames with everything in view.

## Carved 2 m block (1 cm cells, random cuts of 1–25 cm)

| cuts | generate ms | mesh + nodes ms | chunks | quads | nodes | regions | bodies | draw calls | frame ms (cpu / gpu) | fps | 1 edit ms | save ms / MB | load ms | +RAM MB | +VRAM MB |
|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| 10 | 8.2 | 39.3 | 343 | 340 | 234 | 1 | 222 | 973 | 0.6 / n/a | 123 | 1.8 | 2.5 / 0.1 | 7.3 | 4 | 0 |
| 100 | 14.1 | 41.3 | 343 | 1,091 | 290 | 1 | 278 | 1,207 | 0.6 / n/a | 123 | 1.6 | 2.2 / 0.1 | 7.5 | 4 | 0 |
| 1,000 | 64.9 | 56.5 | 382 | 8,244 | 394 | 1 | 382 | 1,680 | 0.6 / n/a | 122 | 2.1 | 3.7 / 0.2 | 8.7 | 9 | 0 |
| 10,000 | 530 | 110 | 492 | 47,356 | 504 | 1 | 492 | 2,180 | 0.7 / n/a | 116 | 0.3 | 5.3 / 0.3 | 11.5 | 23 | 5 |
| 100,000 | 4,739 | 130 | 512 | 60,238 | 524 | 1 | 512 | 2,276 | 0.8 / n/a | 114 | 3.2 | 5.6 / 0.4 | 12.1 | 28 | 7 |

## Random noise cube (50% filled 1 cm cells; worst case for meshing)

| cells | generate ms | mesh + nodes ms | chunks | quads | nodes | regions | bodies | draw calls | frame ms (cpu / gpu) | fps | 1 edit ms | save ms / MB | load ms | +RAM MB | +VRAM MB |
|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| 10,000 | 11.7 | 3.7 | 1 | 15,933 | 13 | 1 | 1 | 8 | 0.3 / n/a | 123 | 17.6 | 0.9 / 0.0 | 0.3 | 5 | 1 |
| 100,000 | 14.3 | 32.1 | 8 | 141,579 | 20 | 1 | 8 | 29 | 0.3 / n/a | 112 | 52.2 | 1.5 / 0.1 | 1.2 | 47 | 18 |
| 1,000,000 | 28.8 | 283 | 64 | 1,435,302 | 76 | 1 | 64 | 238 | 0.5 / n/a | 61 | 72.6 | 5.5 / 0.6 | 9.8 | 484 | 171 |
| 10,000,000 | skipped: next step projected at 14,353,020 quads |

## Many instances of one 10 cm object

| instances | generate ms | mesh + nodes ms | chunks | quads | nodes | regions | bodies | draw calls | frame ms (cpu / gpu) | fps | 1 edit ms | save ms / MB | load ms | +RAM MB | +VRAM MB |
|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| 10 | 0.3 | 0.6 | 1 | 14 | 13 | 1 | 10 | 9 | 0.2 / n/a | 125 | 0.4 | 1.0 / 0.0 | 0.3 | 0 | 0 |
| 100 | 1.3 | 4.2 | 1 | 14 | 13 | 1 | 100 | 10 | 0.3 / n/a | 122 | 0.5 | 1.1 / 0.0 | 0.7 | 0 | 0 |
| 1,000 | 6.0 | 7.7 | 1 | 14 | 13 | 1 | 1,000 | 10 | 0.4 / n/a | 118 | 0.7 | 3.9 / 0.2 | 4.5 | 4 | 0 |
| 10,000 | 16.8 | 69.7 | 1 | 14 | 13 | 1 | 8,136 | 8 | 0.2 / n/a | 103 | 1.8 | 30.0 / 1.6 | 55.7 | 45 | 0 |
| 100,000 | 162 | 720 | 1 | 14 | 13 | 1 | 8,180 | 7 | 0.2 / n/a | 68 | 3.0 | 320 / 16.1 | 478 | 318 | 9 |

## Many unique 10 cm objects

| objects | generate ms | mesh + nodes ms | chunks | quads | nodes | regions | bodies | draw calls | frame ms (cpu / gpu) | fps | 1 edit ms | save ms / MB | load ms | +RAM MB | +VRAM MB |
|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| 10 | 0.9 | 1.3 | 10 | 140 | 13 | 1 | 10 | 13 | 0.3 / n/a | 125 | 1.0 | 5.1 / 0.0 | 1.1 | 0 | 0 |
| 100 | 5.2 | 9.6 | 100 | 1,400 | 13 | 1 | 100 | 15 | 0.3 / n/a | 122 | 0.5 | 12.0 / 0.1 | 8.8 | 1 | 0 |
| 1,000 | 49.2 | 87.0 | 1,000 | 14,000 | 13 | 1 | 1,000 | 13 | 0.2 / n/a | 117 | 0.4 | 117 / 0.7 | 96.4 | 16 | 1 |
| 10,000 | 481 | 866 | 10,000 | 140,000 | 21 | 9 | 8,136 | 34 | 0.3 / n/a | 101 | 0.6 | 1,207 / 6.6 | 929 | 147 | 16 |
| 100,000 | 4,955 | 8,894 | 100,000 | 1,400,000 | 76 | 64 | 8,180 | 77 | 0.2 / n/a | 65 | 0.8 | 14,160 / 65.8 | 22,522 | 932 | 169 |
