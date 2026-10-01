# pw2401 test fixtures

This directory contains tiny, deterministic media inputs used by the declarative
PowerShell example tests. They are copied into an isolated case before a test runs
and must never be modified in place.

The media files were generated with FFmpeg from synthetic color/test sources:

- `media/short-video.mkv`: one-second 320x240 FFV1 video.
- `media/masonry/*.png`: portrait, wide, and square color images.
- `media/vmaf/`: one-second source and lossy comparison videos.
- `media/subtitles/two-streams.mkv`: short video with Chinese and English SRT streams.

The complete fixture set is intentionally small so it can be committed with the
test definitions.
