# Homepage Video Playlist Implementation Plan

> **For agentic workers:** Use superpowers:subagent-driven-development for the independent playback component; integrate views and verify in the current workspace.

**Goal:** Shuffle homepage clips without immediate repetition and display a portrait mobile playlist before the highlight events.

**Architecture:** Extend video-sound with playlist metadata and targets while retaining its visibility, pause and reduced-motion logic. Rails helpers build entries from preloaded event attachments and the current fallback settings. A shared card partial renders the player for desktop portrait/landscape and mobile portrait placements.

**Tech Stack:** Rails ERB, Stimulus, frontend Tailwind CSS, node:test, Minitest.

- [x] Playback: add failing node:test cases for complete rounds, boundary repeats, ended transitions, metadata updates and user pause. Run `node --test test/javascript/video_sound_controller_test.mjs`, implement playlist handling, rerun.
- [x] Rendering: add Rails coverage for mobile placement and exclusion of landscape attachments. Build entries with `src`, `poster`, `href`, `label`, `title`, `subtitle`, `date`, `location`, `overlay`, `adminHref`, `orientation`. Render shared player with optional media restriction. Preserve existing fallback precedence and desktop positions; put mobile player first in the row and use `object-fit: contain` with stable height.
- [x] Integration: update README behavior, run affected Ruby files through `mise exec -- bundle exec rubocop`, run targeted Rails tests and `LOCAL_DESIGN_CHECKS=1 mise exec -- bundle exec bin/ci`. Review all changes for scope and compatibility.
- [x] Browser: connect existing localhost:3000, rebuild assets if needed, inspect mobile widths 375/414 and tablet/desktop 768/1024/1440, verify next clip and scroll-out unloading. Leave localhost open for Kathi.

Work remains in the existing design checkout so localhost previews all current changes. Kathi subsequently requested committing all pending changes and publishing a staging preview. Integrate the current main branch, preserve its global video selection and security updates, run CI, then use the documented PR staging workflow.

## Verification result

Initial design checks passed 48 JavaScript tests and 1,892 Rails tests with Bullet; the initial dependency audit was blocked by older dependencies. Integration with current main retains its security updates, and the dependency audit now passes. Full CI is required again before push. Frontend build and browser checks passed at 375, 414, 768, 1024 and 1440 pixels; mobile is portrait-only with 28px visible controls and larger touch areas. Browser verified pause, source removal after horizontal scrolling, no page overflow, and restored landscape aspect ratio. Integration review confirmed that both playlists include all eligible upcoming published events regardless of displayed lanes.
