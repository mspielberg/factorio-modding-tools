#!/bin/sh
grep 'do local _' "$1" |sed 's/^.*: do local/do local/' > 'data-raw.lua'