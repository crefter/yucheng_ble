#!/usr/bin/env python3
"""Run actual scan/connect methods with SDK doubles, optionally from a Git ref."""
from pathlib import Path
import subprocess, tempfile, sys
repo = Path(__file__).resolve().parents[1]
core = (subprocess.check_output(['git', 'show', sys.argv[1] + ':ios/Classes/YuchengCore.swift'], cwd=repo, text=True)
        if len(sys.argv) > 1 else (repo / 'ios/Classes/YuchengCore.swift').read_text())
start = core.find('    static func normalizedConnectionMAC(')
if start < 0: start = core.index('    func scanDevices(')
methods = core[start:core.index('    func disconnect(')]
host = (subprocess.check_output(['git', 'show', sys.argv[1] + ':ios/Classes/YuchengHostApiImpl.swift'], cwd=repo, text=True)
        if len(sys.argv) > 1 else (repo / 'ios/Classes/YuchengHostApiImpl.swift').read_text())
host_method = host[host.index('    func isDeviceConnected('):host.index('    func connect(')] + host[host.index('    func getCurrentConnectedDevice('):host.index('    func getDefaultStartAndEndDate(')]
host_method = host_method.replace('let timeoutForGetDevice = 5.0', 'let timeoutForGetDevice = 0.01')
scenarios = ['same_name_wrong_connected', 'stale_same_name', 'internal_exact', 'external_exact', 'normalized', 'missing_id', 'invalid_id', 'scan_distinct_mac', 'scan_same_mac', 'scan_preserves_connected', 'wrong_callback', 'matching_connected', 'host_other_mac', 'host_offline', 'host_nil', 'host_normalized', 'host_nil_offline', 'reconnect_wrong', 'reconnect_nil', 'reconnect_normalized', 'reconnect_offline', 'reconnect_wrong_callback', 'getter_live_no_cache', 'getter_live_stale_cache', 'getter_offline_candidate', 'getter_nil_once', 'reconnect_cached_nil', 'reconnect_ota_canonical']
with tempfile.TemporaryDirectory(prefix='yucheng-transfer-') as directory:
 p = Path(directory)
 main = (repo/'ios/Tests/PhoneTransfer/main.swift').read_text().replace('// PRODUCTION_METHODS', methods).replace('// HOST_METHOD', host_method)
 (p/'main.swift').write_text(main)
 subprocess.run(['swiftc','-swift-version','5',str(repo/'ios/Classes/utils/Completer.swift'),str(p/'main.swift'),'-o',str(p/'test')], check=True)
 failures=[]
 for case in scenarios:
  result=subprocess.run([str(p/'test'),case],text=True,capture_output=True,timeout=4)
  print(('FAIL ' if result.returncode else 'PASS ')+case)
  if result.returncode: failures.append(case)
 print(f'{len(scenarios)-len(failures)}/{len(scenarios)} passed')
 sys.exit(bool(failures))
