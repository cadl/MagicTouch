#!/bin/sh
set -eu
cd "${CI_PRIMARY_REPOSITORY_PATH:?Xcode Cloud checkout path is required}"
python3 ci_scripts/configure_build.py
