#!/usr/bin/env python3
"""Compile production history methods/Completer; only SDK IO/types are doubled."""
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
import subprocess
import sys
import tempfile

repo = Path(__file__).resolve().parents[1]
core = (repo / 'ios/Classes/YuchengCore.swift').read_text()
host = (repo / 'ios/Classes/YuchengHostApiImpl.swift').read_text()
deletes = host[host.index('    func deleteSleepData('):host.index('    func deleteAllData(')]
methods = core[core.index('    func getSleepData('):core.index('    func otaUpdate(')]
scenarios = sys.argv[1:] or [
    'sleep_success', 'sleep_empty', 'sleep_no_record', 'sleep_error', 'sleep_timeout',
    'sleep_late', 'sleep_duplicate', 'sleep_cancel', 'sleep_invalid',
    'health_success', 'health_empty', 'health_no_record', 'health_error', 'health_timeout',
    'health_partial_error', 'sport_partial_error', 'health_partial_timeout', 'sport_partial_timeout',
    'health_empty_error', 'health_late', 'health_duplicate', 'health_cancel', 'health_invalid',
]
with tempfile.TemporaryDirectory(prefix='yucheng-ios-history-') as work:
    work = Path(work)
    (work / 'main.swift').write_text((repo / 'ios/Tests/HistoryRead/main.swift').read_text())
    (work / 'HistoryCore.swift').write_text(
        'import Foundation\nimport Combine\nclass YuchengCore {\n'
        'static let shared = YuchengCore()\nstatic let TIME_TO_TIMEOUT = 0.04\n'
        'var currentDevice: Device? = nil\nfunc isConnected() -> Bool { true }\n'
        'func getDefaultStartAndEndDate() -> (start: Int64, end: Int64) { (0, 100) }\n'
        + methods + '\n}\nclass HistoryHost {\n' + deletes + '\n}\n'
    )
    subprocess.run(['swiftc', '-swift-version', '5',
                    str(repo / 'ios/Classes/utils/Completer.swift'),
                    str(repo / 'ios/Classes/utils/HistoryReadSafety.swift'),
                    str(work / 'HistoryCore.swift'), str(work / 'main.swift'),
                    '-o', str(work / 'test')], check=True)
    def run(scenario):
        result = subprocess.run([str(work / 'test'), scenario], text=True, capture_output=True, timeout=4)
        return scenario, result.returncode, result.stdout + result.stderr
    failures = []
    with ThreadPoolExecutor(max_workers=4) as executor:
        for scenario, code, output in executor.map(run, scenarios):
            print(('FAIL ' if code else 'PASS ') + scenario)
            if code:
                failures.append(scenario)
                print(output)
    print(f'{len(scenarios) - len(failures)}/{len(scenarios)} passed')
    sys.exit(bool(failures))
