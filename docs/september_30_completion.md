# September 30 completion work

Standing delivery: signed Android bundle newer than 1.1.1+39, release notes,
GitHub sync, deployed backend and website. Do not execute the one-time reset.

## Requested work

- [x] Reel likes/comments/saves, durable counts and permission tests.
- [x] Loop, audible mobile playback, tap pause, transient double-tap heart,
      long-press optional auto-scroll, lifecycle/controller safety.
- [x] Reels on public profiles, with visibility/block checks.
- [x] Rich in-app shares for reels/feed posts, image messages; recipient access
      must be rechecked rather than storing private signed playback URLs.
- [x] Actual external image/video/text shares; exported video has Grace Connect
      watermark at bottom-left; private R2 remains private.
- [x] Website share-background catalogue upload/edit/enable/remove.
- [x] Developer operations/readiness tools and payment-to-entitlement audit.
- [x] One-time reset UI/server job preserving only requesting developer account;
      durable consumed state, resumable cleanup, no production activation here.
- [ ] Final signed AAB verification and delivery (checks and notes prepared).

## Confirmed starting defects

Current repositories are app 639c90c and landing 2305e01. No tracked local edits.
Attachment is an older Claude transcript, ending before the previous audit.
Reel writes omit identity columns that have no defaults. Authenticated users
also lack permission to call the private RLS visibility function. No engagement
counter triggers exist. Player explicitly disables looping. Heart animation
starts with opacity 1. Share sends only caption text, no file or content link.

Website already has finance, checkout and subscription management pages. Verify
live payment readiness; never claim real billing works merely from mock tests.
