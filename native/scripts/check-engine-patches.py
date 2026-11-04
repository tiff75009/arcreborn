#!/usr/bin/env python3
"""Verify stacked engine patches in a scratch tree, never revert live sources."""
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile


def verify(source, patches):
    with tempfile.TemporaryDirectory(prefix='browser-engine-patches-') as temporary:
        scratch = Path(temporary)
        for patch in patches:
            for line in patch.read_text().splitlines():
                if not line.startswith('+++ b/'):
                    continue
                relative = Path(line[6:])
                if relative.is_absolute() or '..' in relative.parts:
                    raise ValueError('Unsafe patch path')
                destination = scratch / relative
                if not destination.exists():
                    destination.parent.mkdir(parents=True, exist_ok=True)
                    shutil.copyfile(source / relative, destination)
        # Later patches may extend the EOF context of earlier patches. Reverse
        # them in order on copies; individual --reverse --check calls are wrong.
        for patch in reversed(patches):
            subprocess.run(['/usr/bin/git', 'apply', '--reverse', str(patch.resolve())],
                           cwd=scratch, check=True)


if __name__ == '__main__':
    verify(Path(sys.argv[1]), [Path(value) for value in sys.argv[2:]])
