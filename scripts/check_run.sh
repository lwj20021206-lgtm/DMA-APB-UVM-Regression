#!/usr/bin/env bash
set -u

log_file=${1:?usage: check_run.sh LOG_FILE SIM_STATUS}
sim_status=${2:?usage: check_run.sh LOG_FILE SIM_STATUS}

if [[ ! -f "$log_file" ]]; then
  echo "FAIL: simulation log was not created: $log_file" >&2
  exit 1
fi

if [[ "$sim_status" -ne 0 ]]; then
  echo "FAIL: simulator exited with status $sim_status" >&2
  exit "$sim_status"
fi

if grep -q 'Simulation Failed\.' "$log_file"; then
  echo "FAIL: DUT reported 'Simulation Failed.'" >&2
  exit 1
fi

if grep -Eqi 'started at[^[:cntrl:]]*failed at|Error-\[(ASE|SVA[^]]*)\]|Assertion failure([[:space:]:]|$)' "$log_file"; then
  echo "FAIL: assertion failure found in simulation log" >&2
  exit 1
fi

if ! grep -Eq 'UVM_ERROR[[:space:]]*:[[:space:]]*0[[:space:]]*$' "$log_file"; then
  echo "FAIL: missing a zero UVM_ERROR summary" >&2
  exit 1
fi

if ! grep -Eq 'UVM_FATAL[[:space:]]*:[[:space:]]*0[[:space:]]*$' "$log_file"; then
  echo "FAIL: missing a zero UVM_FATAL summary" >&2
  exit 1
fi

echo "PASS: $log_file"
