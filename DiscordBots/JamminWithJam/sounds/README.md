# Sounds

Drop the audio files `config.json` refers to here (mp3, ogg, wav — anything ffmpeg reads).
Nothing is shipped in this folder: pick your own clips and keep the filenames in step with
`file` in `config.json`, which in turn has to stay in step with the ids in the addon's
`Sounds.lua` catalogue. See the main README's "Keeping the two catalogues in step" section.

This folder (except this file) is gitignored, the same way the addon's own `dist/` is: audio
files are binary, guild-specific, and not something a `git diff` can usefully show anyone.
