#!/usr/bin/env bash
# kit-update — update every installed Claude Code plugin in one go.
#
# `claude plugin update` only takes one plugin at a time, so this script:
#   1. refreshes every marketplace   (claude plugin marketplace update)
#   2. snapshots installs            (claude plugin list --json)
#   3. runs `claude plugin update <id> --scope <scope> --json` for each one
#   4. snapshots again and diffs versions to report what actually changed
#
# Requires: claude >= 2.1.268 (for `plugin update --json`), jq.
#
# Usage: update-all.sh [options]
#   -n, --dry-run          show what would be updated, change nothing
#       --no-marketplaces  skip the marketplace refresh step
#       --all-projects     also update project/local installs of OTHER projects
#                          (default: only the current project's)
#       --scope LIST       comma list of scopes to touch (default: user,project,local,managed)
#       --only REGEX       only plugins whose id matches REGEX (e.g. '@my-marketplace$')
#   -y, --yes              pass -y to `plugin update` (accept a changed install command
#                          from a command-source plugin). Ignored by Claude Code when the
#                          script runs inside a Claude session — run it from your terminal.
#   -h, --help
#
# Exit code: 0 when nothing failed, 1 when any update failed or a precondition is missing.

set -uo pipefail

CLAUDE_BIN="${KIT_UPDATE_CLAUDE_BIN:-claude}"   # override for testing
MIN_VERSION="2.1.268"

DRY_RUN=0
SKIP_MKT=0
ALL_PROJECTS=0
SCOPES="user,project,local,managed"
ONLY=""
YES=0

usage() { sed -n '2,/^$/p' "$0" | sed 's/^# \{0,1\}//'; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    -n|--dry-run)       DRY_RUN=1 ;;
    --no-marketplaces)  SKIP_MKT=1 ;;
    --all-projects)     ALL_PROJECTS=1 ;;
    --scope)            SCOPES="${2:?--scope needs a value}"; shift ;;
    --scope=*)          SCOPES="${1#*=}" ;;
    --only)             ONLY="${2:?--only needs a value}"; shift ;;
    --only=*)           ONLY="${1#*=}" ;;
    -y|--yes)           YES=1 ;;
    -h|--help)          usage; exit 0 ;;
    *) echo "unknown option: $1 (see --help)" >&2; exit 1 ;;
  esac
  shift
done

# ---------- helpers ----------------------------------------------------------

if [[ -t 1 ]]; then
  B=$'\e[1m'; DIM=$'\e[2m'; G=$'\e[32m'; Y=$'\e[33m'; R=$'\e[31m'; C=$'\e[36m'; N=$'\e[0m'
else
  B=; DIM=; G=; Y=; R=; C=; N=
fi
step() { printf '%s==>%s %s\n' "$C$B" "$N" "$*"; }
warn() { printf '%swarn:%s %s\n' "$Y" "$N" "$*" >&2; }
die()  { printf '%serror:%s %s\n' "$R" "$N" "$*" >&2; exit 1; }

# version_ge A B  -> true when A >= B (numeric dot compare, no sort -V needed)
version_ge() {
  local IFS=. i a=($1) b=($2)
  for ((i = 0; i < ${#b[@]} || i < ${#a[@]}; i++)); do
    local x=${a[i]:-0} y=${b[i]:-0}
    x=${x//[!0-9]/}; y=${y//[!0-9]/}
    ((10#${x:-0} > 10#${y:-0})) && return 0
    ((10#${x:-0} < 10#${y:-0})) && return 1
  done
  return 0
}

canon() { (cd "$1" 2>/dev/null && pwd -P) || printf '%s' "$1"; }

TMP=$(mktemp -d "${TMPDIR:-/tmp}/kit-update.XXXXXX") || die "mktemp failed"
trap 'rm -rf "$TMP"' EXIT

# ---------- preconditions ----------------------------------------------------

command -v jq >/dev/null 2>&1 || die "jq not found — install it (brew install jq / apt install jq / winget install jqlang.jq)"
command -v "$CLAUDE_BIN" >/dev/null 2>&1 || die "'$CLAUDE_BIN' not found on PATH"

cc_version=$("$CLAUDE_BIN" --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
if [[ -z "$cc_version" ]]; then
  warn "could not read Claude Code version; assuming it supports 'plugin update --json'"
elif ! version_ge "$cc_version" "$MIN_VERSION"; then
  die "Claude Code $cc_version is too old — need $MIN_VERSION+ for 'plugin update --json' (run: claude update)"
fi

CURRENT_PROJECT=$(canon "${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}")
scopes_json=$(jq -cn --arg s "$SCOPES" '$s | split(",") | map(gsub("^\\s+|\\s+$"; ""))')

snapshot() { # $1 = output file
  "$CLAUDE_BIN" plugin list --json >"$1" 2>"$TMP/list.err" \
    || die "'claude plugin list --json' failed: $(cat "$TMP/list.err")"
  jq -e 'type == "array"' "$1" >/dev/null 2>&1 \
    || die "'claude plugin list --json' did not return a JSON array"
}

# ---------- 1. marketplaces --------------------------------------------------

if ((SKIP_MKT)); then
  step "Skipping marketplace refresh (--no-marketplaces)"
elif ((DRY_RUN)); then
  step "[dry-run] would run: claude plugin marketplace update"
else
  step "Refreshing all marketplaces"
  if mkt_out=$("$CLAUDE_BIN" plugin marketplace update 2>&1); then
    printf '    %s\n' "$mkt_out"
  else
    warn "marketplace refresh failed — continuing with cached catalogs"
    printf '    %s\n' "$mkt_out" >&2
  fi
fi

# ---------- 2. pick targets --------------------------------------------------

step "Reading installed plugins"
snapshot "$TMP/before.json"

# One TSV row per updatable install: id, scope, version, projectPath
jq -r --argjson scopes "$scopes_json" --arg only "$ONLY" '
  .[]
  | select(.id | test("@(inline|skills-dir|synced)$") | not)   # not marketplace installs
  | select(.scope as $s | $scopes | index($s))
  | select($only == "" or (.id | test($only)))
  | [.id, .scope, (.version // "?"), (.projectPath // "")] | @tsv
' "$TMP/before.json" >"$TMP/targets.tsv"

# Non-marketplace plugins are reported, never touched
jq -r '.[] | select(.id | test("@(inline|skills-dir|synced)$")) | .id' "$TMP/before.json" >"$TMP/nonmkt.txt"

targets=() skipped=()
while IFS=$'\t' read -r id scope ver proj; do
  [[ -z "$id" ]] && continue
  if [[ "$scope" == project || "$scope" == local ]]; then
    if [[ -z "$proj" || ! -d "$proj" ]]; then
      skipped+=("$id ($scope) — project path missing: ${proj:-<none>}")
      continue
    fi
    if ((!ALL_PROJECTS)) && [[ "$(canon "$proj")" != "$CURRENT_PROJECT" ]]; then
      skipped+=("$id ($scope) — other project: $proj (use --all-projects)")
      continue
    fi
  fi
  targets+=("$id"$'\t'"$scope"$'\t'"$ver"$'\t'"$proj")
done <"$TMP/targets.tsv"

print_nonmkt() {
  if [[ -s "$TMP/nonmkt.txt" ]]; then
    echo "  Not updatable here (session / skills-dir / claude.ai-synced):"
    sed 's/^/    - /' "$TMP/nonmkt.txt"
  fi
}

total=${#targets[@]}
if ((total == 0)); then
  step "No marketplace-installed plugins to update"
  ((${#skipped[@]})) && printf '    skipped: %s\n' "${skipped[@]}"
  print_nonmkt
  exit 0
fi

# ---------- 3. update each ---------------------------------------------------

if ((DRY_RUN)); then
  step "Would check $total plugin install(s) for updates (a dry run can't tell which have a newer version)"
else
  step "Updating $total plugin install(s)"
fi
failed=() needs_terminal=()
i=0
for row in "${targets[@]}"; do
  IFS=$'\t' read -r id scope ver proj <<<"$row"
  i=$((i + 1))
  label="$id ${DIM}[$scope${proj:+ · $proj}]${N}"

  if ((DRY_RUN)); then
    printf '    [%d/%d] %s  %s(installed: %s)%s\n' "$i" "$total" "$label" "$DIM" "$ver" "$N"
    continue
  fi

  args=(plugin update "$id" --scope "$scope" --json)
  ((YES)) && args+=(-y)
  workdir="${proj:-$PWD}"

  # stdout: last line is the JSON result; stderr kept separately
  (cd "$workdir" && "$CLAUDE_BIN" "${args[@]}" </dev/null) >"$TMP/out" 2>"$TMP/err"
  rc=$?
  result=$(grep -E '^[[:space:]]*\{' "$TMP/out" | tail -1)
  outcome=$(jq -r '.outcome // empty' <<<"$result" 2>/dev/null)
  message=$(jq -r '.message // empty' <<<"$result" 2>/dev/null)
  sha=$(jq -r '.shownCommand.sha256 // empty' <<<"$result" 2>/dev/null)
  [[ -z "$message" ]] && message=$(tail -1 "$TMP/err" 2>/dev/null)

  if [[ "$outcome" == ok && $rc -eq 0 ]]; then
    printf '    [%d/%d] %s  %sok%s\n' "$i" "$total" "$label" "$G" "$N"
  else
    printf '    [%d/%d] %s  %sFAILED%s %s\n' "$i" "$total" "$label" "$R" "$N" "$message"
    failed+=("$id ($scope): ${message:-exit $rc}")
    if [[ -n "$sha" ]]; then
      cmd="claude plugin update $id --scope $scope --accept-command $sha"
      [[ -n "$proj" ]] && cmd="cd \"$proj\" && $cmd"
      needs_terminal+=("$cmd")
    fi
  fi
done

# ---------- 4. diff & summary ------------------------------------------------

if ((DRY_RUN)); then
  echo
  step "Dry run — nothing changed"
  ((${#skipped[@]})) && { echo "  Skipped:"; printf '    - %s\n' "${skipped[@]}"; }
  print_nonmkt
  exit 0
fi

snapshot "$TMP/after.json"

# Rows: id, scope, old version, new version, projectPath (last: may be empty) — only changed
jq -r -n --slurpfile b "$TMP/before.json" --slurpfile a "$TMP/after.json" '
  def key: "\(.id)|\(.scope)|\(.projectPath // "")";
  ($b[0] | map({key: key, value: .version}) | from_entries) as $old
  | $a[0][]
  | select($old[key] != null and $old[key] != .version)
  | [.id, .scope, $old[key], .version, (.projectPath // "")] | @tsv
' >"$TMP/changed.tsv"

n_changed=$(grep -c . "$TMP/changed.tsv" || true)
n_failed=${#failed[@]}
n_same=$((total - n_changed - n_failed))
((n_same < 0)) && n_same=0

echo
printf '%sSummary%s  updated: %s%d%s · already latest: %d · failed: %s%d%s · skipped: %d\n' \
  "$B" "$N" "$G" "$n_changed" "$N" "$n_same" "$R" "$n_failed" "$N" "${#skipped[@]}"

if ((n_changed)); then
  echo "  Updated:"
  while IFS=$'\t' read -r id scope old new proj; do
    printf '    - %s [%s]  %s → %s\n' "$id" "$scope" "$old" "$new"
  done <"$TMP/changed.tsv"
fi
((n_failed)) && { echo "  Failed:"; printf '    - %s\n' "${failed[@]}"; }
((${#skipped[@]})) && { echo "  Skipped:"; printf '    - %s\n' "${skipped[@]}"; }
print_nonmkt
if ((${#needs_terminal[@]})); then
  echo "  These need you to accept a changed install command — review it, then run from your own terminal:"
  printf '    %s\n' "${needs_terminal[@]}"
fi
if ((n_changed)); then
  echo
  echo "Run /reload-plugins in any open Claude Code session (or restart) to load the new versions."
fi

((n_failed == 0))
