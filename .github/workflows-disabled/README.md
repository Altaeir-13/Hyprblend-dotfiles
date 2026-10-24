# Disabled inherited workflows

GitHub Actions only runs workflows located in `.github/workflows/`. The files in this
directory were inherited from upstream [end-4/dots-hyprland](https://github.com/end-4/dots-hyprland)
(GPL-3.0, see [`LICENSE`](../../LICENSE)) and were moved here with `git mv`
(history preserved, content unchanged) because they were **not reviewed for the Hyprland Hybrid Rice fork**.

They are kept, rather than deleted, to preserve upstream attribution and to make
re-enabling trivial: `git mv .github/workflows-disabled/<file> .github/workflows/`.
**Review the file first**, especially the permissions and the external calls listed below.

Nothing in the repository references these workflows (checked with a repository-wide search for
their file names and `ai-moderator`); no other workflow, script or test depends on them.

| Workflow | Upstream-specific | Writes to issues / comments | External services | Decision |
| :--- | :--- | :--- | :--- | :--- |
| `auto-close-issue.yml` | Yes. Matches a checkbox of end-4's issue template and replies with end-4's moderation text. | **Yes**: posts a comment, closes the issue (`NOT_PLANNED`) and **locks** it. Token with `issues: write`. | `api.github.com` (GraphQL and REST) | **Disabled.** Also useless here: Issues are disabled on this repository. |
| `moderator.yml` | Generic, but not reviewed for this project. | **Yes**: labels issues, **minimizes comments**; triggers on `issues`, `issue_comment` (this includes **comments on pull requests**) and `pull_request_review_comment`. Token with `issues: write`, `pull-requests: write`. | `github/ai-moderator@v1` (third-party action, GitHub Models inference) | **Disabled.** It would automatically moderate the maintainer's own PR comments with an unreviewed AI model. |
| `dist-update-notification.yml` | Yes. Posts to end-4's discussion #2140. Guarded by `github.repository == 'end-4/dots-hyprland'`, so it was always skipped in this fork. | Would write a discussion comment (only upstream). Builds a GraphQL query by interpolating `github.event.head_commit.message` into the script (shell/GraphQL injection pattern). | `api.github.com` (GraphQL) | **Disabled.** Dead code in this fork and unsafe if the guard were ever removed. |
| `dump-github-context.yml` | No (generic debug helper). | No | None (prints the `github` context to the public log) | **Disabled.** Manual-only debug helper, not needed; prints the whole event context to public logs. |
| `ci.yml` (**kept** in `.github/workflows/`) | No: written for this project. | No (`permissions: contents: read`) | None besides checkout and `apt` | **Kept active.** Provides the required checks `Static Syntax & Portability Checks` and `Automated Regression Test Suite (Sandboxed)`. Maintenance fix: the `bash -n` step now checks every script individually (`find ... -exec bash -n {} +` only parsed the first file). |

## Re-enabling policy

A workflow should only be moved back to `.github/workflows/` after being reviewed for:

1. Least-privilege `permissions:` at workflow or job level.
2. No untrusted input (`github.event.*.body`, titles, commit messages) interpolated into `run:` scripts.
3. No dependency on end-4's repository names, discussion numbers or issue-template text.
4. Third-party actions pinned to a commit SHA when they receive a write token.
