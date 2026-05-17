#!/usr/bin/env bash
# PostToolUse Bash: Strip Co-authored-by from git commits
# FAIL-OPEN: any error → exit silently
trap 'exit 0' ERR

INPUT=$(cat)

# Only act on git commit commands
echo "$INPUT" | grep -q '"command".*git.*commit' || exit 0

# Check last commit for Co-authored-by
LAST_MSG=$(git log -1 --format=%B 2>/dev/null) || exit 0
echo "$LAST_MSG" | grep -qi "Co-authored-by" || exit 0

# Amend to strip Co-authored-by lines
CLEAN_MSG=$(echo "$LAST_MSG" | grep -vi "Co-authored-by" | sed -e :a -e '/^\n*$/{$d;N;ba;}')
[ -z "$CLEAN_MSG" ] && exit 0

echo "$CLEAN_MSG" | git commit --amend -F - --no-verify --quiet 2>/dev/null
exit 0
