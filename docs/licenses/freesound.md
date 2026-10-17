# Freesound sounds: the licences we take

Sounds from [Freesound](https://freesound.org) come under the licence each one's maker chose.
The game takes only these (Jeff's rule: nothing non-commercial, nothing with a revenue cap
or a regional limit):

- **CC0 1.0** (public domain dedication): https://creativecommons.org/publicdomain/zero/1.0/legalcode
- **CC BY 4.0**: https://creativecommons.org/licenses/by/4.0/legalcode
- **CC BY 3.0**: https://creativecommons.org/licenses/by/3.0/legalcode

`tools/freesound.ps1` searches only these and checks each sound's licence again before it
keeps a copy; Freesound's "Attribution NonCommercial" and "Sampling+" are refused.

`art/audio/takes.json` records each Freesound take's maker, page and licence, and the
sound slot block of `THIRD_PARTY.md` credits every one (CC BY needs it; CC0 gets it too).
A take may be cut, trimmed, made mono and re-encoded from the original (CC BY allows
adaptations; the credit says it was cut from the named sound).

## The API's own terms (read 2026-10-17)

Separate from each sound's licence, the Freesound API has terms of its own:
https://freesound.org/help/tos_api/ (no date or version on the page). What bears on us:

- Section 1: a revocable licence to use the API "to retrieve Content necessary to facilitate
  permitted use of Services through your Application", to make "limited intermediate copies
  of Content only as necessary" (deleted when no longer needed) and to process Content "in
  accordance with the applicable Content license/s". "Do not make full copies of the database."
- Section 3: "Terms for commercial use of the API will be negotiated on a case by case basis
  with UPF, including limits regarding the volume of use of the Platform." Calls may be
  limited, and free users may be given new economic conditions.
- Section 4: no scraping, no excessive request volume, no commercialising Content in breach
  of its licence.

The terms don't say the API is for non-commercial use only. They also don't say a commercial
game's developers may use it freely: commercial use of the API is "negotiated case by case".
2026-10-17: Jeff authorized the app and sent the OAuth2 code after the API-terms question was
put to him with three options (A: ask UPF; B: download by hand from the website; C: treat
development-time use as covered). The same day he sent UPF the question through Freesound's
contact form. His decision, in his words: "proceed with API downloads until UPF says
otherwise". UPF's answer: **pending**. A no stops API downloads and switches to hand
downloads from the website, under each sound's own licence.

The tool is never part of the game. It fetches a few dozen sounds, paced under Freesound's
limit of 30 calls a minute, and keeps one copy of each original in the sound library. An
original no take uses is deleted.

Like the Sonniss takes, the files stay outside the repo (the sound library,
`N:\assets\sound\freesound` and `takes`) and go into the game through
`tools/sound_sync.ps1`.
