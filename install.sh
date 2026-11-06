#!/usr/bin/env bash
# install.sh — puts the `tinker` command on your PATH. Safe to run again (idempotent).
# It only creates one symlink: ~/.local/bin/tinker → <this repo>/bin/tinker.
# No sudo. It never edits your shell config files; if ~/.local/bin isn't on your PATH it prints
# the one line to add yourself.
set -euo pipefail
REPO=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)
BIN_DIR=${TINKER_BIN_DIR:-$HOME/.local/bin}
TARGET=$REPO/bin/tinker
LINK=$BIN_DIR/tinker

chmod +x "$REPO"/bin/tinker "$REPO"/bin/tinker-* "$REPO"/bin/gate.sh "$REPO"/fleet/*.sh "$REPO"/runners/*.sh \
  "$REPO"/templates/experiment/run.sh 2>/dev/null || true
mkdir -p "$REPO/projects" "$BIN_DIR"

if [ -L "$LINK" ] && [ "$(readlink "$LINK")" = "$TARGET" ]; then
  echo "install: $LINK already points here — nothing to do."
elif [ -e "$LINK" ] && [ ! -L "$LINK" ]; then
  echo "install: $LINK exists and is not a symlink; leaving it alone." >&2
  echo "  Remove it yourself, or run $TARGET directly." >&2
  exit 1
else
  ln -sfn "$TARGET" "$LINK"
  echo "install: linked $LINK → $TARGET"
fi

case ":$PATH:" in
  *":$BIN_DIR:"*) echo "install: $BIN_DIR is on your PATH. Try: tinker doctor" ;;
  *)
    echo
    echo "One more step: $BIN_DIR is not on your PATH. Add this line to your shell config"
    echo "(~/.bashrc, ~/.zshrc, …), then open a new terminal:"
    echo
    echo "    export PATH=\"$BIN_DIR:\$PATH\""
    echo
    echo "Then run: tinker doctor"
    ;;
esac
