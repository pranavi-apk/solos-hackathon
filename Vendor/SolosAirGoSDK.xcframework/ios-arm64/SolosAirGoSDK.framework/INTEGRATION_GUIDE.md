# Qcc5126 Gaia Response Listener Integration Guide

## Overview

The `Qcc5126GaiaResponseListener` is a comprehensive response aggregator that implements the `GaiaResponseListener` protocol and delegates responses to feature-specific listeners. This follows the same dual-layer architecture as the Android implementation.

## Architecture

```
PacketManagers → Qcc5126GaiaResponseListener → Feature-Specific Listeners
     ↓                    ↓                           ↓
GaiaResponseListener      |                   RtcGaiaListenerInterface
(Basic + Config +         |                   SystemGaiaListenerInterface  
 Wifi + Gaia247)          |                   SensorsGaiaListenerInterface
                          |                   BatteryGaiaListenerInterface
                          |                   ... (20+ feature interfaces)
```

## Simple Integration Approach

### 1. Initialize the Controller

```swift
let controller = SolosGaiaController(version: .v2) // or .v3
controller.setGaiaSender(gaiaSender)
```

### 2. Create and Set Up the Response Listener

```swift
// Create the response listener
let responseListener = Qcc5126GaiaResponseListener()

// Set up your feature listeners
let systemFeature = MySystemFeature()
let batteryFeature = MyBatteryFeature()

// Register feature listeners with the response listener
responseListener.setFeatureListeners(
    system: systemFeature,
    battery: batteryFeature
    // ... add other features as needed
)

// Set the response listener on the controller
controller.setMainResponseListener(responseListener)
```

### 3. Create Feature Classes

Create your feature classes that implement the specific listener interfaces:

```swift
class MySystemFeature: SystemGaiaListenerInterface {
    func onGetFwVersion(_ status: CommandSpecification.GaiaSolosResponseStatus?, majorVer: Int, minorVer: Int, boardVer: Int, buildNum: Int) {
        // Handle firmware version response
        print("FW Version: \(majorVer).\(minorVer).\(boardVer).\(buildNum)")
    }
    
    func onResetDevice() {
        // Handle device reset
    }
    
    // ... implement other required methods
}

class MyBatteryFeature: BatteryGaiaListenerInterface {
    func onReadAutoPowerOffTimeout(_ status: CommandSpecification.GaiaSolosResponseStatus?, timeout: Int) {
        // Handle auto power off timeout read
    }
    
    func onWriteAutoPowerOffTimeout(_ status: CommandSpecification.GaiaSolosResponseStatus?) {
        // Handle auto power off timeout write
    }
    
    // ... implement other required methods
}
```

### 4. Send Commands

Now when you send commands, responses will be automatically routed to the correct feature listeners:

```swift
// This will trigger onGetFwVersion in MySystemFeature
controller.readFWVersion()

// This will trigger onReadAutoPowerOffTimeout in MyBatteryFeature
controller.getAutoPowerOffTimeout()
```

## Complete Example

```swift
class Qcc5126Manager {
    private let controller: SolosGaiaController
    private let responseListener: Qcc5126GaiaResponseListener
    
    init(deviceVersion: GaiaDeviceVersion, gaiaSender: GaiaSenderProtocol) {
        // Convert device version to protocol version
        let protocolVersion: SolosCommandFactory.ProtocolVersion
        switch deviceVersion {
        case .v2: protocolVersion = .v2
        case .v3: protocolVersion = .v3
        case .unknown: protocolVersion = .v2
        }
        
        // Initialize controller
        controller = SolosGaiaController(version: protocolVersion)
        controller.setGaiaSender(gaiaSender)
        
        // Create response listener
        responseListener = Qcc5126GaiaResponseListener()
        
        // Set up feature listeners
        let systemFeature = MySystemFeature()
        let batteryFeature = MyBatteryFeature()
        
        responseListener.setFeatureListeners(
            system: systemFeature,
            battery: batteryFeature
        )
        
        // Set the response listener
        controller.setMainResponseListener(responseListener)
    }
    
    func readFirmwareVersion() {
        controller.readFWVersion()
    }
}
```

## Response Flow

1. **Command Sent**: `controller.readFWVersion()`
2. **Packet Manager**: `BasicGaiaPacketManager` sends the command
3. **Device Response**: Device responds with firmware version
4. **Packet Routing**: `SolosGaiaManager` routes the response
5. **Response Listener**: `Qcc5126GaiaResponseListener.onReadFWVersion()` is called
6. **Feature Delegation**: Response is delegated to `systemListener?.onGetFwVersion()`
7. **Feature Handler**: Your `MySystemFeature.onGetFwVersion()` receives the response

## Benefits

- **Simple**: Just create the response listener and set it
- **Modular**: Each feature has its own listener interface
- **Maintainable**: Easy to add new features without modifying existing code
- **Type Safe**: Strong typing for all response parameters
- **Optional**: Feature listeners are optional - only implement what you need
- **Consistent**: Matches Android architecture exactly

This approach is much simpler and cleaner - you just need to create the response listener, set up your feature listeners, and register it with the controller. The packet managers will automatically route all responses through the `GaiaResponseListener` protocol. 