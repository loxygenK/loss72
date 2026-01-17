#!/usr/bin/env bash

set -eu

function _deps {
  if ! which jq; then
    echo "  = Installing jq"
    curl -o $HOME/.local/bin/jq -L https://github.com/jqlang/jq/releases/download/jq-1.7/jq-linux64 && chmod +x $HOME/.local/bin/jq
  fi
}

function _github {
  curl --silent https://api.github.com/repos/loxygenK/loss72-platemaker$1
}

function _usage {
  echo "usage: ./build.sh <platemaker version>"
}

function _pull {
  _deps

  local latest_tag=$(_github /releases/latest | jq -r ".name")
  echo "  = Considering the tag $latest_tag"

  local commit_hash=$(_github /git/ref/tags/$latest_tag | jq -r ".object.sha")
  echo "  = $latest_tag points to $commit_hash"

  local verified=$(_github /commits/$commit_hash | jq -r ".commit.verification.verified")
  local signature=$(_github /commits/$commit_hash | jq -r ".commit.verification.signature")
  local payload=$(_github /commits/$commit_hash | jq -r ".commit.verification.payload")
  echo "  = Retrieved commit information"

  if [ "$verified" != "true" ]; then
    echo "[!] Cannot run platemaker from unverified commit"
    return 2
  fi

  curl --silent https://keybase.io/loxygenk/pgp_keys.asc | gpg --import

  echo "  = Verifying signature..."

  echo "$signature" > sig.asc
  echo "$payload" > payload

  gpg --verify --status-fd=1 sig.asc payload 2>&1 > gpg_log

  local considered_key=$(cat gpg_log | grep KEY_CONSIDERED | head -n 1 | awk '{ print $3 }')
  echo "  = Signed with key $considered_key"

  if [ "$considered_key" != "1899551DD3D1B9DB355AEF244698AEC661CCD81E" ]; then
    echo "[!] The commit is signed by the unexpected key"
    return 2
  fi

  echo "  = Release is trusted"

  mkdir bin 2>/dev/null || true
  local platemaker=./bin/platemaker
  curl -L https://github.com/loxygenK/loss72-platemaker/releases/download/$latest_tag/loss72-platemaker -o $platemaker

  chmod +x $platemaker
}

function _main {
  local platemaker=./bin/platemaker

  if [ "${@:-empty}" = "pull" ]; then
    _pull
    return 0
  fi

  if [ ! -f "$platemaker" ]; then
    _pull
  fi;

  mkdir dist 2> /dev/null || true

  if [ $# -eq 0 ]; then
    $platemaker build --release
  else
    $platemaker $@
  fi
}

_main $@

