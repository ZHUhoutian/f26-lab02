#!/usr/bin/env bash
# export-transcripts.sh: copy your Claude Code transcripts into transcripts/
# in this repository, ready to review and commit.
#
# What it does:
#   1. Finds the Claude Code sessions that ran inside this repository, under
#      ~/.claude/projects/ (or $CLAUDE_CONFIG_DIR/projects if you set that).
#   2. Copies each session file (and its subagent transcripts, if any) into
#      transcripts/ at the repository root.
#   3. You review the result, then commit and push it like any other file.
#
# Usage (from anywhere inside your course repository):
#   ./tools/export-transcripts.sh
#
# Notes:
#   - Windows: run this from Git Bash or WSL.
#   - Sessions are stored on the machine where you ran the agent. If you
#     worked on more than one machine, run this script on each of them.
#   - Only sessions started inside this repository are exported. Start
#     Claude Code from the repository root and this finds everything.
#   - If you use a different agent tool, this script does not apply: you are
#     responsible for exporting an equivalent transcript (see policies.md).
#   - Review the exported files for accidentally personal content before
#     committing. The redaction rule is in policies.md.
#
# INVARIANT for anyone revising this script: it exports session logs ONLY,
# never the memory/ directory that lives alongside them (auto-memory can
# hold personal context that has no business in a graded repo). The
# top-level *.jsonl glob below guarantees this today; do not replace it
# with a recursive copy.

set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || {
    echo "error: this is not a git repository. Run the script from inside your course repository." >&2
    exit 1
}

CLAUDE_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
PROJECTS_DIR="$CLAUDE_DIR/projects"
if [ ! -d "$PROJECTS_DIR" ]; then
    echo "error: $PROJECTS_DIR not found." >&2
    echo "Claude Code stores its sessions there. Have you run Claude Code on this machine?" >&2
    exit 1
fi

# Claude Code names each folder under projects/ after the directory the
# session started in, with every non-alphanumeric character replaced by "-".
ENCODED="$(printf '%s\n' "$REPO_ROOT" | sed 's/[^A-Za-z0-9]/-/g')"

DEST="$REPO_ROOT/transcripts"
mkdir -p "$DEST"

copied=0
skipped=0

# copy_session <session-jsonl>: copies the session file plus its companion
# directory (subagent transcripts), preserving names.
copy_session() {
    f="$1"
    cp -p "$f" "$DEST/"
    companion="${f%.jsonl}"
    if [ -d "$companion" ]; then
        # Replace any previous export of this session's directory, otherwise
        # cp would nest the new copy inside the old one on a re-run.
        companion_dest="$DEST/$(basename "$companion")"
        rm -rf "$companion_dest"
        cp -Rp "$companion" "$companion_dest"
    fi
    copied=$((copied + 1))
}

for dir in "$PROJECTS_DIR/$ENCODED" "$PROJECTS_DIR/$ENCODED"-*; do
    [ -d "$dir" ] || continue
    for f in "$dir"/*.jsonl; do
        [ -f "$f" ] || continue
        if [ "$dir" = "$PROJECTS_DIR/$ENCODED" ]; then
            # Folder name matches the repository root exactly: always ours.
            copy_session "$f"
        elif grep -q -m 1 -F -e "\"cwd\":\"$REPO_ROOT\"" -e "\"cwd\":\"$REPO_ROOT/" "$f"; then
            # Folder name only starts with our name (a session started in a
            # subdirectory), which can collide with a sibling directory like
            # repo-extra/. The recorded working directory settles it.
            copy_session "$f"
        else
            skipped=$((skipped + 1))
        fi
    done
done

if [ "$copied" -eq 0 ]; then
    echo "No Claude Code sessions found for $REPO_ROOT."
    echo "Sessions are recorded per starting directory: start Claude Code inside the repository and try again."
    if [ "$skipped" -gt 0 ]; then
        echo "(Skipped $skipped session file(s) that ran in other directories.)"
    fi
    exit 1
fi

echo "Exported $copied session(s) to transcripts/ ($(du -sh "$DEST" | cut -f1) total)."
if [ "$skipped" -gt 0 ]; then
    echo "Skipped $skipped session file(s) that ran in other directories."
fi
echo
echo "Next steps:"
echo "  1. Skim the exported files for anything accidentally personal (see policies.md)."
echo "  2. git add transcripts && git commit -m \"Add agent transcripts\""
echo "  3. git push"
