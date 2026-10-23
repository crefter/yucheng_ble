#!/usr/bin/env python3
"""Run the production reconnect coroutine on JVM with deterministic SDK doubles.

Only Android/SDK boundaries are replaced. The reconnect method is extracted from
YuchengCore; seconds are scaled to 100 ms and its warm-up delay to 10 ms so timeout
and cancellation regressions run quickly. No Gradle or pub-cache edits are made.
"""
from pathlib import Path
import os
import re
import subprocess
import tempfile

repo = Path(__file__).resolve().parents[1]
source = repo / 'android/src/main/kotlin/com/crefter/yuchengplugin/yucheng_ble/YuchengCore.kt'
cache = Path.home() / '.gradle/caches/modules-2/files-2.1'


def jar(group, artifact, version):
    return next((cache / group / artifact / version).glob('*/*.jar'))


java_home = os.environ.get('JAVA_HOME')
if java_home is None:
    java_home = subprocess.check_output(['/usr/libexec/java_home'], text=True).strip()
java = Path(java_home) / 'bin/java'
stdlib = jar('org.jetbrains.kotlin', 'kotlin-stdlib', '2.2.20')
coroutines = jar('org.jetbrains.kotlinx', 'kotlinx-coroutines-core-jvm', '1.9.0')
annotations = jar('org.jetbrains', 'annotations', '23.0.0')
compiler = [jar('org.jetbrains.kotlin', 'kotlin-compiler-embeddable', '2.2.20'), stdlib, coroutines, annotations,
            jar('org.jetbrains.kotlin', 'kotlin-script-runtime', '2.2.20'),
            jar('org.jetbrains.kotlin', 'kotlin-reflect', '2.2.0')]
core = source.read_text()
attempt_state = '\n'.join(re.findall(r'^    private (?:val reconnectLock|var reconnectGeneration|var reconnectScanGeneration).*$', core, re.M))
reconnect = core[core.index('    suspend fun reconnect('):core.index('    fun disconnect()')]
reconnect = reconnect.replace('reconnectTimeInSeconds * 1000', 'reconnectTimeInSeconds * 100')
reconnect = reconnect.replace('delay(1000)', 'delay(10)')
reconnect = reconnect.replace('Dispatchers.Main', 'mainDispatcher')
scan = core[core.index('    suspend fun scanDevices('):core.index('    suspend fun connect(')]
scan = scan.replace('Dispatchers.Main', 'mainDispatcher').replace('* 1000', '* 100')
connected = core[core.index('    fun isConnected()'):core.index('\n}', core.index('    fun isConnected()'))]
with tempfile.TemporaryDirectory(prefix='yucheng-android-reconnect-') as temp:
    temp = Path(temp)
    (temp / 'Production.kt').write_text('''import kotlinx.coroutines.*
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.first
object YuchengCore {
 const val YUCHENG_API="test"; const val SCAN_PERIOD=20
 val scannedDevices=mutableSetOf<ScanDeviceBean>()
 val deviceIndex=Counter()
 var selectedDevice:YuchengDevice?=null
 val connectState=MutableStateFlow(3)
''' + attempt_state + '\n' + reconnect + scan + connected + '\n}\n')
    (temp / 'Main.kt').write_text((repo / 'android/src/test/reconnect/Main.kt').read_text())
    cp = ':'.join(map(str, [stdlib, coroutines, annotations]))
    subprocess.run([str(java), '-cp', ':'.join(map(str, compiler)), 'org.jetbrains.kotlin.cli.jvm.K2JVMCompiler',
                    '-no-stdlib', '-no-reflect', '-jvm-target', '17', '-classpath', cp,
                    str(temp / 'Production.kt'), str(temp / 'Main.kt'), '-d', str(temp / 'test.jar')], check=True)
    subprocess.run([str(java), '-cp', str(temp / 'test.jar') + ':' + cp, 'MainKt'], check=True, timeout=30)
