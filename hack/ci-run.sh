#!/usr/bin/env bash
# ci-run.sh NAME COMMAND...: runs COMMAND in core/, the source, with its
# output kept off this public log. The output goes to a file, which is
# encrypted with age to LOG_RECIPIENT (whose key is kept with the source) as
# logs/NAME.log.age, the job's artifact. The log says only whether the
# command passed.
set -uo pipefail
name=$1
shift
plain="$RUNNER_TEMP/$name.log"
(cd core && "$@") > "$plain" 2>&1
code=$?
mkdir -p logs
if ! go run filippo.io/age/cmd/age@v1.3.2 -r "$LOG_RECIPIENT" -o "logs/$name.log.age" "$plain"; then
  echo "::warning::$name: its log could not be encrypted, and is not kept"
fi
rm -f "$plain"
if [ "$code" -eq 0 ]; then
  echo "$name: passed"
else
  echo "::error::$name failed (exit $code); its log is this run's artifact log-$name, encrypted"
fi
exit "$code"
