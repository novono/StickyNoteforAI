# PaperMemory 1.3 architecture

The app keeps the existing version-1 data format and MCP tool contract. Files are reorganized around the responsibilities that caused synchronization and window-lifecycle bugs.

| Boundary | Responsibility |
| --- | --- |
| `Sources/Domain/Note.swift` | Codable note/attachment model and shared identity/version |
| `Sources/Storage/Store.swift` | Injectable storage root, atomic file transactions, backups and revision checks |
| `Sources/Storage/AttachmentStorage.swift` | Validated image imports and content-addressed image files |
| `Sources/Storage/NoteDocuments.swift` | RTF/RTFD loading, immutable document files, draft conflict checks and inline image preservation |
| `Sources/Integration/NoteService.swift` | Shared validated commands for CLI/MCP, including atomic categorization |
| `Sources/Integration/MCP.swift` / `Sources/main.swift` | Transport and application entry points |
| `Sources/App/WindowAnimation.swift` | Injectable native frame transitions; controlled completion in state tests |
| `Sources/App/NoteWindowPolicy.swift` | Desktop/floating levels and Spaces/window-visibility rules |
| `Sources/App/App.swift` | Application lifecycle, panel reconciliation, scoped notifications and command coordination |
| `Sources/UI/PaperView.swift` / `Sources/UI/DetailController.swift` | Compact and expanded editing in the same window |
| `Sources/UI/PaperSurface.swift` / `Sources/Paper/PaperTexture.swift` / `Sources/Paper/PaperAppearance.swift` | Material rendering with a stable per-note seed and bounded texture cache |
| `Sources/Paper/PaperMovement.swift` | Recent pointer velocity, analytic drag trajectory, multi-screen landing and cancellable window coasting |
| `Sources/Paper/PaperAge.swift` | Bounded age curve from immutable creation time, slight stock warmth and edge-only patina |
| `Sources/Paper/PaperMotion.swift` | Temporary animation surface, interruption and editor/frame restoration |
| `Sources/UI/PaperTypography.swift` / `Sources/UI/PaperTextView.swift` / `Sources/App/LibraryController.swift` | Handwriting, text interaction and library presentation |

## Lifecycle invariants

- Desktop panels use level -1: above wallpaper/Finder desktop surfaces, below normal application windows. They are stationary across desktop reveal, join Spaces, and do not hide on deactivation. Expanded editing temporarily uses the floating level; collapse reapplies the persisted mode.
- A note has one panel. Expansion does not spawn another window. Animation suppresses intermediate geometry persistence and restores the retained editor/frame.
- Pointer movement owns the actual panel frame. Release velocity uses a short weighted sampling window; viscous resistance gives continuous deceleration, with greater resistance near display boundaries. Slow or paused releases do not coast. Grabbing, editing, hiding, deletion and termination cancel movement before changing state. Intermediate frames are never persisted; final geometry also updates the expanded editor’s collapse anchor. Reduce Motion disables coasting.
- Reconciliation is guarded against re-entry. Deletion flushes drafts before tearing the paper. Collapse completion checks controller/panel ownership before restoring anything, so an obsolete callback cannot resurrect a removed note.
- Clean expanded editors refresh when AI changes the document. Unsaved edits stay in place; saves compare their base content against storage and merge unrelated metadata only.
- GUI and AI attachment operations append to the existing rich document. Text styles and inline images survive.
- File writes remain locked, atomic and revision-checked. Rich documents use content hashes, so identical autosaves reuse a file. No migration or pruning of existing notes is performed.
- Notifications carry the storage root. Test stores cannot send detail-open requests into the user's store. Legacy clients remain readable and the polling fallback remains available.
- Background AI writes no longer reopen the app unnecessarily. Completing the last note does not create an empty replacement.
- Paper age derives from `createdAt`, independent of content revisions and window movement. The first six hours remain fresh; patina reaches its ceiling at thirty days. Edge wear stays outside the text insets, ink and images are unchanged. A throttled minute refresh invalidates only the paper background without file writes. Animation snapshots use the aged stock color, and the deterministic texture cache is shared across ages.

## Verification

Run `./build.sh` followed by `./verify.sh`. The latter builds native regression executables against all production sources except `Sources/main.swift`, uses isolated temporary stores, runs the CLI/MCP integration suite, and verifies the code signature.

Coverage includes window-server ordering and visibility, hide/show, expand/collapse, live AI refresh, local draft merging, removal during collapse, blank-note management, rich-text image append, conflict prevention, concurrent writes, atomic organize rollback, image copying, malformed storage preservation, animation cleanup, pointer velocity and speed limits, exponential slowdown, multi-display boundaries, native window coasting, catch interruption, settled position persistence and expanded collapse anchors. `scripts/render-motion.swift` samples the production material/motion renderer for visual inspection.

Source groups correspond to application coordination (`App`), shared data (`Domain`), persistence (`Storage`), transport and commands (`Integration`), editing (`UI`) and paper rendering/movement (`Paper`). Regression programs live in `Tests`; developer utilities live in `scripts`. Build products and isolated test stores remain under the ignored `build/` directory.

Window state and drag integration tests use real AppKit panels with a controlled frame animator. They explicitly deliver transition completions, including late callbacks after deletion, instead of depending on compositor callback timing in a command-line test process. Production uses `AppKitWindowAnimator` with the existing timing and Reduce Motion behavior. Paper arrival/tear rendering and inertia still run through the real animation/movement code; visual expansion timing is checked in the running app.
