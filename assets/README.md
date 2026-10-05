# App icon

`keeb-clock-icon.png` is the high-resolution mint clock-keycap master. It has a
navy rounded-square tile and transparent corners, with no manufacturer branding.

Run `sh scripts/render-icon.sh` from the project root to generate all macOS icon
sizes. The script uses macOS's `sips` and Python 3 to remove image metadata.
The checked-in images are ready for ordinary app builds.
