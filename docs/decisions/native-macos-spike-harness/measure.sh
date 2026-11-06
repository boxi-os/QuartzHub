#!/bin/zsh
# measure.sh <label> <owner-name> <pattern-for-pgrep> <command...>
label=$1; owner=$2; pat=$3; shift 3
S=${0:h}
start=$(perl -MTime::HiRes=time -e 'printf "%.3f", time')
"$@" > /dev/null 2>&1 &
for i in {1..300}; do
  if $S/owners | grep -q "^$owner "; then break; fi
  sleep 0.05
done
end=$(perl -MTime::HiRes=time -e 'printf "%.3f", time')
sleep 10
rss=$(ps -axo rss=,command= | grep -F "$pat" | grep -v grep | awk '{s+=$1} END {print s}')
n=$(ps -axo command= | grep -F "$pat" | grep -v grep | wc -l | tr -d ' ')
sleep 0; printf "%s: window after %.2f s, %d processes, RSS %.0f MB (10 s idle)\n" $label $(( end - start )) $n $(( rss / 1024.0 ))
