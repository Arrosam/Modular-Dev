#!/usr/bin/env bash
# PostToolUse Bash: Strip Co-authored-by from git commits
# FAIL-OPEN: any error → exit silently
trap 'exit 0' ERR

INPUT=$(cat | tr -d $'\r')

# Only act on git commit commands
echo "$INPUT" | grep -q '"command".*git.*commit' || exit 0

# Check last commit for Co-authored-by
LAST_MSG=$(git log -1 --format=%B 2>/dev/null) || exit 0
echo "$LAST_MSG" | grep -qi "Co-authored-by" || exit 0

# Amend to strip Co-authored-by lines and trailing blank lines
CLEAN_MSG=$(echo "$LAST_MSG" | grep -vi "Co-authored-by")
# Strip trailing blank lines (portable — no GNU sed extensions)
CLEAN_MSG=$(echo "$CLEAN_MSG" | awk 'NF{p=1} p' | awk '{a[NR]=$0} END{for(i=NR;i>=1;i--)if(a[i]!=""){last=i;break} for(i=1;i<=last;i++)print a[i]}')
[ -z "$CLEAN_MSG" ] && exit 0

echo "$CLEAN_MSG" | git commit --amend -F - --no-verify --quiet 2>/dev/null
exit 0
