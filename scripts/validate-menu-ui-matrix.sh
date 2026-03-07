#!/bin/bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BASELINE_DIR="${PROJECT_DIR}/Tests/MenuSnapshots/Baseline"
SNAPSHOT_DIR="${PROJECT_DIR}/artifacts/menu-previews"
DIFF_DIR="${PROJECT_DIR}/artifacts/menu-diffs"
WRITE_BASELINE="0"
THRESHOLD="0.003"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --write-baseline)
            WRITE_BASELINE="1"
            shift
            ;;
        --threshold)
            THRESHOLD="${2}"
            shift 2
            ;;
        *)
            echo "Unknown argument: $1" >&2
            echo "Usage: ./scripts/validate-menu-ui-matrix.sh [--write-baseline] [--threshold 0.003]" >&2
            exit 2
            ;;
    esac
done

SCENARIOS=(trial active expired invalid)
APPEARANCES=(light dark)

mkdir -p "${SNAPSHOT_DIR}" "${DIFF_DIR}"

if [[ "${WRITE_BASELINE}" == "1" ]]; then
    mkdir -p "${BASELINE_DIR}"
fi

failures=0
missing=0

for scenario in "${SCENARIOS[@]}"; do
    for appearance in "${APPEARANCES[@]}"; do
        name="menu-${scenario}-${appearance}.png"
        snapshot_path="${SNAPSHOT_DIR}/${name}"
        baseline_path="${BASELINE_DIR}/${name}"
        diff_path="${DIFF_DIR}/${name}"

        "${PROJECT_DIR}/scripts/validate-menu-ui.sh" "${scenario}" "${appearance}"

        if [[ "${WRITE_BASELINE}" == "1" ]]; then
            cp "${snapshot_path}" "${baseline_path}"
            echo "baseline updated: ${baseline_path}"
            continue
        fi

        if [[ ! -f "${baseline_path}" ]]; then
            echo "missing baseline: ${baseline_path}"
            missing=$((missing + 1))
            continue
        fi

        if swift "${PROJECT_DIR}/scripts/compare-menu-snapshots.swift" \
            "${baseline_path}" \
            "${snapshot_path}" \
            "${diff_path}" \
            "${THRESHOLD}"; then
            echo "match: ${name}"
        else
            status=$?
            if [[ ${status} -eq 1 ]]; then
                echo "mismatch: ${name} (see ${diff_path})"
                failures=$((failures + 1))
            else
                echo "comparison failed: ${name}" >&2
                exit ${status}
            fi
        fi
    done
done

if [[ ${missing} -gt 0 ]]; then
    echo "missing baselines: ${missing}" >&2
    exit 3
fi

if [[ ${failures} -gt 0 ]]; then
    echo "snapshot mismatches: ${failures}" >&2
    exit 1
fi

echo "all menu snapshots matched baseline"
