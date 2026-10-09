# Perception eval: qwen3:14b

2026-10-08 21:09:02; 8 scene(s), 5 run(s) of each question per scene and mode; 480 answers.

## Accuracy

| | list | grid | both |
|---|---|---|---|
| all | 79% (127/160) | 55% (88/160) | 80% (128/160) |
| What's next to you? | 45% (18/40) | 68% (27/40) | 40% (16/40) |
| Where's the fire? | 85% (34/40) | 38% (15/40) | 100% (40/40) |
| Is the door open? | 88% (35/40) | 48% (19/40) | 88% (35/40) |
| Is anything near me? | 100% (40/40) | 68% (27/40) | 93% (37/40) |

## Latency and size

| | list | grid | both |
|---|---|---|---|
| average latency (voice) | 247 ms | 285 ms | 262 ms |
| over the game's 5 s voice timeout | 0 | 0 | 0 |
| errors | 0 | 0 | 0 |
| prompt tokens, voice (mean of scenes) | 572 | 759 | 824 |
| prompt tokens, stance (mean of scenes) | 254 | 441 | 506 |

## By scene

| | list | grid | both |
|---|---|---|---|
| fire_imp | 15/20 | 8/20 | 14/20 |
| crates | 20/20 | 9/20 | 18/20 |
| door_shut | 19/20 | 17/20 | 20/20 |
| door_open | 15/20 | 10/20 | 15/20 |
| ledge_sneak | 13/20 | 10/20 | 15/20 |
| door_north | 17/20 | 13/20 | 17/20 |
| past_the_door | 15/20 | 16/20 | 16/20 |
| water_cart | 13/20 | 5/20 | 13/20 |

## What the answers show (round 2)

Run on 2026-10-08 against qwen3:14b on the box (RTX 5080), from the dev
machine through an ssh tunnel, with the voice's own prompt and request
body, after two changes from round 1: spoken to, she always answers in
words (decision 120), and the list holds only monsters, what Jeff asked
about and things within 2 paces (decision 121).

- **list 79%, both 80%, grid 55%.** List and both are within five
  points, so the list stays the default and both a setting (decision
  122): the list's voice ask is about 250 tokens shorter.
- **The door question works now**: 88% for list and both, against 0-13%
  in round 1, when 64 of 72 answers were "...". Silences fell from 68 of
  288 answers to 15 of 480.
- **both** still places the fire best (100% against the list's 85%).
- **list** is still weakest on "What's next to you?" (45%): the model
  reads out the monsters a few paces off as well. The grid, where the
  cells beside her can be read off, does best there (68%).
- **grid** alone gets directions wrong and invents fire it cannot see,
  as in round 1.
- Latency is the same in every mode (about 250-285 ms a line; the live
  server shared the box's Ollama during the run).

## Round 1, for comparison

3 runs a cell, 288 answers, before decisions 120 and 121: list 52%,
grid 45%, both 61%; the door question 0% / 4% / 13%, nearly all silence;
voice prompt tokens 552 / 728 / 804.
