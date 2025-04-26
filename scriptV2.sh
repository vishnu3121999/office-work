#!/usr/bin/env bash
set -euo pipefail

# compare_deps.sh
# Usage: ./compare_deps.sh <base_branch> <feature_branch>

if [ "$#" -ne 2 ]; then
  echo "Usage: $0 <base_branch> <feature_branch>"
  exit 1
fi

BASE=$1
FEATURE=$2
CURR=$(git rev-parse --abbrev-ref HEAD)
REPO="mvn"   # your maven_install name

echo "📌 Comparing '$BASE' → '$FEATURE'  (starting on '$CURR')"
echo

# 1) Stash everything so checkout never fails
if [ -n "$(git status --porcelain)" ]; then
  echo "🔒 Stashing local changes..."
  git stash push -a -m "temp-stash-for-compare_deps"
  STASHED=1
else
  STASHED=0
fi

# 2) Create temp dir
TMP=$(mktemp -d)
echo "📂 Temp dir: $TMP"
echo

# 3) Bazel query snippet for @mvn//:all
QUERY='bazel query @mvn//:all --output=build \
  | grep tags \
  | awk -F"\"" "{print \$2}" \
  | sed "s/maven_coordinates=//" \
  | sort'

run_query(){
  local branch=$1 out=$2
  git checkout -f "$branch" &>/dev/null
  echo "📦 Querying $branch… → $out"
  eval "$QUERY" > "$out"
}

# 4) Capture both branches’ deps
run_query "$BASE"    "$TMP/base_deps.txt"
run_query "$FEATURE" "$TMP/feature_deps.txt"

# 5) Print raw lists
echo "── Base dependencies ──"
cat "$TMP/base_deps.txt"
echo
echo "── Feature dependencies ──"
cat "$TMP/feature_deps.txt"
echo

# 6) Load into associative arrays
declare -A base_versions feat_versions
while IFS= read -r L; do
  ga=${L%:*}; v=${L##*:}
  base_versions["$ga"]=$v
done <"$TMP/base_deps.txt"
while IFS= read -r L; do
  ga=${L%:*}; v=${L##*:}
  feat_versions["$ga"]=$v
done <"$TMP/feature_deps.txt"

# 7) Union of all GA keys
mapfile -t ALL_GA < <(
  printf "%s\n" "${!base_versions[@]}" "${!feat_versions[@]}" | sort -u
)

# 8) Print version changes and classify
echo "── Version changes ──"
declare -a ADDED_UPGRADED REMOVED
for ga in "${ALL_GA[@]}"; do
  oldv=${base_versions[$ga]:-}
  newv=${feat_versions[$ga]:-}
  if [ -z "$oldv" ]; then
    echo "  • $ga  (added → $newv)"
    ADDED_UPGRADED+=("$ga")
  elif [ -z "$newv" ]; then
    echo "  • $ga  ($oldv → removed)"
    REMOVED+=("$ga")
  elif [ "$oldv" != "$newv" ]; then
    echo "  • $ga  (upgraded: $oldv → $newv)"
    ADDED_UPGRADED+=("$ga")
  fi
done
echo

# 9) Pre-fetch @mvn for rdeps()
echo "⏳ Pre-fetching @mvn artifacts…"
bazel fetch @mvn//:all &>/dev/null || true
echo

# 10) Prepare global set of affected services
declare -A AFFECTED_SERVICES
record_services(){
  for svc in "$@"; do
    if [[ -n "$svc" ]]; then
      AFFECTED_SERVICES["$svc"]=1
    fi
  done
}

# 11) Map added/upgraded on FEATURE branch
if [ "${#ADDED_UPGRADED[@]}" -gt 0 ]; then
  echo "──── Mapping added/upgraded deps on '$FEATURE' ────"
  git checkout -f "$FEATURE" &>/dev/null
  for ga in "${ADDED_UPGRADED[@]}"; do
    oldv=${base_versions[$ga]:-}
    newv=${feat_versions[$ga]:-}
    echo
    echo "▶ $ga"
    echo "    Status             : $( [ -z "$oldv" ] && echo "added → $newv" || echo "upgraded: $oldv → $newv" )"
    label=$(echo "$ga" | sed -E 's/[:\.-]/_/g')
    bz="@${REPO}//:$label"
    echo "    Bazel label        : $bz"

    # Direct dependency
    echo "    Direct dependency  :"
    mapfile -t DIR_SRCS < <(
      grep -R --include='BUILD*' -l "$bz" . \
      | xargs -r -n1 dirname \
      | sort -u
    )
    if [ "${#DIR_SRCS[@]}" -eq 0 ]; then
      echo "      (none)"
    else
      for svc in "${DIR_SRCS[@]}"; do
        echo "      - $svc"
        record_services "$svc"
      done
    fi

    # Transitive dependency (filter out INFO:)
    echo "    Transitive dependency:"
    mapfile -t TRANS_SRCS < <(
      bazel query --noshow_loading_progress --noshow_progress \
        "rdeps(//..., $bz)" \
        --noimplicit_deps --notool_deps --output=package 2>&1 \
      | grep -v '^INFO:' \
      | sort -u
    )
    if [ "${#TRANS_SRCS[@]}" -eq 0 ]; then
      echo "      (none)"
    else
      for svc in "${TRANS_SRCS[@]}"; do
        echo "      - $svc"
        record_services "$svc"
      done
    fi
  done
  echo
fi

# 12) Map removed on BASE branch
if [ "${#REMOVED[@]}" -gt 0 ]; then
  echo "──── Mapping removed deps on '$BASE' ────"
  git checkout -f "$BASE" &>/dev/null
  for ga in "${REMOVED[@]}"; do
    oldv=${base_versions[$ga]}
    echo
    echo "▶ $ga"
    echo "    Status             : removed (→ $oldv)"
    label=$(echo "$ga" | sed -E 's/[:\.-]/_/g')
    bz="@${REPO}//:$label"
    echo "    Bazel label        : $bz"

    # Direct dependency
    echo "    Direct dependency  :"
    mapfile -t DIR_SRCS < <(
      grep -R --include='BUILD*' -l "$bz" . \
      | xargs -r -n1 dirname \
      | sort -u
    )
    if [ "${#DIR_SRCS[@]}" -eq 0 ]; then
      echo "      (none)"
    else
      for svc in "${DIR_SRCS[@]}"; do
        echo "      - $svc"
        record_services "$svc"
      done
    fi

    # Transitive dependency (filter out INFO:)
    echo "    Transitive dependency:"
    mapfile -t TRANS_SRCS < <(
      bazel query --noshow_loading_progress --noshow_progress \
        "rdeps(//..., $bz)" \
        --noimplicit_deps --notool_deps --output=package 2>&1 \
      | grep -v '^INFO:' \
      | sort -u
    )
    if [ "${#TRANS_SRCS[@]}" -eq 0 ]; then
      echo "      (none)"
    else
      for svc in "${TRANS_SRCS[@]}"; do
        echo "      - $svc"
        record_services "$svc"
      done
    fi
  done
  echo
fi

# 13) Final: list all affected services
echo "── Affected services across all changes ──"
mapfile -t ALL_SERVICES < <(printf "%s\n" "${!AFFECTED_SERVICES[@]}" | sort)
if [ "${#ALL_SERVICES[@]}" -eq 0 ]; then
  echo "  (none)"
else
  for svc in "${ALL_SERVICES[@]}"; do
    echo "  - $svc"
  done
fi
echo

# 14) Restore & cleanup
echo "🔙 Restoring branch '$CURR'"
git checkout -f "$CURR" &>/dev/null
if (( STASHED )); then
  echo "🔓 Popping stash"
  git stash pop &>/dev/null
fi
rm -rf "$TMP"
echo "✅ Done. Temporary files cleaned up."
