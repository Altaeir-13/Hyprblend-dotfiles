#!/usr/bin/env bash
# =============================================================================
# Reproducible, push-free transfer bundle of the working tree (tracked changes
# + untracked files) for testing inside a disposable VM.
#
#   bundle.sh create <out-dir>             (host; read-only on the repository)
#   bundle.sh verify <bundle-dir> <work>   (host or VM; clones + checks hashes)
#
# Produces in <out-dir>:
#   repo.bundle          full git history (all local branches)
#   overlay.tar.gz       modified + untracked files, deterministic tar
#   OVERLAY.sha256       sha256 of every overlay file (path-relative)
#   DELETED.txt          tracked files deleted in the working tree (if any)
#   BASE_REVISION        branch + commit the overlay applies on top of
#   SHA256SUMS           checksums of the artefacts above
#
# The submodule content is NOT bundled: it is fetched at the pinned gitlink by
# `git submodule update --init` (the installer already does this).
# =============================================================================
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

# Never ship these, even if somebody forgot to gitignore them.
DENY_REGEX='(^|/)(\.env[^/]*|id_(rsa|ed25519|ecdsa)[^/]*|[^/]*\.(pem|key|p12|pfx|kdbx|gpg)|\.netrc|\.git-credentials|cache|build[^/]*|__pycache__|node_modules|\.venv)(/|$)|\.(so|o|a|log|bak|orig|rej|swp|core)$|\.pkg\.tar\.[a-z]+$'

die() { echo "bundle.sh: $*" >&2; exit 1; }

cmd_create() {
    local out="${1:?usage: bundle.sh create <out-dir>}"
    cd "$REPO_ROOT"
    [[ -z "$(git ls-files -u)" ]] || die "unmerged paths present"

    mkdir -p "$out"
    out="$(cd "$out" && pwd)"
    rm -f "$out"/{repo.bundle,overlay.tar.gz,OVERLAY.sha256,DELETED.txt,BASE_REVISION,SHA256SUMS}

    local head branch ts
    head="$(git rev-parse HEAD)"
    branch="$(git rev-parse --abbrev-ref HEAD)"
    ts="$(git log -1 --format=%ct)"

    # Candidate files: modified tracked (not deleted) + untracked, non-ignored.
    local list; list="$(mktemp)"
    trap 'rm -f "$list"' RETURN
    { git diff --name-only --diff-filter=d -z HEAD; git ls-files -o --exclude-standard -z; } \
        | sort -z -u > "$list"

    # Drop submodule gitlinks (their content is fetched separately).
    local sub; sub="$(git submodule status --recursive | awk '{print $2}')"
    if [[ -n "$sub" ]]; then
        local filtered; filtered="$(mktemp)"
        while IFS= read -r -d '' f; do
            skip=false
            for s in $sub; do [[ "$f" == "$s" || "$f" == "$s/"* ]] && skip=true; done
            $skip || printf '%s\0' "$f"
        done < "$list" > "$filtered"
        mv "$filtered" "$list"
    fi

    # Safety net against leaking sensitive files / artefacts.
    local bad
    bad="$(tr '\0' '\n' < "$list" | grep -E "$DENY_REGEX" || true)"
    [[ -z "$bad" ]] || die "refusing to bundle suspicious paths:"$'\n'"$bad"

    git diff --name-only --diff-filter=D HEAD > "$out/DELETED.txt"
    [[ -s "$out/DELETED.txt" ]] || rm -f "$out/DELETED.txt"

    git bundle create "$out/repo.bundle" --branches >/dev/null 2>&1
    git bundle verify "$out/repo.bundle" >/dev/null 2>&1 || die "git bundle verify failed"

    tar --null -T "$list" --sort=name --owner=0 --group=0 --numeric-owner \
        --mtime="@${ts}" -cf - | gzip -n -9 > "$out/overlay.tar.gz"

    xargs -0 -a "$list" sha256sum > "$out/OVERLAY.sha256"
    printf 'branch=%s\ncommit=%s\ncommit_time=%s\nsubmodules=%s\nfiles=%s\n' \
        "$branch" "$head" "$ts" "$(git submodule status --recursive | tr '\n' ';')" \
        "$(tr -cd '\0' < "$list" | wc -c)" > "$out/BASE_REVISION"

    ( cd "$out" && sha256sum repo.bundle overlay.tar.gz OVERLAY.sha256 BASE_REVISION \
        $( [[ -f DELETED.txt ]] && echo DELETED.txt ) > SHA256SUMS )

    echo "Bundle created in: $out"
    cat "$out/BASE_REVISION"
    cat "$out/SHA256SUMS"
}

cmd_verify() {
    local dir="${1:?usage: bundle.sh verify <bundle-dir> <workdir>}"
    local work="${2:?usage: bundle.sh verify <bundle-dir> <workdir>}"
    dir="$(cd "$dir" && pwd)"

    ( cd "$dir" && sha256sum -c SHA256SUMS ) || die "artefact checksum mismatch"

    [[ ! -e "$work" ]] || die "workdir already exists: $work"
    git clone -q "$dir/repo.bundle" "$work"
    local commit branch
    commit="$(sed -n 's/^commit=//p' "$dir/BASE_REVISION")"
    branch="$(sed -n 's/^branch=//p' "$dir/BASE_REVISION")"
    git -C "$work" checkout -q "$branch" 2>/dev/null || git -C "$work" checkout -q "$commit"
    [[ "$(git -C "$work" rev-parse HEAD)" == "$commit" ]] || die "base commit mismatch"

    tar -xzf "$dir/overlay.tar.gz" -C "$work"
    if [[ -f "$dir/DELETED.txt" ]]; then
        while IFS= read -r f; do rm -f -- "$work/$f"; done < "$dir/DELETED.txt"
    fi

    ( cd "$work" && sha256sum -c --quiet "$dir/OVERLAY.sha256" ) || die "overlay hash mismatch"
    echo "OK: base ${commit:0:12} + overlay verified in $work"
}

case "${1:-}" in
    create) shift; cmd_create "$@";;
    verify) shift; cmd_verify "$@";;
    *) die "usage: bundle.sh create <out-dir> | verify <bundle-dir> <workdir>";;
esac
