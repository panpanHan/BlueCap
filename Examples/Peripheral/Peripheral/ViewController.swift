//
//  ViewController.swift
//  Beacon
//
//  Created by Troy Stribling on 4/13/15.
//  Copyright (c) 2015 gnos.us. All rights reserved.
//

import UIKit
import CoreBluetooth
import CoreMotion
import BlueCapKit

class ViewController: UITableViewController {
    
    let g =  9.81
    
    @IBOutlet var xAccelerationLabel        : UILabel!
    @IBOutlet var yAccelerationLabel        : UILabel!
    @IBOutlet var zAccelerationLabel        : UILabel!
    @IBOutlet var xRawAccelerationLabel     : UILabel!
    @IBOutlet var yRawAccelerationLabel     : UILabel!
    @IBOutlet var zRawAccelerationLabel     : UILabel!
    
    @IBOutlet var rawUpdatePeriodlabel      : UILabel!
    @IBOutlet var updatePeriodLabel         : UILabel!
    
    @IBOutlet var startAdvertisingSwitch    : UISwitch!
    @IBOutlet var startAdvertisingLabel     : UILabel!
    @IBOutlet var enableLabel               : UILabel!
    @IBOutlet var enabledSwitch             : UISwitch!
    
    var startAdvertiseFuture                : Future<Void>?
    var stopAdvertiseFuture                 : Future<Void>?
    var powerOffFuture                      : Future<Void>?
    var powerOffFutureSuccessFuture         : Future<Void>?
    var powerOffFutureFailedFuture          : Future<Void>?
    var accelerometerUpdatePeriodFuture     : FutureStream<CBATTRequest>?
    var accelerometerEnabledFuture          : FutureStream<CBATTRequest>?
    
    let accelerometer           = Accelerometer()
    var accelrometerDataFuture  : FutureStream<CMAcceleration>?
    
    let accelerometerService                    = MutableService(uuid:TISensorTag.AccelerometerService.uuid)
    let accelerometerDataCharacteristic         = MutableCharacteristic(uuid:TISensorTag.AccelerometerService.Data.uuid,
                                                    properties:CBCharacteristicProperties.Read|CBCharacteristicProperties.Notify,
                                                    permissions:CBAttributePermissions.Readable|CBAttributePermissions.Writeable,
                                                    value:Serde.serialize(TISensorTag.AccelerometerService.Data(x:1.0, y:0.5, z:-1.5)!))
    let accelerometerEnabledCharacteristic      = MutableCharacteristic(uuid:TISensorTag.AccelerometerService.Enabled.uuid,
                                                    properties:CBCharacteristicProperties.Read|CBCharacteristicProperties.Write,
                                                    permissions:CBAttributePermissions.Readable|CBAttributePermissions.Writeable,
                                                    value:Serde.serialize(TISensorTag.AccelerometerService.Enabled.No.rawValue))
    let accelerometerUpdatePeriodCharacteristic = MutableCharacteristic(uuid:TISensorTag.AccelerometerService.UpdatePeriod.uuid,
                                                    properties:CBCharacteristicProperties.Read|CBCharacteristicProperties.Write,
                                                    permissions:CBAttributePermissions.Readable|CBAttributePermissions.Writeable,
                                                    value:Serde.serialize(UInt8(100)))
    
    required init(coder aDecoder:NSCoder) {
        self.accelerometerService.characteristics =
            [self.accelerometerDataCharacteristic, self.accelerometerEnabledCharacteristic, self.accelerometerUpdatePeriodCharacteristic]
        super.init(coder:aDecoder)
        self.respondToWriteRequests()
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
    }
    
    override func viewWillAppear(animated: Bool) {
        super.viewWillAppear(animated)
        if self.accelerometer.accelerometerAvailable {
            self.startAdvertisingSwitch.enabled = true
            self.startAdvertisingLabel.textColor = UIColor.blackColor()
            self.enabledSwitch.enabled = true
            self.enableLabel.textColor = UIColor.blackColor()
            self.updatePeriod()
        } else {
            self.startAdvertisingSwitch.enabled = false
            self.startAdvertisingSwitch.on = false
            self.startAdvertisingLabel.textColor = UIColor.lightGrayColor()
            self.enabledSwitch.enabled = false
            self.enabledSwitch.on = false
            self.enableLabel.textColor = UIColor.lightGrayColor()
        }
    }
    
    override func viewWillDisappear(animated: Bool) {
        super.viewWillDisappear(animated)
    }
    
    @IBAction func toggleEnabled(sender:AnyObject) {
        if self.accelerometer.accelerometerActive {
            self.accelerometer.stopAccelerometerUpdates()
        } else {
            self.accelrometerDataFuture = self.accelerometer.startAcceleromterUpdates()
            self.accelrometerDataFuture?.onSuccess {data in
                self.updateAccelerometerData(data)
            }
            self.accelrometerDataFuture?.onFailure {error in
                self.presentViewController(UIAlertController.alertOnError(error), animated:true, completion:nil)
            }
        }
    }
    
    @IBAction func toggleAdvertise(sender:AnyObject) {
        let manager = PeripheralManager.sharedInstance
        if manager.isAdvertising {
            manager.stopAdvertising().onSuccess {
                self.presentViewController(UIAlertController.alertWithMessage("stoped advertising"), animated:true, completion:nil)
            }
            self.accelerometerUpdatePeriodCharacteristic.stopProcessingWriteRequests()
        } else {
            self.startAdvertising()
        }
    }
    
    func startAdvertising() {
        if let uuid = CBUUID(string:TISensorTag.AccelerometerService.uuid) {
            let manager = PeripheralManager.sharedInstance
            // on power on remove all services add service and start advertising
            self.startAdvertiseFuture = manager.powerOn().flatmap {_ -> Future<Void> in
                manager.removeAllServices()
                }.flatmap {_ -> Future<Void> in
                    manager.addService(self.accelerometerService)
                }.flatmap {_ -> Future<Void> in
                    manager.startAdvertising(TISensorTag.AccelerometerService.name, uuids:[uuid])
            }
            self.startAdvertiseFuture?.onSuccess {
                self.presentViewController(UIAlertController.alertWithMessage("powered on and started advertising"), animated:true, completion:nil)
            }
            self.startAdvertiseFuture?.onFailure {error in
                self.presentViewController(UIAlertController.alertOnError(error), animated:true, completion:nil)
                self.startAdvertisingSwitch.on = false
            }
            // stop advertising and updating accelerometer on bluetooth power off
            self.powerOffFuture = manager.powerOff().flatmap { _ -> Future<Void> in
                if self.accelerometer.accelerometerActive {
                    self.accelerometer.stopAccelerometerUpdates()
                    self.enabledSwitch.on = false
                }
                return manager.stopAdvertising()
            }
            self.powerOffFuture?.onSuccess {
                self.startAdvertisingSwitch.on = false
                self.startAdvertisingSwitch.enabled = false
                self.startAdvertisingLabel.textColor = UIColor.lightGrayColor()
                self.presentViewController(UIAlertController.alertWithMessage("powered off and stopped advertising"), animated:true, completion:nil)
            }
            self.powerOffFuture?.onFailure {error in
                self.startAdvertisingSwitch.on = false
                self.startAdvertisingSwitch.enabled = false
                self.startAdvertisingLabel.textColor = UIColor.lightGrayColor()
                self.presentViewController(UIAlertController.alertWithMessage("advertising failed"), animated:true, completion:nil)
            }
            // enable controls when bluetooth is powered on again after stop advertising is successul
            self.powerOffFutureSuccessFuture = self.powerOffFuture?.flatmap {_ -> Future<Void> in
                manager.powerOn()
            }
            self.powerOffFutureSuccessFuture?.onSuccess {
                self.startAdvertisingSwitch.enabled = true
                self.startAdvertisingLabel.textColor = UIColor.blackColor()
            }
            // enable controls when bluetooth is powered on again after     stop advertising fails
            self.powerOffFutureFailedFuture = self.powerOffFuture?.recoverWith {_  -> Future<Void> in
                manager.powerOn()
            }
            self.powerOffFutureFailedFuture?.onSuccess {
                if PeripheralManager.sharedInstance.poweredOn {
                    self.startAdvertisingSwitch.enabled = true
                    self.startAdvertisingLabel.textColor = UIColor.blackColor()
                }
            }
        }
    }
    
    func respondToWriteRequests() {
        self.accelerometerUpdatePeriodFuture = self.accelerometerUpdatePeriodCharacteristic.startRespondingToWriteRequests(capacity:2)
        self.accelerometerUpdatePeriodFuture?.onSuccess {request in
            if request.value.length > 0 &&  request.value.length <= 8 {
                self.accelerometerUpdatePeriodCharacteristic.value = request.value
                self.accelerometerUpdatePeriodCharacteristic.respondToRequest(request, withResult:CBATTError.Success)
                self.updatePeriod()
            } else {
                self.accelerometerUpdatePeriodCharacteristic.respondToRequest(request, withResult:CBATTError.InvalidAttributeValueLength)
            }
        }
        self.accelerometerEnabledFuture = self.accelerometerEnabledCharacteristic.startRespondingToWriteRequests(capacity:2)
        self.accelerometerEnabledFuture?.onSuccess {request in
            if request.value.length == 1 {
                self.accelerometerEnabledCharacteristic.value = request.value
                self.accelerometerEnabledCharacteristic.respondToRequest(request, withResult:CBATTError.Success)
                self.updateEnabled()
            } else {
                self.accelerometerEnabledCharacteristic.respondToRequest(request, withResult:CBATTError.InvalidAttributeValueLength)
            }
        }
    }
    
    func updateAccelerometerData(data:CMAcceleration) {
        self.xAccelerationLabel.text = NSString(format: "%.2f", data.x) as String
        self.yAccelerationLabel.text = NSString(format: "%.2f", data.y) as String
        self.zAccelerationLabel.text = NSString(format: "%.2f", data.z) as String
        if let xRaw = Int8(doubleValue:(-64.0*data.x)), yRaw = Int8(doubleValue:(-64.0*data.y)), zRaw = Int8(doubleValue:(64.0*data.z)) {
            self.xRawAccelerationLabel.text = "\(xRaw)"
            self.yRawAccelerationLabel.text = "\(yRaw)"
            self.zRawAccelerationLabel.text = "\(zRaw)"
            if let data = TISensorTag.AccelerometerService.Data(rawValue:[xRaw, yRaw, zRaw]) {
                self.accelerometerDataCharacteristic.updateValue(data)
            }
        }
    }
    
    func updatePeriod() {
        if let period : TISensorTag.AccelerometerService.UpdatePeriod = Serde.deserialize(self.accelerometerUpdatePeriodCharacteristic.value) {
            self.accelerometer.updatePeriod = Double(period.period)/1000.0
            self.updatePeriodLabel.text =  NSString(format: "%d", period.period) as String
            self.rawUpdatePeriodlabel.text = NSString(format: "%d", period.periodRaw) as String
        }
    }
    
    func updateEnabled() {
        if let enabled : TISensorTag.AccelerometerService.Enabled = Serde.deserialize(self.accelerometerEnabledCharacteristic.value)  where self.enabledSwitch.on != enabled.boolValue {
            self.enabledSwitch.on = enabled.boolValue
            self.toggleEnabled(self)
        }
    }
}
