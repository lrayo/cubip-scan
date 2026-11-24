import CoreBluetooth
import Flutter
import GReader
import UIKit

public class CubipRfidPlugin: NSObject, FlutterPlugin, FlutterStreamHandler {
  public static func register(with registrar: FlutterPluginRegistrar) {
    let instance = CubipRfidPlugin()
    let methods = FlutterMethodChannel(name: "cubip_rfid", binaryMessenger: registrar.messenger())
    let events = FlutterEventChannel(name: "cubip_rfid/events", binaryMessenger: registrar.messenger())
    registrar.addMethodCallDelegate(instance, channel: methods)
    events.setStreamHandler(instance)
  }

  private let client = GClient()
  private let bleManager = GBleManager.instance
  private var eventSink: FlutterEventSink?
  private var devices: [String: CBPeripheral] = [:]
  private var gbleDevice: GBleDevice?
  private let queue = DispatchQueue(label: "com.megadeep.cubipscan.rfid")

  public func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
    eventSink = events
    return nil
  }

  public func onCancel(withArguments arguments: Any?) -> FlutterError? {
    eventSink = nil
    return nil
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "requestPermissions":
      result(true)
    case "startScan":
      startScan()
      result(nil)
    case "stopScan":
      bleManager.stopBluetoothDevicesDiscovery()
      result(nil)
    case "connect":
      let args = call.arguments as? [String: Any]
      guard let id = args?["deviceId"] as? String else {
        result(FlutterError(code: "args", message: "Falta el identificador del lector.", details: nil))
        return
      }
      connect(deviceId: id, result: result)
    case "disconnect":
      _ = client.close()
      emit(["type": "connection", "state": "disconnected"])
      result(nil)
    case "startInventory":
      startInventory(result: result)
    case "stopInventory":
      send(MsgBaseStop(), result: result, onOk: { _ in result(nil) })
    case "setPower":
      let args = call.arguments as? [String: Any]
      let power = args?["power"] as? Int ?? 26
      let msg = MsgBaseSetPower()
      msg.dicPower[1] = power
      send(msg, result: result, onOk: { _ in result(nil) })
    case "getPower":
      let msg = MsgBaseGetPower()
      send(msg, result: result, onOk: { _ in result(msg.dicPower[1]) })
    case "applyColombiaBand":
      applyColombiaBand(result: result)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func startScan() {
    bleManager.setGBLEDeviceServiceUUID(serviceUUID: CubipRfidPlugin.serviceUuid)
    bleManager.setGPeripheralCharacteristicWriteUUID(peripheralCharacteristicWriteUUID: CubipRfidPlugin.writeUuid)
    bleManager.onBluetoothAdapterStateChange { [weak self] ok, _, errMsg in
      guard let self else { return }
      if ok {
        self.bleManager.onBluetoothDevicePeripheral { peripheral, rssi in
          let name = peripheral.name ?? ""
          if name.isEmpty { return }
          self.devices[peripheral.identifier.uuidString] = peripheral
          self.emit([
            "type": "device",
            "id": peripheral.identifier.uuidString,
            "name": name,
            "rssi": rssi,
          ])
        }
        self.bleManager.startBluetoothDevicesDiscovery()
      } else {
        let message: String
        if errMsg == "poweredOff" {
          message = "Activa el Bluetooth para buscar el lector."
        } else if errMsg == "unauthorized" {
          message = "Autoriza el Bluetooth de la app para buscar el lector."
        } else {
          message = "Error de Bluetooth: \(errMsg)"
        }
        self.emit(["type": "error", "message": message])
      }
    }
    bleManager.openBluetoothAdapter()
  }

  private func connect(deviceId: String, result: @escaping FlutterResult) {
    guard let peripheral = devices[deviceId] else {
      result(FlutterError(code: "connect", message: "No se encontró ese lector. Vuelve a escanear.", details: nil))
      return
    }
    emit(["type": "connection", "state": "connecting"])
    bleManager.stopBluetoothDevicesDiscovery()
    let device = GBleDevice(gble: bleManager, gPeripheral: peripheral)
    gbleDevice = device
    guard client.openBleClient(gBleDevice: device) else {
      emit(["type": "connection", "state": "disconnected", "message": "No se pudo abrir la conexión BLE."])
      result(FlutterError(code: "connect", message: "No se pudo abrir la conexión BLE.", details: nil))
      return
    }
    client.onBLEConnect { [weak self] _, code, msg in
      if code == 0 {
        self?.client.onTagEpcLog { _, info in
          self?.handleTag(info)
        }
        self?.client.onTagEpcOver { _, _ in
          self?.emit(["type": "inventoryOver"])
        }
        self?.emit(["type": "connection", "state": "connected"])
        DispatchQueue.main.async { result(nil) }
      } else {
        self?.emit(["type": "connection", "state": "disconnected", "message": msg])
        DispatchQueue.main.async {
          result(FlutterError(code: "connect", message: msg, details: nil))
        }
      }
    }
    client.onBLEDisconnect { [weak self] _, errMsg in
      _ = self?.client.close()
      self?.emit(["type": "connection", "state": "disconnected", "message": errMsg])
    }
  }

  private func startInventory(result: @escaping FlutterResult) {
    let msg = MsgBaseInventoryEpc()
    msg.antennaEnable = EnumG.AntennaNo_1
    msg.inventoryMode = EnumG.InventoryMode_Inventory
    send(msg, result: result, onOk: { _ in result(nil) })
  }

  private func applyColombiaBand(result: @escaping FlutterResult) {
    let range = MsgBaseSetFreqRange()
    range.freqRangeIndex = 3
    send(range, result: result, onOk: { _ in
      let freq = MsgBaseSetFrequency()
      freq.automatically = false
      freq.freqIndexArray = Array(25...49)
      self.send(freq, result: result, onOk: { _ in result(nil) })
    })
  }

  private func handleTag(_ info: LogBaseEpcInfo) {
    if info.result != 0 { return }
    let epc = info.epc
    if epc.isEmpty { return }
    let rssi = info.rssidBm != 0 ? info.rssidBm : info.rssi
    emit([
      "type": "read",
      "epc": epc,
      "tid": info.tid,
      "rssi": rssi,
      "rssidBm": info.rssidBm,
      "antenna": info.antId,
      "timestamp": Int(Date().timeIntervalSince1970 * 1000),
    ])
  }

  private func send(_ msg: Message, result: @escaping FlutterResult, onOk: @escaping (Message) -> Void) {
    client.sendAsyncMsg(msg: msg, callback: { _ in
      if msg.getRtCode() == 0 {
        onOk(msg)
      } else {
        result(FlutterError(code: "rfid", message: msg.getRtMsg(), details: nil))
      }
    }, timeout: 3000)
  }

  private func emit(_ event: [String: Any]) {
    DispatchQueue.main.async { self.eventSink?(event) }
  }

  private static let serviceUuid = "0000fff0-0000-1000-8000-00805f9b34fb"
  private static let writeUuid = "0000fff2-0000-1000-8000-00805f9b34fb"
}
