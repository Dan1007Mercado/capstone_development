# P15.6 physical replay fixture

`published_manifest.json` was read from the connected Infinix X6711's existing
published-artifact repository. Its stored artifact SHA-256 is verified by the
experiment before use. No layout is regenerated.
`published_template.pdf` was recovered from the same repository and its stored
PDF SHA-256 verified. This is the base template PDF, not the exact packet print job.

The phone's packet repository maps the printed packet IDs to this exact template:

| Printed packet | Photos | Template/version |
|---|---|---|
| P034-2982 | `all_marked.jpg`, `tilted_allmarked_fullmarked.jpg` | `tmpl-87811039040f1a9e6600a2dfff09bfeb`, v1 |
| P035-A333 | `mixstroke_mark.jpg`, `Tilted_mix_strokes.jpg` | same |
| P036-1CE4 | `unmarked.jpg`, `blank_tilted.jpg` | same |

`expected_answers.json` records the user's Q1–Q11 keys. Pairing the flat/tilted
photos uses their printed packet identities, not the earlier 10-question archive.
The 22 MB of original JPEGs remain in the user-supplied `images_samples` directory;
they are not duplicated into this fixture or silently added to Git.

See `docs/development/p15.6-root-cause-investigation.md` for hashes, native replay
results, controls, limitations, and reproduction commands. These files are
experimental evidence, not a calibrated production accuracy guarantee.
