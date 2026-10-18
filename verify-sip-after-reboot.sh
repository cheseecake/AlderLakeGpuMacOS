#!/bin/bash
# Post-reboot verification — MyIntelGPU.kext SIP unblock
# รันหลัง reboot:  bash /Users/ppbk/irepo-build/verify-sip-after-reboot.sh
export PAGER=cat
OCGUID="7C436110-AB2A-4BBB-A880-FE41995C9F82"
OCVER="4D1FDA02-38C7-4A6A-9CC6-4BCCA8B30102:opencore-version"
pass=0; fail=0
chk(){ if eval "$2" >/dev/null 2>&1; then echo "PASS  $1"; pass=$((pass+1)); else echo "FAIL  $1"; fail=$((fail+1)); fi }

echo "=== S1: SIP off ==="
echo "--- csrutil status ---"; csrutil status
chk "S1a csrutil = disabled"        'csrutil status | grep -qi disabled'
echo "--- nvram csr-active-config ---"; nvram csr-active-config 2>&1
chk "S1b nvram csr-active-config exists" 'nvram csr-active-config'

echo
echo "=== S1: OC actually ran this boot ==="
echo "--- opencore-version ---"; nvram "$OCVER" 2>&1
chk "S1c OC wrote opencore-version"  'nvram "'"$OCVER"'"'
echo "--- nvram boot-args ---"; nvram boot-args 2>&1
chk "S1d nvram boot-args applied"    'nvram boot-args'

echo
echo "=== S1: kext loaded ==="
echo "--- kmutil showloaded | grep myintel ---"; kmutil showloaded 2>&1 | grep -i myintel
chk "S1e kext 3.1.130 loaded"        'kmutil showloaded 2>/dev/null | grep -i myintel | grep -q 3.1.130'

echo
echo "=== S3: no accelerator probe / no WS crash ==="
LATEST=$(ls -t /Volumes/EFI-SPARE/opencore-*.txt 2>/dev/null | head -1)
echo "--- newest OC/boot log: $LATEST ---"
[ -n "$LATEST" ] && grep -aoE "EB\.CSR\.S\|VAR\] 0x[0-9A-Fa-f]+|EB\|CSR:OUT\] 0x[0-9A-Fa-f]+" "$LATEST" | head -4
chk "S3a log shows csr VAR 0x0FFF"   '[ -n "'"${LATEST:-}"'" ] && grep -aq "CSR.S|VAR] 0x00000FFF" "$LATEST"'
PROBE_PRED_KERNEL_ONLY='sender == "kernel" AND eventMessage CONTAINS "PROBE TRIGGERED"'
PROBE_N=$(log show --last 90m --predicate "$PROBE_PRED_KERNEL_ONLY" 2>/dev/null | grep -c "PROBE TRIGGERED")
echo "--- PROBE TRIGGERED lines (kernel only): $PROBE_N ---"
chk "S3b no PROBE TRIGGERED"         '[ "$PROBE_N" -eq 0 ]'
echo "--- recent WindowServer crashes ---"
ls -t ~/Library/Logs/DiagnosticReports/WindowServer-*.ips 2>/dev/null | head -3

echo
echo "=================== RESULT: $pass PASS / $fail FAIL ==================="
echo "Rollback (ถ้าต้องการคืน config):"
echo "  cp /Volumes/EFI-SPARE/EFI/OC/Config.plist.bak-20261012-063843 /Volumes/EFI-SPARE/EFI/OC/Config.plist"
