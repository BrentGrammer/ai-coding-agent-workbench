# Windows Support Plan

## Current state

The Linux sandbox runtime is portable, but the host launchers use Bash, Unix paths, macOS application paths, and `open -a Docker`. macOS is currently the supported and tested host. Linux and WSL2 are unverified. Native Windows is not supported.

## Goal

Run the Herdr and Hunk workbench with Claude, Codex, and OpenCode from native Windows while preserving Docker Sandbox isolation, network policies, credential handling, and reusable agent logins.

## Approach

1. Move host orchestration from Bash into a cross-platform Node.js CLI.
2. Keep setup commands that run inside the Linux sandbox as Bash.
3. Add Windows project-path handling and Docker Desktop startup.
4. Support Windows Terminal with a configurable current-terminal fallback.
5. Replace the Bash command wrappers with cross-platform entry points.
6. Validate sandbox creation, reuse, authentication, Herdr panes, Hunk, clipboard behavior, file edits, network restrictions, and clean shutdown.

## Delivery order

1. Support the main Herdr workflow with Claude, Codex, and OpenCode.
2. Add the remaining local agent launchers.
3. Evaluate WSL2 and Linux separately and document verified behavior.

## Estimated effort

- WSL2 investigation and basic support: a few hours.
- Native Windows for Herdr and the three primary agents: one to two focused days.
- Native Windows for every local launcher: two to four days including Windows testing.

A Windows machine is required for final verification.
