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

echo "📌 Comparing '$BASE' → '$FEATURE'  (on '$CURR')"
echo

# 1) Stash everything so checkouts never fail
if [ -n "$(git status --porcelain)" ]; then
  echo "🔒 Stashing local changes..."
  git stash push -a -m "temp-stash-for-compare_deps"
  STASHED=1
else
  STASHED=0
fi

# 2) Make a temp dir
TMP=$(mktemp -d)
echo "📂 Temp dir: $TMP"
echo

# 3) Bazel query snippet for @mvn//:all
QUERY='bazel query @mvn//:all --output=build \
  | grep tags \
  | awk -F"\"" "{print \$2}" \
  | sed "s/maven_coordinates=//" \
  | sort'

# Safely bind branch+out
run_query() {
  local branch="$1"
  local out="$2"
  git checkout -f "$branch" &>/dev/null
  echo "📦 Querying $branch → $out"
  eval "$QUERY" > "$out"
}

# 4) Capture both sides
run_query "$BASE"    "$TMP/base_deps.txt"
run_query "$FEATURE" "$TMP/feature_deps.txt"

# 5) Show raw lists
echo "── Base dependencies ──"
cat "$TMP/base_deps.txt"
echo
echo "── Feature dependencies ──"
cat "$TMP/feature_deps.txt"
echo

# 6) Load into maps
declare -A base_versions feat_versions
while IFS= read -r L; do
  base_versions["${L%:*}"]="${L##*:}"
done <"$TMP/base_deps.txt"
while IFS= read -r L; do
  feat_versions["${L%:*}"]="${L##*:}"
done <"$TMP/feature_deps.txt"

# 7) Union of all G:A coords
mapfile -t ALL_GA < <(
  printf "%s\n" "${!base_versions[@]}" "${!feat_versions[@]}" |
    sort -u
)

# 8) Diff summary
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

# 9) Pre-fetch so rdeps works
echo "⏳ Pre-fetching @mvn artifacts…"
bazel fetch @mvn//:all &>/dev/null || true
echo

# 10) Collect affected services
declare -A AFFECTED
record() { for s in "$@"; do [[ -n "$s" ]] && AFFECTED["$s"]=1; done; }

# helper to map a single GA on a branch
map_ga() {
  local ga=$1 status=$2 branch=$3
  echo
  echo "▶ $ga  [$status]"
  git checkout -f "$branch" &>/dev/null

  local label="@${REPO}//:$(echo "$ga" | sed -E 's/[:\.-]/_/g')"
  echo "    Bazel label        : $label"

  # Direct
  echo "    Direct dependency  :"
  mapfile -t DIR < <(
    grep -R --include='BUILD*' -l "$label" . |
      xargs -r -n1 dirname |
      sort -u
  )
  if [ "${#DIR[@]}" -eq 0 ]; then
    echo "      (none)"
  else
    for d in "${DIR[@]}"; do
      echo "      - $d"; record "$d"
    done
  fi

  # Transitive (keep only //… packages)
  echo "    Transitive dependency:"
  mapfile -t TR < <(
    bazel query --noshow_loading_progress --noshow_progress \
      "rdeps(//..., $label)" \
      --noimplicit_deps --notool_deps --output=package 2>/dev/null |
      grep -v '^INFO:' |
      grep '^//' |
      sort -u
  )
  if [ "${#TR[@]}" -eq 0 ]; then
    echo "      (none)"
  else
    for t in "${TR[@]}"; do
      echo "      - $t"; record "$t"
    done
  fi
}

# 11) Map added/upgraded on feature
if [ "${#ADDED_UPGRADED[@]}" -gt 0 ]; then
  echo "──── Mapping added/upgraded on '$FEATURE' ────"
  for ga in "${ADDED_UPGRADED[@]}"; do
    oldv=${base_versions[$ga]:-}
    newv=${feat_versions[$ga]}
    status=$( [ -z "$oldv" ] \
      && printf "added→%s" "$newv" \
      || printf "upgraded:%s→%s" "$oldv" "$newv" )
    map_ga "$ga" "$status" "$FEATURE"
  done
  echo
fi

# 12) Map removed on base
if [ "${#REMOVED[@]}" -gt 0 ]; then
  echo "──── Mapping removed on '$BASE' ────"
  for ga in "${REMOVED[@]}"; do
    oldv=${base_versions[$ga]}
    map_ga "$ga" "removed→$oldv" "$BASE"
  done
  echo
fi

# 13) Final list of all affected services
echo "── Affected services across all changes ──"
mapfile -t SVC < <(printf "%s\n" "${!AFFECTED[@]}" | sort)
if [ "${#SVC[@]}" -eq 0 ]; then
  echo "  (none)"
else
  for s in "${SVC[@]}"; do
    echo "  - $s"
  done
fi
echo

# 14) Restore & cleanup
echo "🔙 Restoring branch '$CURR'"
git checkout -f "$CURR" &>/dev/null
(( STASHED )) && git stash pop &>/dev/null
rm -rf "$TMP"
echo "✅ Done."
