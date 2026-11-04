#!/bin/zsh
# Serves screenshot requests from the UI test: req/<name> contains a delay in seconds.
D=${0:a:h}
while true; do
  for f in $D/req/*(N); do
    n=${f:t}; d=$(cat $f); sleep ${d:-0}
    xcrun simctl io $(cat $D/../udid) screenshot --type=png $D/shots/$n-$(cat $D/mode).png >/dev/null 2>&1
    rm -f $f
  done
  sleep 0.1
done
