#!/usr/bin/env bash
# Runs the headless Godot suites and the server tests ONE COMMAND AT A TIME, printing before/after progress lines around each.
# Usage: tools/run_suites.sh <overall_percent> <phase_task> [suite ...]     (no suites = all)
# No suite reaches the network: headless runs disable RunSync, and the backend tests use a scripted fake transport.
PCT="$1"; TASK="$2"; shift 2
GD="D:/Godot/editor/Godot_v4.7.2-stable_mono_win64/Godot_v4.7.2-stable_mono_win64_console.exe"
cd "$(dirname "$0")/.." || exit 2
SUITES=("$@")
[ ${#SUITES[@]} -eq 0 ] && SUITES=(startup_tests menu_tests audio_tests ui_tests layout_tests pause_tests failure_tests timer_tests rhythm_tests speed_tests integration_tests progression_tests experience_tests fx_tests modes_tests account_tests backend_tests online_ui_tests)
fails=0
for s in "${SUITES[@]}"; do
  echo "Overall: ${PCT}% | Phase/task: ${TASK} | Purpose: run headless suite ${s} | Expected: 0 failed"
  timeout 290 "$GD" --headless --path . "res://tests/${s}.tscn" > "/tmp/${s}.out" 2>&1; code=$?
  line=$(grep -E '==== .*checks' "/tmp/${s}.out" | head -1 | sed 's/====//g'); bad=$(grep -c '  FAIL' "/tmp/${s}.out")
  echo "Result: ${s} exit=${code} ${line} | FAIL lines=${bad} | Overall: ${PCT}% (no new criterion verified by this command alone)"
  [ "$code" -ne 0 ] && fails=$((fails+1))
done
echo "Overall: ${PCT}% | Phase/task: ${TASK} | Purpose: run difficulty logic tests (run_tests.gd) | Expected: ALL TESTS PASSED"
timeout 200 "$GD" --headless --path . -s res://tests/run_tests.gd > /tmp/rt.out 2>&1; code=$?
echo "Result: run_tests exit=${code} $(grep -E 'FAIL|PASSED' /tmp/rt.out | head -2 | tr '\n' ' ') | Overall: ${PCT}%"
[ "$code" -ne 0 ] && fails=$((fails+1))
echo "Overall: ${PCT}% | Phase/task: ${TASK} | Purpose: run server SQL tests on PostgreSQL 18 (PGlite) | Expected: 89 checks, 0 failed"
(cd server && timeout 200 node test_schema.mjs > /tmp/sql.out 2>&1); code=$?
echo "Result: server tests exit=${code} $(grep -E '==== .*checks' /tmp/sql.out | sed 's/====//g') | Overall: ${PCT}%"
[ "$code" -ne 0 ] && fails=$((fails+1))
echo "SUMMARY: ${fails} command(s) exited non-zero"
exit $fails
