#!/bin/sh
# jevos entrypoint -- assembles `jev serve` from env so the Railway deploy form
# can tweak runtime knobs. Blank = release default (blank threads = auto all
# CPUs; blank ctx = 8192). JEV_API_KEY is read by the binary itself (empty = no auth).
# POSIX sh -- works under dash AND bash.
set -eu

port="${PORT:-8080}"
extra=""
[ -n "${JEV_THREADS:-}" ] && extra="${extra} --threads ${JEV_THREADS}"
[ -n "${JEV_CTX:-}"     ] && extra="${extra} --ctx ${JEV_CTX}"
warm=""
[ "${JEV_WARMUP:-1}" != "0" ] && warm="--warmup 384"

echo "[jevos] jevos-v3 port=${port} threads=${JEV_THREADS:-auto} ctx=${JEV_CTX:-8192} auth=${JEV_API_KEY:+set}"
exec /opt/jev/jev serve --host 0.0.0.0 --port "${port}" --model-dir /opt/jev/model ${extra} ${warm}
