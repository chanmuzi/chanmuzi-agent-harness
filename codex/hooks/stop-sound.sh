#!/bin/bash
# Compatibility shim for stale Codex Stop hook references.
# Fresh harness config does not register a Stop hook, but older sessions or
# cached app state may still invoke this path. Exit successfully without sound.
exit 0
