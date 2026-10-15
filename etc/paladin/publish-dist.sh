#!/usr/bin/env bash
# Publish the checked-out commit as a pruned "dist" commit that cargo can
# fetch cheaply. The dist branch holds only what a dependent build needs and
# its history is independent of the dev branch. Publishes append to the dist
# branch and never rewrite it: cargo locks the commit sha, and a sha that
# leaves the branch makes every older lockfile that references it
# unbuildable.
#
# Usage: etc/paladin/publish-dist.sh <dist-branch> [remote]
# Prints the new dist commit sha on stdout.
set -euo pipefail

dist_branch=${1:?usage: publish-dist.sh <dist-branch> [remote]}
remote=${2:-origin}

cd "$(git rev-parse --show-toplevel)"
if [ -n "$(git status --porcelain)" ]; then
    echo "publish-dist: the working tree is not clean" >&2
    exit 1
fi
dev_commit=$(git rev-parse HEAD)
dev_branch=$(git rev-parse --abbrev-ref HEAD)

# Everything a dependent build needs: the workspace manifest and all eleven
# crates (style/Cargo.toml has path dependencies on selectors, servo_arc,
# to_shmem and to_shmem_derive). README.md is the `readme` of style/.
# Dropped: .github, the sync scripts.
keep=(
    Cargo.toml
    README.md
    rustfmt.toml
    malloc_size_of
    selectors
    servo_arc
    style
    style_derive
    style_traits
    stylo_atoms
    stylo_dom
    stylo_static_prefs
    to_shmem
    to_shmem_derive
    etc/paladin
)

git fetch "$remote" "refs/heads/$dist_branch:refs/remotes/$remote/$dist_branch" 2>/dev/null || true
parent=$(git rev-parse --verify -q "refs/remotes/$remote/$dist_branch" || true)

index=$(mktemp)
trap 'rm -f "$index"' EXIT
export GIT_INDEX_FILE=$index
git read-tree --empty
git ls-tree -r --full-tree HEAD -- "${keep[@]}" | git update-index --index-info
tree=$(git write-tree)
unset GIT_INDEX_FILE

message="dist: $dev_branch at ${dev_commit:0:12}

Built by etc/paladin/publish-dist.sh from $dev_commit."
if [ -n "$parent" ]; then
    commit=$(git commit-tree "$tree" -p "$parent" -m "$message")
else
    commit=$(git commit-tree "$tree" -m "$message")
fi
git push "$remote" "$commit:refs/heads/$dist_branch"
echo "$commit"
