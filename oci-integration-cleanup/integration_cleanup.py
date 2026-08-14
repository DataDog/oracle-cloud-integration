#!/usr/bin/env python3
"""Responsibility: preserve the public cleanup API and executable script path.

Safety boundary: contains no cleanup logic; all validation and mutation gates
remain in the focused ``oci_cleanup`` implementation modules.
Cleanup sequence role: re-exports the supported API and delegates execution to
``oci_cleanup.cli.main``.

Imports from this facade remain the compatibility surface for callers and tests,
while direct invocation forwards arguments and exit status to the package CLI.
"""

from __future__ import annotations

import sys

from oci_cleanup import *  # noqa: F401,F403
from oci_cleanup import __all__

if __name__ == "__main__":
    sys.exit(main())
