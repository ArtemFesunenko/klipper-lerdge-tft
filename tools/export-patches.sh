#!/bin/bash
# Regenerate patches/ from a Klipper branch that contains the changes as
# commits on top of upstream Klipper.
#
# Usage: tools/export-patches.sh <klipper dir> <base commit> [branch]
set -e
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
KLIPPER_DIR="${1:?klipper directory}"
BASE="${2:?base commit}"
BRANCH="${3:-lerdge}"
rm -f "$REPO_DIR"/patches/*.patch
git -C "$KLIPPER_DIR" format-patch -q -o "$REPO_DIR/patches" "$BASE..$BRANCH"
ls "$REPO_DIR/patches"
