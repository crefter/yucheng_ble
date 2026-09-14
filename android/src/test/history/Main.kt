import kotlinx.coroutines.*
import java.util.concurrent.atomic.AtomicInteger

annotation class RequiresApi(val value: Int)
object Build { const val ID="test"; object VERSION { const val SDK_INT=36 }; object VERSION_CODES { const val O=26 } }
object Log { fun d(tag:String, value:String) {}; fun i(tag:String, value:String) {}; fun e(tag:String, value:String) {} }
class NoConnectionException: Exception()
data class YuchengSleepData(val startTimeStamp:Long=10,val endTimeStamp:Long=20)
data class YuchengSportData(val startTimeStamp:Long=10,val endTimeStamp:Long=20,val steps:Long=1,val calories:Long=1,val distance:Long=1) { val startDate get()=java.time.LocalDate.now() }
data class YuchengHealthData(val startTimestamp:Long=10)
data class YuchengHealthSportData(val healthData:List<YuchengHealthData>,val sportData:List<YuchengSportData>)
interface YuchengSleepEvent
interface YuchengHealthEvent
class YuchengSleepDataEvent(val sleepData:YuchengSleepData):YuchengSleepEvent
class YuchengSleepTimeOutEvent(val isTimeout:Boolean):YuchengSleepEvent
class YuchengHealthDataEvent(val healthData:YuchengHealthSportData):YuchengHealthEvent
class YuchengHealthTimeOutEvent(val isTimeout:Boolean):YuchengHealthEvent
class YuchengSleepDataConverter(val gson:Any?=null) { fun convert(value:Any?):YuchengSleepData { check(value != "bad"); return YuchengSleepData() } }
class YuchengSportDataConverter(val gson:Any?=null) { fun convert(value:Any?):YuchengSportData { check(value != "bad"); return YuchengSportData() } }
class YuchengHealthDataConverter(val gson:Any?=null) { fun convert(value:Any?):YuchengHealthData { check(value != "bad"); return YuchengHealthData() } }
object Constants { object DATATYPE { const val Health_HistorySleep=1; const val Health_HistorySport=2; const val Health_HistoryAll=3; const val Health_DeleteSleep=4; const val Health_DeleteSport=5; const val Health_DeleteAll=6 } }
object YCBTClient {
 val scope=CoroutineScope(Dispatchers.Default+SupervisorJob())
 val modes=mutableMapOf<Int,String>(); val reads=mutableListOf<Int>(); val deletes=mutableListOf<Int>()
 fun healthHistoryData(type:Int, callback:(Int,Float,HashMap<String,Any>?) -> Unit) {
   synchronized(reads) { reads.add(type) }
   val mode=modes[type] ?: "success"
   if(mode=="throw") throw IllegalStateException("injected SDK failure")
   if(mode=="timeout") return
   scope.launch {
     delay(if(mode=="late") 150L else 3L)
     val data=if(mode=="null") null else hashMapOf<String,Any>("data" to if(mode=="empty") emptyList<String>() else listOf(if(mode=="bad") "bad" else "sample"))
     try { callback(if(mode=="error") 7 else 0,0f,data); if(mode=="duplicate") callback(0,0f,data) } catch (e:Exception) { /* Old code lets converter exceptions escape SDK thread. */ }
   }
 }
 fun deleteHealthHistoryData(type:Int, callback:(Int,Float,HashMap<String,Any>?) -> Unit) { deletes.add(type); callback(0,0f,null) }
}
class Storage { fun readFlavor()="test" }
class TokenStorage { fun getToken(flavor:Any)="dummy" }
object YuchengFlavor { fun fromString(value:String)="test" }
object YuchengInternetChecker { suspend fun hasInternet(client:Any)=true }
object ApiClient { fun getClientForCheckInternet()=Any(); fun getClient(apiConfig:Any,tokenStorage:Any,flavor:Any)=Any() }
class YuchengApiConfig { val sleepBaseUrl="http://test.invalid"; val healthBaseUrl="http://test.invalid"; companion object { fun fromFlavor(value:Any)=YuchengApiConfig() } }
data class StartEndTimestamp(val start:Long=0,val end:Long=100) { companion object { fun service()=StartEndTimestamp() } }
class YuchengRepository(client:Any,config:Any) {
 companion object { val sent=mutableListOf<String>(); var sleepError:Exception?=null; var healthError:Exception?=null }
 suspend fun saveSleep(data:List<YuchengSleepData>, id:String) { sent.add("sleep"); sleepError?.let {throw it} }
 suspend fun saveHealth(data:YuchengHealthSportData, id:String) { sent.add("health"); healthError?.let {throw it} }
}
class GsonBuilder { fun create()=this; fun toJson(value:Any?)="[]" }
fun YuchengSleepData.toJson()=emptyMap<String,Any>()
fun YuchengSportData.toJson()=emptyMap<String,Any>()
fun YuchengHealthData.toJson()=emptyMap<String,Any>()
fun Long.isValidEpochMs()=true
fun String.toMediaType()=this
fun String.toRequestBody(media:String)=this
object YuchengApiConstants { const val sleep="/sleep"; const val health="/health" }
class Request { class Builder { fun header(name:String,value:String)=this; fun url(value:String)=this; fun post(value:String)=this; fun build()=Request() } }
class OkHttpClient(val code:Int=200,val error:Exception?=null) {
 fun newCall(request:Request)=this
 fun execute():Response { error?.let { throw it }; return Response(code) }
}
class Response(val code:Int):AutoCloseable { val isSuccessful get()=code in 200..299; override fun close() {} }
var passed=0; var failed=0
suspend fun test(name:String, body:suspend () -> Unit) {
 YCBTClient.modes.clear(); YCBTClient.reads.clear(); YuchengRepository.sent.clear(); YuchengRepository.sleepError=null; YuchengRepository.healthError=null
 try { body(); println("PASS $name"); passed++ } catch(e:Throwable) { println("FAIL $name: $e"); failed++ }
}
suspend fun sleepRead(events:(YuchengSleepEvent)->Unit={}) = YuchengCore.getSleepData(false,0,100,YuchengSleepDataConverter(),events)
suspend fun healthRead(events:(YuchengHealthEvent)->Unit={}) = YuchengCore.getHealthSportData(false,0,100,YuchengSportDataConverter(),YuchengHealthDataConverter(),events)
suspend fun deleteSleep():Boolean {
 val reply=CompletableDeferred<Boolean>(); val count=AtomicInteger()
 HistoryHost().deleteSleepData { count.incrementAndGet(); reply.complete(it.getOrThrow()) }
 val result=withTimeout(200) {reply.await()}; delay(80); check(count.get()==1); return result
}
suspend fun deleteHealth():Boolean {
 val reply=CompletableDeferred<Boolean>(); val count=AtomicInteger()
 HistoryHost().deleteHealthSportData { count.incrementAndGet(); reply.complete(it.getOrThrow()) }
 val result=withTimeout(200) {reply.await()}; delay(80); check(count.get()==1); return result
}
fun main() = runBlocking {
 test("complete_read_ack_deletes_history") {
   sleepRead(); healthRead(); check(deleteSleep()); check(deleteHealth()); check(YCBTClient.deletes.toSet()==setOf(4,5,6)); YCBTClient.deletes.clear()
 }
 test("active_read_rejects_automatic_delete") {
   YCBTClient.modes[1]="late"; val pending=async { runCatching {sleepRead()} }; delay(5)
   check(!deleteSleep()); check(YCBTClient.deletes.isEmpty()); pending.await(); delay(170)
 }

 for(mode in listOf("success","empty","null","error","throw","timeout","bad","duplicate","late")) {
   test("sleep_$mode") {
     YCBTClient.modes[1]=mode; val count=AtomicInteger(); val result=runCatching { sleepRead { if(it is YuchengSleepDataEvent) count.incrementAndGet() } }
     delay(170)
     if(mode in listOf("success","empty","duplicate")) { check(result.isSuccess); check(result.getOrThrow().size == if(mode=="empty") 0 else 1); check(count.get() == if(mode=="empty") 0 else 1) }
     else { check(result.isFailure); check(count.get()==0) }
   }
 }
 for((sport,health) in listOf("success" to "success","empty" to "empty","success" to "throw","throw" to "success","timeout" to "success","success" to "timeout","empty" to "error","error" to "empty","timeout" to "timeout","error" to "error")) {
   test("health_${sport}_${health}") {
     YCBTClient.modes[2]=sport; YCBTClient.modes[3]=health
     var event:YuchengHealthSportData?=null
     val result=runCatching { healthRead { if(it is YuchengHealthDataEvent) event=it.healthData } }
     check(YCBTClient.reads.containsAll(listOf(2,3)))
     val success=sport=="success" || health=="success" || sport=="empty" && health=="empty"
     check(result.isSuccess==success)
     if(success) { check(result.getOrThrow().sportData.size==if(sport=="success") 1 else 0); check(result.getOrThrow().healthData.size==if(health=="success") 1 else 0); check(event==result.getOrThrow()) }
   }
 }
 test("read_sleep_failure_still_uploads_health") { YCBTClient.modes[1]="throw"; YuchengBleService().readData(); check(YuchengRepository.sent==listOf("health")) }
 test("read_health_failure_still_uploads_sleep") { YCBTClient.modes[2]="throw"; YCBTClient.modes[3]="throw"; YuchengBleService().readData(); check(YuchengRepository.sent==listOf("sleep")) }
 test("upload_sleep_failure_still_uploads_health") { YuchengRepository.sleepError=IllegalStateException("upload"); YuchengBleService().sendDataToServer(listOf(YuchengSleepData()),YuchengHealthSportData(listOf(YuchengHealthData()),emptyList())); check(YuchengRepository.sent==listOf("sleep","health")) }
 test("upload_cancel_does_not_upload_health") { YuchengRepository.sleepError=CancellationException("cancel"); check(runCatching { YuchengBleService().sendDataToServer(listOf(YuchengSleepData()),YuchengHealthSportData(listOf(YuchengHealthData()),emptyList())) }.exceptionOrNull() is CancellationException); check(YuchengRepository.sent==listOf("sleep")) }
 test("read_cancel_does_not_continue") { YCBTClient.modes[2]="timeout"; val job=async { healthRead() }; delay(10); job.cancel(); check(runCatching { job.await() }.exceptionOrNull() is CancellationException); check(3 !in YCBTClient.reads) }
 test("partial_ack_retains_unread_history_after_later_full_read") {
   YCBTClient.modes[3]="throw"; check(healthRead().sportData.isNotEmpty())
   check(!deleteHealth()); check(YCBTClient.deletes.isEmpty())
   YCBTClient.modes.clear(); healthRead(); check(!deleteHealth()); check(YCBTClient.deletes.isEmpty())
 }
 test("failed_sleep_ack_retains_history_after_later_full_read") {
   YCBTClient.modes[1]="null"; check(runCatching {sleepRead()}.isFailure)
   YCBTClient.modes.clear(); sleepRead(); check(!deleteSleep()); check(YCBTClient.deletes.isEmpty())
 }
 test("upload_health_failure_preserves_sleep_attempt") {
   YuchengRepository.healthError=IllegalStateException("upload")
   YuchengBleService().sendDataToServer(listOf(YuchengSleepData()),YuchengHealthSportData(listOf(YuchengHealthData()),emptyList()))
   check(YuchengRepository.sent==listOf("sleep","health"))
 }
 for(category in listOf("sleep","health")) for(failure in listOf("http","io","cancel","success")) {
   test("repository_${category}_${failure}") {
     val repo=ProductionRepository(OkHttpClient(if(failure=="http") 500 else 200, when(failure) { "io" -> java.io.IOException("network"); "cancel" -> CancellationException("cancel"); else -> null }), YuchengApiConfig())
     val result=runCatching { if(category=="sleep") repo.saveSleep(listOf(YuchengSleepData()),"test") else repo.saveHealth(YuchengHealthSportData(listOf(YuchengHealthData()),emptyList()),"test") }
     check(result.isSuccess==(failure=="success"))
     if(failure=="cancel") check(result.exceptionOrNull() is CancellationException)
   }
 }
 println("$passed passed, $failed failed"); check(failed==0)
}
