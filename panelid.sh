#!/bin/zsh
# panelid.sh — read the internal LCD panel identity record (from DCP, no privilege).
# Run on a known-genuine Mac and on a suspect Mac, then compare.
raw=$(ioreg -lw0 -r -n disp0 2>/dev/null | /usr/bin/grep -m1 'Panel_ID' | /usr/bin/sed -E 's/.*"Panel_ID" = "([^"]*)".*/\1/')

if [[ -z "$raw" ]]; then
  print -- "Panel_ID : <ABSENT>   <-- no panel identity published (strong SUSPECT signal)"
  exit 2
fi

print -- "Panel_ID (raw, ${#raw} chars):"
print -- "  $raw"
print --
print -- "Fields (split on '+'):"
i=0
typeset -a F
IFS='+' read -rA F <<< "$raw"
for f in "${F[@]}"; do
  printf "  [%d] len=%-3d %s\n" "$i" "${#f}" "$f"
  i=$((i+1))
done

pserial="${F[1]}"         # zsh arrays are 1-based -> field [0]
pstatus="${F[3]}"         # field [2]
print --
print -- "Serial-number field [0] : $pserial"
print -- "Build/status field  [2] : $pstatus"

# --- heuristic genuine check ---
zeros=$(print -- "$pserial" | tr -d '0')
verdict="LIKELY GENUINE"
[[ "$pstatus" != PROD* ]] && verdict="SUSPECT (status field is not PROD)"
[[ -z "$zeros" ]]         && verdict="SUSPECT (serial field is all zeros)"
[[ ${#pserial} -lt 8 ]]   && verdict="SUSPECT (serial field too short)"
print -- "Heuristic verdict       : $verdict"
