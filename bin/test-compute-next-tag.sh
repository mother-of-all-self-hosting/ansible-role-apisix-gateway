#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 Slavi Pantaleev
#
# SPDX-License-Identifier: AGPL-3.0-or-later

# Exercises bin/compute-next-tag.sh against throwaway git repositories.
#
# Usage: bin/test-compute-next-tag.sh
#
# Every scenario creates a repository in a temporary directory, gives it role
# files and a release history, and then replays a series of merges through the
# real script, tagging as it goes just like the autotag workflow does. This
# repository is never touched and no network access is needed.

set -euo pipefail

script_under_test="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/compute-next-tag.sh"

failures=0
workdir=''

cleanup() {
	cd /
	if [ -n "$workdir" ]; then
		rm -rf "$workdir"
		workdir=''
	fi
}

trap cleanup EXIT

# Starts a scenario with a repository at APISIX 3.8.0 which has already
# seen two releases of it (v3.8.0-0 and v3.8.0-1).
#
# defaults/main.yml is deliberately hostile to a naive version match: the
# Jinja-derived image tag mentions the version variable by name and carries a
# `-debian` suffix, a longer variable name shares its prefix, and a decoy with
# a different version sits above the real assignment. Only the anchored
# `apisix_version:` line may be picked up.
scenario() {
	echo "$1"

	cleanup
	workdir="$(mktemp -d)"

	mkdir -p "$workdir/bin" "$workdir/defaults" "$workdir/tasks" "$workdir/templates"
	cp "$script_under_test" "$workdir/bin/"
	cd "$workdir"

	git init -q -b main .
	git config user.email 'test@example.com'
	git config user.name 'Test'
	git config commit.gpgsign false

	cat > defaults/main.yml <<-'EOF'
		# apisix_version: 9.9.9 (a commented-out decoy)
		apisix_dashboard_version: 3.0.1
		apisix_version_extra: 7.7.7
		apisix_version: 3.8.0
		apisix_container_image_tag: "{{ apisix_version }}-debian"
	EOF
	printf 'placeholder\n' > tasks/main.yml
	printf 'placeholder\n' > templates/env.j2
	printf 'placeholder\n' > README.md

	git add -A
	git commit -qm 'Initial commit'

	local release_number
	for release_number in 0 1; do
		git tag "v3.8.0-$release_number"
	done
}

# Applies a change, commits it, and tags whatever the script says it should be.
# Prints the tag, or nothing when the script decided against a release.
merge() {
	local change="$1" tag

	eval "$change"
	git add -A
	git commit -qm 'Merge'

	tag="$(bin/compute-next-tag.sh 2>/dev/null)"

	if [ -n "$tag" ]; then
		git tag "$tag"
	fi

	printf '%s' "$tag"
}

expect() {
	local description="$1" expected="$2" actual="$3"

	if [ "$actual" = "$expected" ]; then
		printf '  ok   | %s -> %s\n' "$description" "${actual:-no release}"
	else
		printf '  FAIL | %s -> expected %s, got %s\n' "$description" "${expected:-no release}" "${actual:-no release}"
		failures=$((failures + 1))
	fi
}

bump_version="sed -i 's|^apisix_version: 3.8.0|apisix_version: 3.18.0|' defaults/main.yml"
revert_version="sed -i 's|^apisix_version: 3.18.0|apisix_version: 3.8.0|' defaults/main.yml"
edit_task="printf 'a task\n' >> tasks/main.yml"
edit_template="printf 'a line\n' >> templates/env.j2"
edit_readme="printf 'documentation\n' >> README.md"
edit_script="printf '# a comment\n' >> bin/compute-next-tag.sh"
edit_decoy="sed -i 's|^apisix_version_extra: 7.7.7|apisix_version_extra: 8.8.8|' defaults/main.yml"

# The two merge orders below apply the same updates and must each end up with
# every update released exactly once, whichever order they arrive in.

scenario 'A version bump merged before other role changes'
expect 'version bump' v3.18.0-0 "$(merge "$bump_version")"
expect 'task edit'    v3.18.0-1 "$(merge "$edit_task")"
expect 'template'     v3.18.0-2 "$(merge "$edit_template")"

scenario 'A version bump merged after other role changes'
expect 'task edit'    v3.8.0-2  "$(merge "$edit_task")"
expect 'version bump' v3.18.0-0 "$(merge "$bump_version")"

scenario 'Commits that do not affect the role'
expect 'README'   ''       "$(merge "$edit_readme")"
expect 'a script' ''       "$(merge "$edit_script")"
expect 'a task'   v3.8.0-2 "$(merge "$edit_task")"

# The real repository is already past v3.8.0-9, so this ordering is not
# hypothetical: a lexical sort would pick -9 and recompute an existing tag.
scenario 'Release numbers past 9'
for release_number in 2 3 4 5 6 7 8 9 10; do
	git tag "v3.8.0-$release_number"
done
expect 'a task' v3.8.0-11 "$(merge "$edit_task")"

scenario 'Reverting to an already released version'
merge "$bump_version" > /dev/null
# The role is now identical to what v3.8.0-1 already published, so there is
# nothing new to release.
expect 'a revert' ''       "$(merge "$revert_version")"

scenario 'Reverting to an already released version, with a change'
merge "$bump_version" > /dev/null
expect 'a revert' v3.8.0-2 "$(merge "$revert_version && $edit_task")"

# A variable whose name merely starts with the same prefix must not be mistaken
# for the version. It still lives under defaults/, so it releases - but as a
# release of 3.8.0, not of 8.8.8.
scenario 'A same-prefix variable is not the version'
expect 'decoy edit' v3.8.0-2 "$(merge "$edit_decoy")"

if [ "$failures" -gt 0 ]; then
	echo >&2 "$failures scenario(s) behaved unexpectedly"
	exit 1
fi

echo 'All scenarios behaved as expected'
