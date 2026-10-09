# Perception eval: qwen3:14b

2026-10-08 20:50:13; 8 scene(s), 3 run(s) of each question per scene and mode; 288 answers.

## Accuracy

| | list | grid | both |
|---|---|---|---|
| all | 52% (50/96) | 45% (43/96) | 61% (59/96) |
| What's next to you? | 38% (9/24) | 71% (17/24) | 46% (11/24) |
| Where's the fire? | 71% (17/24) | 46% (11/24) | 92% (22/24) |
| Is the door open? | 0% (0/24) | 4% (1/24) | 13% (3/24) |
| Is anything near me? | 100% (24/24) | 58% (14/24) | 96% (23/24) |

## Latency and size

| | list | grid | both |
|---|---|---|---|
| average latency (voice) | 192 ms | 188 ms | 197 ms |
| over the game's 5 s voice timeout | 0 | 0 | 0 |
| errors | 0 | 0 | 0 |
| prompt tokens, voice (mean of scenes) | 552 | 728 | 804 |
| prompt tokens, stance (mean of scenes) | 265 | 441 | 517 |

## By scene

| | list | grid | both |
|---|---|---|---|
| fire_imp | 9/12 | 5/12 | 9/12 |
| crates | 9/12 | 6/12 | 8/12 |
| door_shut | 8/12 | 9/12 | 9/12 |
| door_open | 5/12 | 5/12 | 6/12 |
| ledge_sneak | 5/12 | 2/12 | 6/12 |
| door_north | 4/12 | 4/12 | 8/12 |
| past_the_door | 6/12 | 8/12 | 9/12 |
| water_cart | 4/12 | 4/12 | 4/12 |

## What the answers show

Run on 2026-10-08 against qwen3:14b on the box (RTX 5080), from the dev
machine through an ssh tunnel, with the voice's own prompt and request
body. Every answer is in `build/perception_eval.jsonl` when re-run.

- **both** is the most accurate overall (61%) and the only mode good at
  "Where's the fire?" (92%): the map plus the list's paces and bearings
  together place it.
- **list** is best at "Is anything near me?" (100%), since "next to
  Jeff" is written out for it, but worst at "What's next to you?" (38%):
  the model reads the question as "what's around you" and recites the
  list, things two to four paces off included.
- **grid** alone is weakest (45%). It gets compass directions wrong (fire
  two paces north answered as "to the south"), misses a monster beside
  Jeff ("Nothing near you" with a sneak there), and when no fire is in
  sight invents one "to the north, past the wall". It is best at
  "What's next to you?" (71%): the cells beside her are easy to read off
  the map.
- **"Is the door open?" measures nothing yet**: in 64 of 72 asks the
  model answered "..." (silence), whatever the mode. That comes from the
  voice prompt, not from perception: removing VOICE_RULES' "Only if there
  is truly nothing worth saying, answer with just: ..." or rephrasing the
  question ("Is the door ahead open or shut?") gets "The door is closed."
  at once. Of the few non-silent answers: list 0/3, grid 1/1, both 3/4.
- With no fire in sight, list mode still says "The fire is behind us, to
  the left." in some scenes: the world primer mentions fires, and an
  empty list does not say "no fire".
- Latency is the same in every mode (about 190 ms per voice line; prefill
  is cheap on this card). The cost is prompt size: the grid adds about
  180 tokens to every ask, both about 250, to the voice's and the
  stance's alike.
