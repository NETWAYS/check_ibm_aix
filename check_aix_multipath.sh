#!/bin/bash
# Icinga plugin to monitor physical disk paths on IBM AIX
#
# When less than 50% paths are down, WARNING is the result.
# For more paths CRITICAL is returned.
#
# Example:
#  [OK] 1 disks, 2 paths
#  [OK] hdisk0: 2 paths
#
# References:
# - https://www.ibm.com/docs/en/aix/7.2?topic=l-lspath-command
#
# Copyright (C) 2021 NETWAYS GmbH <info@netways.de>
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <https://www.gnu.org/licenses/>.

set -eo pipefail

error() {
  echo "UNKNOWN" "$@"
  exit 3
}

worst_state() {
  local overall=-1
  local s

  for s in "$@"; do
    if [[ $s -eq 2 ]]; then
      overall=2
    elif [[ $s -eq 3 ]]; then
      if [[ $overall -ne 2 ]]; then
        overall=3
      fi
    elif [[ $s -gt $overall ]]; then
      overall=$s
    fi
  done

  if [[ $overall -lt 0 ]] || [[ $overall -gt 3 ]]; then
    overall=3
  fi

  echo $overall
}

badge() {
  case "$1" in
  0)
    echo "[OK]"
    ;;
  1)
    echo "[WARNING]"
    ;;
  2)
    echo "[CRITICAL]"
    ;;
  *)
    echo "[UNKNOWN]"
  esac
}

containsElement () {
  local e match="$1"
  shift
  for e; do [[ "$e" == "$match" ]] && return 0; done
  return 1
}

# Load path info
if ! path_info="$(lspath -F"name parent status")"; then
  error "Could not list paths"
fi

# Extract disks from path
while read -ra path; do
  name="${path[0]}"

  if ! containsElement "${path[0]}" "${pvs[@]}"; then
    pvs+=("$name")
  fi
done <<<"$path_info"

output=""
overall=0
count=0
paths=0
problems=0

process_disk() {
  count="$(expr $count + 1)"

  line="${current_disk}: ${paths_total} paths"

  state=0

  if [[ "${#paths_inactive[@]}" -gt 0 ]]; then
    down_pct="$(bc <<<"100 / $paths_total * ${#paths_inactive[@]}")"

    if [[ $down_pct -lt 50 ]]; then
      state=1
    else
      state=2
    fi

    line+=", ${#paths_inactive[@]} paths are not enabled: ${paths_inactive[*]}"
  fi

  if [[ $state -gt 0 ]]; then
    problems="$(expr $problems + 1)"
  fi

  output+="$(badge $state) ${line}\n"
  overall="$(worst_state $overall $state)"
}

while read -ra path; do
  disk="${path[0]}"
  path="${path[1]}"
  path_state="${path[2]}"

  if [[ "$current_disk" != "$disk" ]]; then
    if [[ -n "$current_disk" ]]; then
      process_disk
    fi

    current_disk="$disk"
    paths_total=0
    paths_inactive=()
  fi

  paths_total="$(expr $paths_total + 1)"
  if [[ "$path_state" != "Enabled" ]]; then
    paths_inactive+=("$path")
  fi

  paths="$(expr $paths + 1)"
done <<<"$path_info"

process_disk # the last one

# print output
echo -n "$(badge $overall) $count disks, $paths paths"
if [[ $problems -gt 0 ]]; then
  echo -n " - $problems problems!"
fi

echo
echo -e "$output"

exit $overall
