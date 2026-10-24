#!/usr/bin/env bash
# =============================================================================
# Static ELF/QML layout analysis of the built illogical-impulse-caelestia-plugin.
#
#   check-plugin-package.sh <pkg.tar.zst | extracted-dir>
#
# Read-only. Reports:
#   * installed QML module layout (qmldir / plugin .so / backing libs)
#   * RPATH/RUNPATH of every ELF, flagging absolute paths outside /usr
#   * any embedded reference to a developer home directory
#   * Caelestia NEEDED libs that cannot be resolved through the object's OWN
#     RUNPATH (DT_RUNPATH is not transitive: this can break dlopen of a plugin
#     whose backing libs depend on sibling backing libs)
# Exit status: 1 if a hard FAIL is found, 0 otherwise (WARN does not fail).
# =============================================================================
set -uo pipefail

src="${1:?usage: check-plugin-package.sh <pkg.tar.zst | extracted-dir>}"
FAIL=0; WARN=0
fail() { echo "FAIL: $*"; FAIL=$((FAIL+1)); }
warn() { echo "WARN: $*"; WARN=$((WARN+1)); }
ok()   { echo "ok:   $*"; }

if [[ -f "$src" ]]; then
    root="$(mktemp -d)"; trap 'rm -rf "$root"' EXIT
    bsdtar -xf "$src" -C "$root" || { echo "cannot extract $src"; exit 2; }
else
    root="$src"
fi

# QML dir inside a package is usr/lib/qt6/qml; a build tree has qml/ instead.
qmlroot=""
for c in "$root/usr/lib/qt6/qml" "$root/qml"; do [[ -d "$c/Caelestia" ]] && qmlroot="$c" && break; done
[[ -n "$qmlroot" ]] || { fail "no Caelestia QML tree found under $root"; exit 1; }
echo "QML root: ${qmlroot#"$root"/}"

[[ -f "$qmlroot/Caelestia/qmldir" ]] && ok "Caelestia/qmldir present" || fail "Caelestia/qmldir missing"
n_mod=$(find "$qmlroot/Caelestia" -name qmldir | wc -l)
echo "      qmldir files: $n_mod"

mapfile -t elfs < <(find "$root" -type f -name '*.so*' -not -path '*/CMakeFiles/*' -print)
(( ${#elfs[@]} > 0 )) || { fail "no shared objects found"; exit 1; }
echo "      shared objects: ${#elfs[@]}"

for f in "${elfs[@]}"; do
    rel="${f#"$root"/}"
    dyn="$(readelf -d "$f" 2>/dev/null)" || continue

    rp="$(sed -n 's/.*(\(RPATH\|RUNPATH\)).*\[\(.*\)\]/\2/p' <<<"$dyn" | head -1)"
    if [[ -n "$rp" ]]; then
        IFS=':' read -ra parts <<<"$rp"
        for p in "${parts[@]}"; do
            [[ -z "$p" ]] && { warn "$rel: empty RUNPATH entry (resolves to CWD)"; continue; }
            case "$p" in
                '$ORIGIN'*|/usr/*) ;;
                *) fail "$rel: RUNPATH entry outside /usr or \$ORIGIN: $p";;
            esac
        done
    fi

    if strings -a "$f" | grep -qE '/home/[A-Za-z0-9_.-]+/'; then
        n=$(strings -a "$f" | grep -cE '/home/[A-Za-z0-9_.-]+/')
        # Debug-info paths are tolerable; flag them as WARN, RUNPATH ones already FAIL.
        warn "$rel: $n embedded /home/<user>/ strings (build paths / debug info?)"
    fi

    # Transitive-RUNPATH check for Caelestia sibling deps.
    dir="$(dirname "$f")"
    while read -r need; do
        found=false
        if [[ -n "$rp" ]]; then
            for p in "${parts[@]}"; do
                d="${p//\$ORIGIN/$dir}"
                [[ -e "$d/$need" ]] && found=true && break
            done
        fi
        [[ -e "$dir/$need" && -z "$rp" ]] && : # same dir is NOT searched without RUNPATH/ORIGIN
        $found || warn "$rel: NEEDED $need not resolvable via its own RUNPATH (OK only if already loaded by SONAME; verify with a real dlopen)"
    done < <(sed -n 's/.*Shared library: \[\(libcaelestia-[^]]*\)\].*/\1/p' <<<"$dyn")
done

echo
echo "Result: $FAIL FAIL, $WARN WARN"
(( FAIL == 0 ))
