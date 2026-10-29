# Engine version updates

Zero-K's server chooses the required engine version. The macOS build must use
that actual upstream release, not report a newer simulation as an older one.
The current baseline is Recoil tag `2026.07.04`, which resolves to
`de69361239d8c8b1012dba3f5aa3122954ea4da3`.

The port lives in the Recoil fork's `macos/2026.07.04` branch. All engine changes
are ordinary commits there. Lobby changes live in the Chobby fork's `macos-port`
branch. CircuitAI's Apple ARM64/AngelScript changes live in its own fork, and the
engine commits the fork URL and exact submodule revision. Source preparation
does not apply engine, lobby or AI patches.

## Merge the next required release tag

When Zero-K changes its required version, fetch upstream tags and merge the
new required tag into the port's history. Keep the previous version branch for
rebuilding older game-compatible releases. For example, after setting
`ENGINE_RELEASE` to the new version required by Zero-K:

```sh
cd external/recoil
: "${ENGINE_RELEASE:?Set ENGINE_RELEASE to the release required by Zero-K}"
git fetch upstream --tags
git switch macos/2026.07.04
git switch -c "macos/$ENGINE_RELEASE"
git merge --no-ff "refs/tags/$ENGINE_RELEASE"
```

Resolve renderer, Lua, input, platform, build-system and submodule conflicts
in the source files. Preserve the actual new upstream simulation code. Do not
carry the old engine version string forward just to bypass compatibility checks.
If the required release has no upstream tag, establish its exact upstream commit
before merging; do not substitute whichever upstream branch happens to be latest.

Inspect the new tag's CircuitAI gitlink and AngelScript version. Merge the newly
required AI revision into the CircuitAI fork, resolve its ARM64 changes, and
push that commit before updating the engine's submodule pointer. Keep the
CircuitAI fork URL in `.gitmodules`; the unrelated BARb submodule is unchanged.
Upstream fixes may make some port code unnecessary, so review the merge rather
than blindly retaining every old change.

Build the engine, C AI interface and CircuitAI together using the same compiler
and floating-point settings. Run the bundle audit, a native skirmish with AI,
all display modes and trackpad checks. Test a multiplayer match against the
corresponding Windows/Linux release; a reported version alone does not establish
synchronization.

Commit and push the validated fork branch, then update `sources.lock.json`:

- `revision`: the exact new fork commit containing the merge and port fixes.
- `branch`: the maintained `macos/<version>` branch, for developer orientation.
- `engine_version`: the actual required engine release/sync version.
- `upstream_tag` and `upstream_base`: the merged tag and its resolved commit.

The build checks out `revision`, not a moving branch or tag. Retaining the
resolved upstream commit also records the baseline if a tag later changes.
Reconfigure/rebuild and test a fresh `.app` before distributing it.

## Source ownership and reproducibility

Chobby and the helper are pinned independently. A central commit records the
compatible fork commits, plus the exact Steamworks, Mesa, libclc, SDK and .NET
runtime versions. An app update replaces static resources as a unit and keeps
Application Support data intact.

Only Mesa GPU sharing and create-dmg Finder compatibility remain as third-party
patches in this repository. They modify projects outside the engine/lobby forks.

Source preparation never resets an existing checkout. Developers can edit a
fork under `external/` and rebuild their tweaks. Release checks require clean
checkouts at the lock-file revisions and clean, initialized submodules at their
committed gitlinks. Commit/push source changes in the owning fork before changing
the central release pins.
