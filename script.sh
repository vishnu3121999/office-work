#!/bin/bash
set -euo pipefail
# compare_deps.sh
# Compares the Bazel Maven dependency graph between two git branches.
# It stashes local changes, checks out each branch, runs a Bazel query using @mvn,
# prints the raw temporary dependency files, and outputs a formatted diff.
# Usage: ./compare_deps.sh <base_branch> <feature_branch>
# Example: ./compare_deps.sh master feature

if [ "$#" -ne 2 ]; then
  echo "Usage: $0 <base_branch> <feature_branch>"
  exit 1
fi

BASE_BRANCH=$1
FEATURE_BRANCH=$2

CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD)
echo "Current branch is '$CURRENT_BRANCH'."

# Stash any local changes (including untracked and ignored files) to avoid checkout conflicts.
if [ -n "$(git status --porcelain)" ]; then
  echo "Local changes detected. Stashing changes (including ignored files)..."
  git stash push -a -m "temp stash for compare_deps.sh"
  STASHED=1
else
  STASHED=0
fi

# Create a temporary directory for dependency files.
TMP_DIR=$(mktemp -d)
echo "Using temporary directory: $TMP_DIR"

# Use @mvn instead of @maven in the Bazel query.
BAZEL_QUERY_CMD="bazel query @mvn//:all --output=build | grep tags | awk -F'\"' '{print \$2}' | sed 's/maven_coordinates=//' | sort"

# Function to run Bazel query on a given branch and write output to a file.
run_query() {
  local branch=$1
  local outfile=$2
  echo "Force checking out branch: $branch"
  git checkout -f "$branch" || { echo "Failed to checkout $branch"; exit 1; }
  echo "Running Bazel query on branch '$branch'..."
  eval $BAZEL_QUERY_CMD > "$outfile"
  echo "Dependencies from '$branch' saved to $outfile."
}

# Run query on base and feature branches.
run_query "$BASE_BRANCH" "$TMP_DIR/base_deps.txt"
run_query "$FEATURE_BRANCH" "$TMP_DIR/feature_deps.txt"

# Print the temporary dependency files.
echo ""
echo "Base dependencies file:"
cat "$TMP_DIR/base_deps.txt"
echo ""
echo "Feature dependencies file:"
cat "$TMP_DIR/feature_deps.txt"
echo ""

# Generate a unified diff with zero context.
echo "Comparing dependency lists (formatted):"
diff -U0 "$TMP_DIR/base_deps.txt" "$TMP_DIR/feature_deps.txt" > "$TMP_DIR/diff_output.txt" || true

# Initialize arrays to hold lines for each hunk.
declare -a old_lines=()
declare -a new_lines=()

# Function to process a diff hunk and print formatted changes.
process_hunk() {
    local count_old=${#old_lines[@]}
    local count_new=${#new_lines[@]}
    local max=$(( count_old > count_new ? count_old : count_new ))
    for (( i=0; i<$max; i++ )); do
        if [ $i -lt $count_old ] && [ $i -lt $count_new ]; then
            echo "${old_lines[$i]}   -->   ${new_lines[$i]}"
        elif [ $i -lt $count_old ]; then
            echo "${old_lines[$i]}   -->   (removed)"
        elif [ $i -lt $count_new ]; then
            echo "(none)   -->   ${new_lines[$i]}"
        fi
    done
    # Clear arrays for the next hunk.
    old_lines=()
    new_lines=()
}

# Process the diff output.
while IFS= read -r line; do
    if [[ "$line" =~ ^@@ ]]; then
        # Process any hunk already collected.
        if [ ${#old_lines[@]} -gt 0 ] || [ ${#new_lines[@]} -gt 0 ]; then
            process_hunk
        fi
    elif [[ "$line" =~ ^- && ! "$line" =~ ^--- ]]; then
        # Remove the "-" prefix.
        old_lines+=( "${line:1}" )
    elif [[ "$line" =~ ^\+ && ! "$line" =~ ^\+\+\+ ]]; then
        # Remove the "+" prefix.
        new_lines+=( "${line:1}" )
    fi
done < "$TMP_DIR/diff_output.txt"

# Process any remaining lines.
if [ ${#old_lines[@]} -gt 0 ] || [ ${#new_lines[@]} -gt 0 ]; then
    process_hunk
fi

echo ""
echo "Formatted diff output complete."

# Restore original branch.
echo "Force restoring original branch: $CURRENT_BRANCH"
git checkout -f "$CURRENT_BRANCH" || { echo "Failed to checkout $CURRENT_BRANCH"; exit 1; }

# Restore stashed changes if any.
if [ "$STASHED" -eq 1 ]; then
  echo "Restoring stashed changes..."
  git stash pop || { echo "Failed to restore stashed changes."; exit 1; }
fi

# Clean up temporary directory.
rm -rf "$TMP_DIR"
echo "Temporary files cleaned up."
