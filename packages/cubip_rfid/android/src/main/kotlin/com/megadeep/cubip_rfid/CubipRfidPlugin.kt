@file:Suppress("MissingPermission")
package com.megadeep.cubip_rfid

import android.Manifest
import android.app.Activity
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothManager
import android.bluetooth.le.ScanCallback
import android.bluetooth.le.ScanResult
import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import com.gg.reader.api.dal.GClient
import com.gg.reader.api.dal.communication.BleBluetoothClient
import com.gg.reader.api.protocol.gx.EnumG
import com.gg.reader.api.protocol.gx.LogBaseEpcInfo
import com.gg.reader.api.protocol.gx.MsgBaseGetPower
import com.gg.reader.api.protocol.gx.MsgBaseInventoryEpc
import com.gg.reader.api.protocol.gx.MsgBaseSetFreqRange
import com.gg.reader.api.protocol.gx.MsgBaseSetFrequency
import com.gg.reader.api.protocol.gx.MsgBaseSetPower
import com.gg.reader.api.protocol.gx.MsgBaseStop
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.PluginRegistry
import java.util.Hashtable
import java.util.UUID
import java.util.concurrent.Executors

class CubipRfidPlugin :
    FlutterPlugin,
    MethodChannel.MethodCallHandler,
    EventChannel.StreamHandler,
    ActivityAware,
    PluginRegistry.RequestPermissionsResultListener {

    private lateinit var methods: MethodChannel
    private lateinit var events: EventChannel
    private lateinit var appContext: Context
    private var activity: Activity? = null
    private var eventSink: EventChannel.EventSink? = null

    private val mainHandler = Handler(Looper.getMainLooper())
    private val io = Executors.newSingleThreadExecutor()

    private val client = GClient()
    private var bleClient: BleBluetoothClient? = null
    private var adapter: BluetoothAdapter? = null

    private val serviceUuid: UUID = UUID.fromString(SERVICE_UUID)
    private val notifyUuid: UUID = UUID.fromString(NOTIFY_UUID)
    private val writeUuid: UUID = UUID.fromString(WRITE_UUID)

    private val scanCallback = object : ScanCallback() {
        override fun onScanResult(callbackType: Int, result: ScanResult) {
            val device = result.device ?: return
            val name = device.name ?: result.scanRecord?.deviceName ?: return
            if (name.isBlank()) return
            emit(
                mapOf(
                    "type" to "device",
                    "id" to device.address,
                    "name" to name,
                    "rssi" to result.rssi,
                ),
            )
        }

        override fun onScanFailed(errorCode: Int) {
            emit(mapOf("type" to "error", "message" to "El escaneo BLE falló ($errorCode)."))
        }
    }

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        appContext = binding.applicationContext
        methods = MethodChannel(binding.binaryMessenger, "cubip_rfid")
        events = EventChannel(binding.binaryMessenger, "cubip_rfid/events")
        methods.setMethodCallHandler(this)
        events.setStreamHandler(this)
        adapter = (appContext.getSystemService(Context.BLUETOOTH_SERVICE) as BluetoothManager).adapter
        bleClient = BleBluetoothClient(appContext).apply {
            setSERVER_UUID(serviceUuid)
            setNOTIFY_UUID(notifyUuid)
            setWRITE_UUID(writeUuid)
        }
        client.onTagEpcLog = { _, info -> handleTag(info) }
        client.onTagEpcOver = { _, _ -> emit(mapOf("type" to "inventoryOver")) }
        client.onDisconnected = { _ ->
            emit(mapOf("type" to "connection", "state" to "disconnected", "message" to "El lector se desconectó."))
        }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        methods.setMethodCallHandler(null)
        events.setStreamHandler(null)
        stopScanInternal()
        runCatching { client.close() }
        runCatching { bleClient?.close() }
        io.shutdownNow()
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        eventSink = events
    }

    override fun onCancel(arguments: Any?) {
        eventSink = null
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "requestPermissions" -> requestPermissions(result)
            "startScan" -> {
                if (!hasPermissions()) {
                    result.error("permissions", "Faltan permisos de Bluetooth.", null)
                    return
                }
                try {
                    startScanInternal()
                    result.success(null)
                } catch (e: Exception) {
                    result.error("scan", e.message, null)
                }
            }
            "stopScan" -> {
                stopScanInternal()
                result.success(null)
            }
            "connect" -> {
                val id = call.argument<String>("deviceId")
                if (id.isNullOrBlank()) {
                    result.error("args", "Falta el identificador del lector.", null)
                    return
                }
                io.execute {
                    try {
                        connectInternal(id)
                        mainHandler.post { result.success(null) }
                    } catch (e: Exception) {
                        mainHandler.post { result.error("connect", e.message, null) }
                    }
                }
            }
            "disconnect" -> io.execute {
                runCatching { client.sendSynMsg(MsgBaseStop()) }
                runCatching { client.close() }
                runCatching { bleClient?.close() }
                emit(mapOf("type" to "connection", "state" to "disconnected"))
                mainHandler.post { result.success(null) }
            }
            "startInventory" -> io.execute {
                try {
                    startInventoryInternal()
                    mainHandler.post { result.success(null) }
                } catch (e: Exception) {
                    mainHandler.post { result.error("inventory", e.message, null) }
                }
            }
            "stopInventory" -> io.execute {
                client.sendSynMsg(MsgBaseStop())
                mainHandler.post { result.success(null) }
            }
            "setPower" -> {
                val power = call.argument<Int>("power") ?: 26
                io.execute {
                    try {
                        setPowerInternal(power)
                        mainHandler.post { result.success(null) }
                    } catch (e: Exception) {
                        mainHandler.post { result.error("power", e.message, null) }
                    }
                }
            }
            "getPower" -> io.execute {
                try {
                    mainHandler.post { result.success(getPowerInternal()) }
                } catch (e: Exception) {
                    mainHandler.post { result.error("power", e.message, null) }
                }
            }
            "applyColombiaBand" -> io.execute {
                try {
                    applyColombiaBandInternal()
                    mainHandler.post { result.success(null) }
                } catch (e: Exception) {
                    mainHandler.post { result.error("band", e.message, null) }
                }
            }
            else -> result.notImplemented()
        }
    }

    private fun startScanInternal() {
        val bluetooth = adapter ?: throw IllegalStateException("Este dispositivo no tiene Bluetooth.")
        if (!bluetooth.isEnabled) {
            throw IllegalStateException("Activa el Bluetooth para buscar el lector.")
        }
        bluetooth.bluetoothLeScanner.startScan(scanCallback)
    }

    private fun stopScanInternal() {
        runCatching { adapter?.bluetoothLeScanner?.stopScan(scanCallback) }
    }

    private fun connectInternal(address: String) {
        stopScanInternal()
        emit(mapOf("type" to "connection", "state" to "connecting"))
        val ble = bleClient ?: throw IllegalStateException("Cliente BLE no inicializado.")
        ble.setSERVER_UUID(serviceUuid)
        ble.setNOTIFY_UUID(notifyUuid)
        ble.setWRITE_UUID(writeUuid)
        if (!client.openBleBluetooth(address, 4000, ble)) {
            emit(
                mapOf(
                    "type" to "connection",
                    "state" to "disconnected",
                    "message" to "No se pudo abrir la conexión BLE.",
                ),
            )
            throw IllegalStateException("No se pudo abrir la conexión BLE.")
        }
        client.setSendHeartBeat(true)
        emit(mapOf("type" to "connection", "state" to "connected"))
    }

    private fun startInventoryInternal() {
        val msg = MsgBaseInventoryEpc()
        msg.antennaEnable = EnumG.AntennaNo_1
        msg.inventoryMode = EnumG.InventoryMode_Inventory
        client.sendSynMsg(msg)
        if (msg.rtCode.toInt() != 0) {
            throw IllegalStateException(msg.rtMsg ?: "El inventario no arrancó.")
        }
    }

    private fun setPowerInternal(power: Int) {
        val msg = MsgBaseSetPower()
        val table = Hashtable<Int, Int>()
        table[1] = power
        msg.dicPower = table
        client.sendSynMsg(msg)
        if (msg.rtCode.toInt() != 0) {
            throw IllegalStateException(msg.rtMsg ?: "No se pudo aplicar la potencia.")
        }
    }

    private fun getPowerInternal(): Int? {
        val msg = MsgBaseGetPower()
        client.sendSynMsg(msg)
        if (msg.rtCode.toInt() != 0) return null
        return msg.dicPower?.get(1)
    }

    private fun applyColombiaBandInternal() {
        val range = MsgBaseSetFreqRange()
        range.freqRangeIndex = FCC_RANGE_INDEX
        client.sendSynMsg(range)
        if (range.rtCode.toInt() != 0) {
            throw IllegalStateException(range.rtMsg ?: "No se pudo fijar la banda FCC.")
        }
        val freq = MsgBaseSetFrequency()
        freq.automatically = false
        freq.listFreqCursor = ArrayList(COLOMBIA_CURSORS)
        client.sendSynMsg(freq)
        if (freq.rtCode.toInt() != 0) {
            throw IllegalStateException(freq.rtMsg ?: "No se pudieron limitar los canales de Colombia.")
        }
    }

    private fun handleTag(info: LogBaseEpcInfo?) {
        if (info == null || info.result != 0) return
        val epc = info.epc ?: return
        if (epc.isBlank()) return
        val rssiDbm = info.rssidBm
        val rssi = if (rssiDbm != 0) rssiDbm else info.rssi
        val tid = info.tid
        emit(
            mapOf(
                "type" to "read",
                "epc" to epc,
                "tid" to (tid ?: ""),
                "rssi" to rssi,
                "rssidBm" to rssiDbm,
                "antenna" to info.antId,
                "timestamp" to System.currentTimeMillis(),
            ),
        )
    }

    private fun emit(event: Map<String, Any?>) {
        mainHandler.post { eventSink?.success(event) }
    }

    private fun hasPermissions(): Boolean {
        return requiredPermissions().all {
            ContextCompat.checkSelfPermission(appContext, it) == PackageManager.PERMISSION_GRANTED
        }
    }

    private fun requiredPermissions(): Array<String> {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            arrayOf(Manifest.permission.BLUETOOTH_SCAN, Manifest.permission.BLUETOOTH_CONNECT)
        } else {
            arrayOf(Manifest.permission.ACCESS_FINE_LOCATION)
        }
    }

    private var permissionResult: MethodChannel.Result? = null

    private fun requestPermissions(result: MethodChannel.Result) {
        if (hasPermissions()) {
            result.success(true)
            return
        }
        val act = activity
        if (act == null) {
            result.error("activity", "No hay una Activity para pedir permisos.", null)
            return
        }
        permissionResult = result
        ActivityCompat.requestPermissions(act, requiredPermissions(), PERMISSION_REQUEST)
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ): Boolean {
        if (requestCode != PERMISSION_REQUEST) return false
        val ok = grantResults.isNotEmpty() && grantResults.all { it == PackageManager.PERMISSION_GRANTED }
        permissionResult?.success(ok)
        permissionResult = null
        if (!ok) {
            emit(mapOf("type" to "error", "message" to "Se necesitan permisos de Bluetooth para escanear."))
        }
        return true
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activity = binding.activity
        binding.addRequestPermissionsResultListener(this)
    }

    override fun onDetachedFromActivityForConfigChanges() {
        activity = null
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        onAttachedToActivity(binding)
    }

    override fun onDetachedFromActivity() {
        activity = null
    }

    companion object {
        const val SERVICE_UUID = "0000fff0-0000-1000-8000-00805f9b34fb"
        const val NOTIFY_UUID = "0000fff1-0000-1000-8000-00805f9b34fb"
        const val WRITE_UUID = "0000fff2-0000-1000-8000-00805f9b34fb"
        const val FCC_RANGE_INDEX = 3
        const val PERMISSION_REQUEST = 0xC0B1

        // Cursores de FrequencyUtils.indexGetFre(3) entre 915 y 928 MHz (índices 25..49).
        val COLOMBIA_CURSORS: List<Int> = (25..49).toList()
    }
}
