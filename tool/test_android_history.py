#!/usr/bin/env python3
"""Run real native history/background methods on JVM with SDK/HTTP doubles.

Requires the project's Kotlin compiler/coroutines artifacts in the Gradle cache.
Does not change Gradle, Flutter, production checkouts, or the pub cache.
"""
from pathlib import Path
import os
import subprocess
import tempfile

repo = Path(__file__).resolve().parents[1]
source = repo / 'android/src/main/kotlin/com/crefter/yuchengplugin/yucheng_ble'
cache = Path.home() / '.gradle/caches/modules-2/files-2.1'
def jar(group, artifact, version):
    return next((cache / group / artifact / version).glob('*/*.jar'))
java = Path(os.environ.get('JAVA_HOME', '/Applications/Android Studio.app/Contents/jbr/Contents/Home')) / 'bin/java'
stdlib = jar('org.jetbrains.kotlin', 'kotlin-stdlib', '2.4.10')
coroutines = jar('org.jetbrains.kotlinx', 'kotlinx-coroutines-core-jvm', '1.9.0')
annotations = jar('org.jetbrains', 'annotations', '23.0.0')
compiler = [jar('org.jetbrains.kotlin', 'kotlin-compiler-embeddable', '2.4.10'), stdlib, coroutines, annotations,
            jar('org.jetbrains.kotlin', 'kotlin-script-runtime', '2.4.10'),
            jar('org.jetbrains.kotlin', 'kotlin-reflect', '1.9.24')]
core = (source / 'YuchengCore.kt').read_text()
start = core.find('    private suspend fun <T> readHistory(')
if start < 0: start = core.index('    suspend fun getSleepData(')
methods = core[start:core.index('    fun isConnected()', start)].replace('1000 * TIME_TO_TIMEOUT', '60L')
service = (source / 'service/YuchengBleService.kt').read_text()
service = service[service.index('    @OptIn(FlowPreview::class)'):service.index('    @RequiresApi(Build.VERSION_CODES.O)\n    override fun onStartCommand')]
service = service.replace('private suspend fun ', 'suspend fun ')
repository = (source / 'data/remote/YuchengRepository.kt').read_text()
repository = repository[repository.index('    @RequiresApi(Build.VERSION_CODES.O)\n    suspend fun saveSleep('):]
api = (source / 'YuchengApiImpl.kt').read_text()
deletes = api[api.index('    @OptIn(DelicateCoroutinesApi::class)\n    private suspend fun deleteData('):api.index('    @OptIn(DelicateCoroutinesApi::class)\n    override fun deleteAllData(')]
deletes = deletes.replace('override fun ', 'fun ').replace('1000 * TIME_TO_TIMEOUT', '60L')
with tempfile.TemporaryDirectory(prefix='yucheng-android-history-') as temp:
    temp = Path(temp)
    safety = source / 'HistoryReadSafety.kt'
    safety_text = safety.read_text().split('\n', 1)[1] if safety.exists() else ''
    (temp / 'Production.kt').write_text('import kotlinx.coroutines.*\nimport java.io.IOException\nimport java.util.concurrent.TimeoutException\nimport java.time.ZonedDateTime\nimport java.util.concurrent.atomic.AtomicBoolean\n' + safety_text + '''
object YuchengCore {
 const val YUCHENG_API="test"; const val GET_SLEEP_DATA="test"; const val GET_HEALTH_DATA="test"
 const val TIME_TO_TIMEOUT=1L
 var storage: Storage?=Storage(); var tokenStorage: TokenStorage?=TokenStorage()
 fun isConnected()=true
 suspend fun reconnect(unused: Any?, timeout: Int) {}
''' + methods + '''
}
class HistoryHost { val YUCHENG_API="test"; val TIME_TO_TIMEOUT=1L
''' + deletes + '''
}
class YuchengBleService {
 val YUCH_TAG="test"; var gson: Any?=Any(); var tokenIsNullCount=0
 val MAX_TOKEN_IS_NULL_COUNT=3; val STOP_FOREGROUND_REMOVE=1
 fun stopForeground(value: Int) {}; fun stopSelf() {}
''' + service + '\n}\nclass ProductionRepository(val apiClient: OkHttpClient, val apiConfig: YuchengApiConfig) {\nval TAG_SLEEP="test"; val TAG_HEALTH="test"; val gson=GsonBuilder().create()\n' + repository)
    (temp / 'Main.kt').write_text((repo / 'android/src/test/history/Main.kt').read_text())
    cp = ':'.join(map(str, [stdlib, coroutines, annotations]))
    subprocess.run([str(java), '-cp', ':'.join(map(str, compiler)), 'org.jetbrains.kotlin.cli.jvm.K2JVMCompiler',
                    '-no-stdlib', '-no-reflect', '-jvm-target', '17', '-classpath', cp,
                    str(temp / 'Production.kt'), str(temp / 'Main.kt'), '-d', str(temp / 'test.jar')], check=True)
    subprocess.run([str(java), '-cp', str(temp / 'test.jar') + ':' + cp, 'MainKt'], check=True, timeout=30)
