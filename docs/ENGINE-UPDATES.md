# Engine version updates

Zero-K's server chooses the required engine version. The macOS build must use
that actual upstream release, not report a newer simulation as an older one.
The current baseline is Recoil `2026.07.04` (`de6936123`).

Keep a version-specific branch in the Recoil fork, such as
`macos/2026.07.04`. The first port commit applies the upstream macOS graphics
integration to that baseline plus the trackpad, Retina and presentation fixes.
Subsequent commits handle application-bundle resource lookup and Dock behavior.

When Zero-K changes its required version:

1. Fetch that release into the Recoil fork and create a new `macos/<version>`
   branch. Merge or reapply the macOS commits, resolving changes in the
   renderer, Lua API, input and platform code deliberately.
2. Inspect the new engine's pinned CircuitAI/AngelScript revision. The central
   `patches/circuitai-apple-arm64.patch` is specific to the current submodule;
   it must apply cleanly or be replaced with the appropriate port. Do not
   force a failed patch onto unrelated source.
3. Build the engine, C AI interface and CircuitAI together with the same
   compiler and floating-point settings. Preserve the correct sync version.
4. Run the bundle audit, a native skirmish with AI, all display modes and the
   trackpad checks. Test a multiplayer match against the corresponding
   Windows/Linux release; a reported version alone does not establish sync.
5. Commit the validated fork changes and update `sources.lock.json` to the
   exact new commit and engine version. Build and test a fresh `.app` before
   distributing it.

Chobby and the helper are pinned independently. A central commit records the
compatible combination, plus the exact Steamworks, Mesa, libclc, SDK and .NET
runtime versions. An app update replaces static resources as a unit and keeps
Application Support data intact.

Source preparation never resets an existing checkout. Developers can edit a
fork under `external/` and rebuild their tweaks. Release builds should start
from clean checkouts at the lock-file revisions; the build manifest records
whether the source trees were modified.
