#!/bin/bash
# Icinga plugin to monitor LV state on IBM AIX
#
# The plugin expects all LVs to be open and syncd,
# except for boot, which can be closed.
#
# Example:
#
#  [OK] 12 LVs found
#  [OK] rootvg/hd5: boot N/A (closed/syncd)
#  [OK] rootvg/hd6: paging N/A (open/syncd)
#  [OK] rootvg/hd8: jfs2log N/A (open/syncd)
#  [OK] rootvg/hd4: jfs2 / (open/syncd)
#  [OK] rootvg/hd2: jfs2 /usr (open/syncd)
#  [OK] rootvg/hd9var: jfs2 /var (open/syncd)
#  [OK] rootvg/hd3: jfs2 /tmp (open/syncd)
#  [OK] rootvg/hd1: jfs2 /home (open/syncd)
#  [OK] rootvg/hd10opt: jfs2 /opt (open/syncd)
#  [OK] rootvg/hd11admin: jfs2 /admin (open/syncd)
#  [OK] rootvg/lg_dumplv: sysdump N/A (open/syncd)
#  [OK] rootvg/livedump: jfs2 /var/adm/ras/livedump (open/syncd)
#
# References:
# - https://www.ibm.com/docs/en/aix/7.2?topic=l-lslv-command
# - https://www.ibm.com/docs/en/aix/7.2?topic=l-lsvg-command
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

output=""

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

if ! vg_raw="$(lsvg -L)"; then
  error "Could not scan for vgs"
fi

for vg in $vg_raw; do
  vgs+=("$vg")
done

overall=0
count=0
problems=0

for vg in "${vgs[@]}"; do
  # Scan the LV listing for this VG
  while read -ra lv; do
    if [[ ${#lv[@]} -eq 1 ]]; then
      # this contains the name of the vg -  we skip it
      continue
    fi

    if [[ "${lv[0]}" == "LV" ]]; then # && [[ "${lv[1]}" == "NAME" ]]; then
      # just a header
      continue
    fi

    lv="${lv[0]}"
    lv_type="${lv[1]}"
    num_lp="${lv[2]}"
    num_pp="${lv[3]}"
    num_pv="${lv[4]}"
    lv_state="${lv[5]}"
    active="${lv[5]%/*}"
    mirror="${lv[5]#*/}"
    mountpoint="${lv[6]}"

    state=0
    line="${vg}/${lv}: ${lv_type} ${mountpoint}"

    # check alignment
    align=$(expr $num_pp / $num_lp)
    if [[ $align -gt 1 ]] &&  [[ $align -ne $num_lp ]]; then
      line+=" LV mirroring is misaligned!"
      state=1
    fi

    # check if all volumes are opened - apart from boot
    if [[ "$lv_type" != "boot" ]] && [[ "$active" != open ]]; then
      line+=" LV is not opened!"
      state=1
    fi

    if [[ "$mirror" != syncd ]]; then
      line+=" LV is not in sync!"
      state=2
    fi

    line+=" (${lv_state})"

    count="$(expr $count + 1)"
    if [[ $state -gt 0 ]]; then
      problems="$(expr $problems + 1)"
    fi

    output+="$(badge $state) ${line}\n"
    overall="$(worst_state $overall $state)"
  done < <(lsvg -L -l "$vg")
done

# print output
echo -n "$(badge $overall) $count LVs found"
if [[ $problems -gt 0 ]]; then
  echo -n " - $problems problems!"
fi

echo
echo -e "$output"

exit $overall
