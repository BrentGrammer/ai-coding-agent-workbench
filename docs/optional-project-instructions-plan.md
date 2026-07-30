# Optional Project Instructions Plan

## Confirmed Behavior

The direct local start commands already work from a parent folder that contains
several repositories. The sandbox mounts the parent folder and gives the agent
access to all folders below it.

No multi-project code change is necessary.

## Required Work

1. Fix sandbox name collisions.
   - Build each sandbox name from the readable folder name and a short hash of
     the full canonical workspace path.
   - Make `/workspace/client-a/app` and `/workspace/client-b/app` use different
     sandbox names.
   - Use the parent folder path when the parent folder is the selected
     workspace.
   - Do not reuse an old sandbox when its workspace path cannot be confirmed.
   - State that the first launch with the new name can require a new agent
     login.
2. Create portable `AGENTS.md` and `CLAUDE.md` templates for use in other
   projects.
3. Make `CLAUDE.md` import `AGENTS.md` so Claude receives the shared rules.
4. Copy only `AGENTS.md` and `CLAUDE.md` through the automatic prompt.
   - Do not include or reference `readonly/CONVENTIONS.md` in the portable
     templates.
   - Do not include or reference `readonly/REACT_INSTRUCTIONS.md` in the
     portable templates.
   - Keep both files in the workbench as optional convenience files.
5. Add one shared instruction-copy function for the applicable local start
   commands.
6. Before a sandbox starts, check which instruction files are missing from the
   selected workspace.
7. Do not show a prompt when both files already exist.
8. Never replace or change an existing project instruction file.
9. When one or both files are missing, show these choices:
   1. Copy the missing files once.
   2. Copy the missing files and remember this choice.
   3. Do not copy the files this time.
   4. Do not copy the files and remember this choice.
10. Store remembered choices under
   `~/.local/state/agent-workbench/instruction-copy/`.
11. Save one independent choice for each full canonical workspace path.
    - Do not key choices by the folder name.
    - Make `/workspace/client-a/app` and `/workspace/client-b/app` keep separate
      choices.
    - Treat a moved or renamed workspace as a new workspace.
12. Provide a start-command option that asks again and replaces the remembered
    choice for the selected workspace.
13. Add the prompt to these local start commands:
    - `start-claude`
    - `start-cline`
    - `start-codex`
    - `start-commandcode`
    - `start-cursor`
    - `start-grok`
    - `start-kilo`
    - `start-opencode`
    - `start-pi`
14. Do not add this behavior to AgentCore, Herdr, Hunk, Antigravity, or Gemini
    in this change.
15. Add a README example that shows how to start a direct agent from a parent
    folder:

    ```shell
    cd "/workspace/My Projects"
    start-codex
    ```

16. State in the README that every child repository is writable and Git
    commands must run inside the applicable repository.
17. Document `readonly/CONVENTIONS.md` and
    `readonly/REACT_INSTRUCTIONS.md` as optional files that users can copy into
    a project themselves.
