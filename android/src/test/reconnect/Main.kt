import kotlinx.coroutines.*
import java.util.concurrent.CopyOnWriteArrayList
import java.util.concurrent.Executors
import java.util.concurrent.CountDownLatch

const val RING_A="AA:BB:CC:DD:EE:01"
const val RING_B="AA:BB:CC:DD:EE:02"

val mainDispatcher = Executors.newSingleThreadExecutor().asCoroutineDispatcher()
object Log { fun d(tag:String, value:String) {}; fun e(tag:String, value:String) {} }
object Constants { object BLEState { const val Connected=6; const val ReadWriteOK=10 } }
class Counter { var value=0L; fun fetchAndAdd(amount:Long):Long { val old=value; value+=amount; return old } }
data class YuchengDevice(val index:Long, val deviceName:String?, val uuid:String?, val isReconnected:Boolean)
class YuchengDeviceCompleteEvent(val completed:Boolean):YuchengDeviceEvent
class YuchengDeviceTimeOutEvent(val isTimeout:Boolean):YuchengDeviceEvent
interface YuchengDeviceEvent
class YuchengDeviceDataEvent(val index:Long, val uuid:String?, val isReconnected:Boolean, val deviceName:String?):YuchengDeviceEvent
class ScanDeviceBean(val deviceMac:String?=RING_A, val deviceName:String?="Ring", val device:Any?=Any())
object YCBTClient {
 var state=3; var boundMac:String?=RING_A; var failReconnect=false
 val reconnectDevices=CopyOnWriteArrayList<String>()
 val reconnectCallbacks=CopyOnWriteArrayList<(Int)->Unit>()
 val scanCallbacks=CopyOnWriteArrayList<(Int,ScanDeviceBean)->Unit>()
 val connectCallbacks=CopyOnWriteArrayList<(Int)->Unit>()
 var scanActive=false; var stopScans=0
 fun getBindDeviceMac()=boundMac
 fun getBindDeviceName()="Ring"
 fun connectState()=state
 fun reconnectDevice(mac:String, callback:(Int)->Unit) {
   if(failReconnect) throw IllegalStateException("SDK reconnect failure")
   reconnectDevices.add(mac); reconnectCallbacks.add(callback)
 }
 fun startScanBle(callback:(Int,ScanDeviceBean)->Unit, period:Int) { scanActive=true; scanCallbacks.add(callback) }
 fun connectBleDevice(device:Any, callback:(Int)->Unit) { connectCallbacks.add(callback) }
 fun stopScanBle() { scanActive=false; stopScans++ }
 fun reset() { state=3; boundMac=RING_A; failReconnect=false; reconnectDevices.clear(); reconnectCallbacks.clear(); scanCallbacks.clear(); connectCallbacks.clear(); scanActive=false; stopScans=0 }
}
var passed=0
suspend fun eventually(body:()->Boolean) { withTimeout(500) { while(!body()) delay(1) } }
suspend fun test(name:String, body:suspend CoroutineScope.()->Unit) = coroutineScope {
 YCBTClient.reset(); YuchengCore.connectState.value=3; YuchengCore.selectedDevice=null
 body()
 eventually { YuchengCore.connectState.subscriptionCount.value==0 }
 check(!YCBTClient.scanActive) { "scan leaked in $name" }
 println("PASS $name"); passed++
}
suspend fun startScanReconnect(scope:CoroutineScope, code:Int=1, events:MutableList<YuchengDeviceEvent>):Deferred<Result<Boolean>> {
 val result=scope.async { runCatching {YuchengCore.reconnect(RING_A,1,onDevice={events.add(it)})} }
 eventually { YCBTClient.reconnectCallbacks.size==1 }
 withContext(mainDispatcher) { YCBTClient.reconnectCallbacks.single()(code) }
 eventually { YCBTClient.scanCallbacks.size==1 }
 return result
}
fun main() = runBlocking {
 try {
  test("connecting_state_five_is_inside_the_reconnect_deadline") {
   YCBTClient.state=5; YuchengCore.connectState.value=5
   val started=System.nanoTime()
   val result=runCatching { withTimeout(700) { YuchengCore.reconnect(RING_A,1) } }
   val elapsed=(System.nanoTime()-started)/1_000_000
   check(result.exceptionOrNull() is TimeoutCancellationException)
   check(elapsed < 500) { "state 5 escaped requested deadline: ${elapsed}ms" }
   check(YCBTClient.reconnectCallbacks.isEmpty())
  }
  test("existing_connecting_state_can_finish_before_deadline") {
   YCBTClient.state=5; YuchengCore.connectState.value=5
   val events=mutableListOf<YuchengDeviceEvent>()
   val result=async { YuchengCore.reconnect(RING_A,1,onDevice={events.add(it)}) }
   delay(30); YCBTClient.state=6; YuchengCore.connectState.value=6
   check(result.await()); check(events.size==1); check(YuchengCore.selectedDevice?.uuid==RING_A)
  }
  test("sdk_no_response_cancels_the_state_listener") {
   val result=runCatching {YuchengCore.reconnect(RING_A,1)}
   check(result.exceptionOrNull() is TimeoutCancellationException)
   check(YCBTClient.reconnectCallbacks.size==1)
  }
  for(code in listOf(0,1)) {
   test("timeout_stops_scan_and_ignores_late_scan_callback_$code") {
    val events=mutableListOf<YuchengDeviceEvent>()
    val result=startScanReconnect(this,code,events)
    check(result.await().exceptionOrNull() is TimeoutCancellationException)
    check(YCBTClient.stopScans>0)
    withContext(mainDispatcher) { YCBTClient.scanCallbacks.single()(0,ScanDeviceBean()) }
    check(YCBTClient.connectCallbacks.isEmpty()); check(events.isEmpty()); check(YuchengCore.selectedDevice==null)
   }
   test("timeout_ignores_already_registered_late_connect_callback_$code") {
    val events=mutableListOf<YuchengDeviceEvent>()
    val result=startScanReconnect(this,code,events)
    withContext(mainDispatcher) { YCBTClient.scanCallbacks.single()(0,ScanDeviceBean()) }
    eventually { YCBTClient.connectCallbacks.size==1 }
    check(result.await().exceptionOrNull() is TimeoutCancellationException)
    YCBTClient.state=6
    withContext(mainDispatcher) { YCBTClient.connectCallbacks.single()(0) }
    check(events.isEmpty()); check(YuchengCore.selectedDevice==null)
   }
  }
  test("caller_cancellation_stops_scan_and_discards_late_callbacks") {
   val events=mutableListOf<YuchengDeviceEvent>()
   val result=startScanReconnect(this,1,events)
   result.cancelAndJoin()
   check(YCBTClient.stopScans>0)
   withContext(mainDispatcher) { YCBTClient.scanCallbacks.single()(0,ScanDeviceBean()) }
   check(YCBTClient.connectCallbacks.isEmpty()); check(events.isEmpty())
  }
  test("successful_scan_reconnect_still_publishes_selected_device") {
   val events=mutableListOf<YuchengDeviceEvent>()
   val result=startScanReconnect(this,1,events)
   withContext(mainDispatcher) { YCBTClient.scanCallbacks.single()(0,ScanDeviceBean()) }
   YCBTClient.state=6
   withContext(mainDispatcher) { YCBTClient.connectCallbacks.single()(0) }
   check(result.await().getOrThrow()); check(events.size==1)
   check(YuchengCore.selectedDevice?.uuid==RING_A)
  }
  test("auto_ready_publishes_metadata_before_return_and_ignores_late_sdk") {
   val events=mutableListOf<YuchengDeviceEvent>()
   val result=async {YuchengCore.reconnect(RING_A.lowercase(),1,onDevice={events.add(it)})}
   eventually {YCBTClient.reconnectCallbacks.size==1}
   YCBTClient.state=10; YuchengCore.connectState.value=10
   check(result.await())
   check(events.size==1); check(YuchengCore.selectedDevice?.uuid==RING_A)
   val selected=YuchengCore.selectedDevice
   withContext(mainDispatcher) {YCBTClient.reconnectCallbacks.single()(0)}
   check(events.size==1); check(YuchengCore.selectedDevice===selected)
  }
  test("late_reconnect_callback_cannot_mutate_a_new_attempt") {
   val events=mutableListOf<YuchengDeviceEvent>()
   check(runCatching {YuchengCore.reconnect(RING_A,1,onDevice={events.add(it)})}.isFailure)
   val old=YCBTClient.reconnectCallbacks.single()
   val current=async {YuchengCore.reconnect(RING_A,1,onDevice={events.add(it)})}
   eventually {YCBTClient.reconnectCallbacks.size==2}
   YCBTClient.state=6
   withContext(mainDispatcher) { old(0) }
   check(events.isEmpty()); check(YuchengCore.selectedDevice==null)
   withContext(mainDispatcher) {YCBTClient.reconnectCallbacks.last()(0)}
   check(current.await()); check(events.size==1)
  }
  test("successful_attempt_drops_all_stale_callbacks_during_a_new_attempt") {
   val firstEvents=mutableListOf<YuchengDeviceEvent>()
   val first=startScanReconnect(this,1,firstEvents)
   val staleReconnect=YCBTClient.reconnectCallbacks.single()
   val staleScan=YCBTClient.scanCallbacks.single()
   withContext(mainDispatcher) {staleScan(0,ScanDeviceBean())}
   val staleConnect=YCBTClient.connectCallbacks.single()
   YCBTClient.state=6
   withContext(mainDispatcher) {staleConnect(0)}
   check(first.await().getOrThrow()); check(firstEvents.size==1)
   val selected=YuchengCore.selectedDevice
   YCBTClient.state=3; YCBTClient.boundMac=RING_B
   val secondEvents=mutableListOf<YuchengDeviceEvent>()
   val second=async {YuchengCore.reconnect(RING_B,2,onDevice={secondEvents.add(it)})}
   eventually {YCBTClient.reconnectCallbacks.size==2}
   withContext(mainDispatcher) {YCBTClient.reconnectCallbacks.last()(1)}
   eventually {YCBTClient.scanCallbacks.size==2}
   val connectCount=YCBTClient.connectCallbacks.size
   val stops=YCBTClient.stopScans
   YCBTClient.state=6
   withContext(mainDispatcher) {
    staleReconnect(0); staleScan(0,ScanDeviceBean()); staleConnect(0)
   }
   check(YCBTClient.connectCallbacks.size==connectCount)
   check(YCBTClient.stopScans==stops && YCBTClient.scanActive)
   check(firstEvents.size==1 && secondEvents.isEmpty())
   check(YuchengCore.selectedDevice===selected)
   withContext(mainDispatcher) {
    YCBTClient.scanCallbacks.last()(0,ScanDeviceBean(deviceMac=RING_B))
    YCBTClient.connectCallbacks.last()(0)
   }
   check(second.await()); check(secondEvents.size==1)
   check(YuchengCore.selectedDevice?.uuid==RING_B)
  }
  test("superseded_attempt_cleanup_does_not_stop_a_new_scan") {
   val oldEvents=mutableListOf<YuchengDeviceEvent>()
   val first=startScanReconnect(this,1,oldEvents)
   val staleScan=YCBTClient.scanCallbacks.single()
   delay(20)
   YCBTClient.boundMac=RING_B
   val events=mutableListOf<YuchengDeviceEvent>()
   val second=async {YuchengCore.reconnect(RING_B,2,onDevice={events.add(it)})}
   eventually {YCBTClient.reconnectCallbacks.size==2}
   withContext(mainDispatcher) {YCBTClient.reconnectCallbacks.last()(1)}
   eventually {YCBTClient.scanCallbacks.size==2}
   val stops=YCBTClient.stopScans
   check(first.await().exceptionOrNull() is TimeoutCancellationException)
   check(YCBTClient.scanActive && YCBTClient.stopScans==stops)
   withContext(mainDispatcher) {staleScan(0,ScanDeviceBean())}
   check(YCBTClient.connectCallbacks.isEmpty() && oldEvents.isEmpty())
   YCBTClient.state=6
   withContext(mainDispatcher) {
    YCBTClient.scanCallbacks.last()(0,ScanDeviceBean(deviceMac=RING_B))
    YCBTClient.connectCallbacks.last()(0)
   }
   check(second.await()); check(events.size==1)
   check(YuchengCore.selectedDevice?.uuid==RING_B)
  }
  test("state_five_bind_switch_cannot_publish_the_captured_old_mac") {
   YCBTClient.state=5; YuchengCore.connectState.value=5
   val events=mutableListOf<YuchengDeviceEvent>()
   val result=async {YuchengCore.reconnect(RING_A,1,onDevice={events.add(it)})}
   delay(30)
   YCBTClient.boundMac=RING_B; YCBTClient.state=6; YuchengCore.connectState.value=6
   eventually {YCBTClient.reconnectCallbacks.size==1}
   check(!result.isCompleted); check(events.isEmpty()); check(YuchengCore.selectedDevice==null)
   result.cancelAndJoin()
  }
  test("auto_ready_does_not_publish_another_bound_device") {
   val events=mutableListOf<YuchengDeviceEvent>()
   val result=async {YuchengCore.reconnect(RING_A,1,onDevice={events.add(it)})}
   eventually {YCBTClient.reconnectCallbacks.size==1}
   YCBTClient.boundMac=RING_B; YCBTClient.state=10; YuchengCore.connectState.value=10
   delay(10)
   check(!result.isCompleted); check(events.isEmpty()); check(YuchengCore.selectedDevice==null)
   result.cancelAndJoin()
  }
  test("queued_superseded_main_job_never_calls_sdk_reconnect") {
   val released=CountDownLatch(1)
   val started=CompletableDeferred<Unit>()
   val blocker=launch(mainDispatcher) { started.complete(Unit); released.await() }
   started.await()
   try {
    val first=async {runCatching {YuchengCore.reconnect(RING_A,2)}}
    delay(30)
    YCBTClient.boundMac=RING_B
    val second=async {YuchengCore.reconnect(RING_B,2)}
    delay(30)
    released.countDown(); blocker.join()
    eventually {YCBTClient.reconnectDevices.isNotEmpty()}
    check(YCBTClient.reconnectDevices==listOf(RING_B))
    YCBTClient.state=6
    withContext(mainDispatcher) {YCBTClient.reconnectCallbacks.single()(0)}
    check(second.await())
    check(first.await().exceptionOrNull() is TimeoutCancellationException)
   } finally { released.countDown(); blocker.join() }
  }
  test("lowercase_request_matches_uppercase_bound_and_scan_mac") {
   YCBTClient.state=6
   val fastEvents=mutableListOf<YuchengDeviceEvent>()
   check(YuchengCore.reconnect(RING_A.lowercase(),1,onDevice={fastEvents.add(it)}))
   check(fastEvents.size==1)
   YCBTClient.state=3
   val events=mutableListOf<YuchengDeviceEvent>()
   val result=async {YuchengCore.reconnect(RING_A.lowercase(),1,onDevice={events.add(it)})}
   eventually {YCBTClient.reconnectCallbacks.size==1}
   check(YCBTClient.reconnectDevices.single()==RING_A)
   withContext(mainDispatcher) {
    YCBTClient.reconnectCallbacks.single()(1)
    YCBTClient.scanCallbacks.single()(0,ScanDeviceBean(deviceMac=RING_A))
   }
   YCBTClient.state=6
   withContext(mainDispatcher) {YCBTClient.connectCallbacks.single()(0)}
   check(result.await()); check(events.size==1)
  }
  test("old_scan_is_cleaned_when_new_attempt_uses_connected_fast_path") {
   val events=mutableListOf<YuchengDeviceEvent>()
   val first=startScanReconnect(this,1,events)
   YCBTClient.state=6; YCBTClient.boundMac=RING_B
   check(YuchengCore.reconnect(RING_B,1))
   check(first.await().exceptionOrNull() is TimeoutCancellationException)
   check(!YCBTClient.scanActive && YCBTClient.stopScans>0)
   check(events.isEmpty()); check(YuchengCore.selectedDevice?.uuid==RING_B)
  }
  test("public_scan_takes_ownership_from_background_reconnect") {
   val events=mutableListOf<YuchengDeviceEvent>()
   val first=startScanReconnect(this,1,events)
   val staleScan=YCBTClient.scanCallbacks.single()
   val publicScan=async {YuchengCore.scanDevices(20)}
   eventually {YCBTClient.scanCallbacks.size==2}
   val stops=YCBTClient.stopScans
   check(first.await().exceptionOrNull() is TimeoutCancellationException)
   check(YCBTClient.scanActive && YCBTClient.stopScans==stops)
   withContext(mainDispatcher) {staleScan(0,ScanDeviceBean())}
   check(YCBTClient.connectCallbacks.isEmpty() && events.isEmpty())
   publicScan.cancelAndJoin()
   // Mirrors stopScanDevices after leaving the public search screen.
   withContext(mainDispatcher) {YCBTClient.stopScanBle()}
  }
  test("manual_reconnect_callback_rejects_other_bound_device") {
   val events=mutableListOf<YuchengDeviceEvent>()
   val result=async {YuchengCore.reconnect(RING_A,1,onDevice={events.add(it)})}
   eventually {YCBTClient.reconnectCallbacks.size==1}
   YCBTClient.boundMac=RING_B; YCBTClient.state=6
   withContext(mainDispatcher) {YCBTClient.reconnectCallbacks.single()(0)}
   check(!result.await()); check(events.isEmpty()); check(YuchengCore.selectedDevice==null)
  }
  for(code in listOf(0,1)) {
   test("scan_connect_success_rejects_other_live_bound_device_$code") {
    val events=mutableListOf<YuchengDeviceEvent>()
    val result=startScanReconnect(this,code,events)
    withContext(mainDispatcher) {YCBTClient.scanCallbacks.single()(0,ScanDeviceBean())}
    YCBTClient.boundMac=RING_B; YCBTClient.state=6
    withContext(mainDispatcher) {YCBTClient.connectCallbacks.single()(0)}
    check(!result.await().getOrThrow()); check(events.isEmpty()); check(YuchengCore.selectedDevice==null)
   }
  }
  test("auto_ready_ignores_other_mac_then_waits_for_its_own_ready_state") {
   val events=mutableListOf<YuchengDeviceEvent>()
   val result=async {YuchengCore.reconnect(RING_A.lowercase(),1,onDevice={events.add(it)})}
   eventually {YCBTClient.reconnectCallbacks.size==1}
   YCBTClient.boundMac=RING_B; YCBTClient.state=10; YuchengCore.connectState.value=10
   delay(10)
   check(!result.isCompleted); check(events.isEmpty()); check(YuchengCore.selectedDevice==null)
   YCBTClient.state=5; YuchengCore.connectState.value=5
   delay(5)
   YCBTClient.boundMac=RING_A; YCBTClient.state=10; YuchengCore.connectState.value=10
   check(result.await()); check(events.size==1); check(YuchengCore.selectedDevice?.uuid==RING_A)
  }
  test("synchronous_sdk_error_cleans_up_observer") {
   YCBTClient.failReconnect=true
   val result=runCatching {YuchengCore.reconnect(RING_A,1)}
   check(result.exceptionOrNull() is IllegalStateException)
  }
  println("Yucheng reconnect: $passed checks passed")
 } finally { mainDispatcher.close() }
}
