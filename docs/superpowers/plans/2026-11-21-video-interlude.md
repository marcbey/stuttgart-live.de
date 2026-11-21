# Video Interlude Implementation Plan

**Goal:** Add the approved two-second silent brand transition between homepage clips and open localhost:3000.

**Architecture:** Keep playlist selection in video-sound. A cancellable interlude timer runs only while playback is eligible and unpaused. A shared overlay uses the homepage’s existing stacked Oswald wordmark and dark background, without a caption as requested in the latest design revision. CSS fades the panel and gently lifts the logo; reduced motion disables animation.

**Tech Stack:** Stimulus, ERB, frontend CSS, node:test.

## Steps

- [x] Add failing timer tests in `test/javascript/video_sound_controller_test.mjs`: wait 2 seconds, preserve mute, pause/resume, suspend offscreen, cancel on disconnect, skip for single clips.
- [x] Extend `video_sound_controller.js` with interlude lifecycle; keep legacy players unchanged and disable the event link during the brand panel.
- [x] Add overlay to `_video_playlist_card.html.erb` and responsive styles to `frontend.tailwind.css` using the existing locally served Oswald wordmark.
- [x] Update README, run JavaScript tests and local CI, inspect mobile/desktop presentation and open localhost:3000.

Implementation stays in the current checkout for the local preview. Kathi subsequently requested publishing a PR staging preview. Brakeman is updated to 8.1.1 to satisfy the required latest-version check before CI and push.

## Verification

The local design CI passed 1,924 Rails tests (12,281 assertions), RuboCop, dependency audits and seeds. Initially the Brakeman wrapper rejected installed 8.1.0 because 8.1.1 was available; an independent scan with 8.1.0 completed with zero warnings. The updated 8.1.1 scanner then identified CVE-2026-132825 in Ruby 4.0.2. The staging follow-up updates all runtime pins to the officially fixed Ruby 4.0.10 and requires full CI again. The final JavaScript suite covers timer suspension, pause, clip selection and persistent media-error recovery. Browser checks verified the real shared player in 112px, 230px and 380px cards, including interlude display, pause and resume. The temporary two-clip test page was removed; localhost:3000 remains running and open.
