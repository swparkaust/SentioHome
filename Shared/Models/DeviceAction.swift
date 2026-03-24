import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Each instance represents a single control action for a HomeKit accessory.
#if canImport(FoundationModels)
@Generable
#endif
struct DeviceAction: Codable {

    #if canImport(FoundationModels)
    @Guide(description: "The accessory ID shown in square brackets in the device list, e.g. if the device is listed as '[ABC-123] Floor Lamp', use 'ABC-123'.")
    #endif
    var accessoryID: String

    #if canImport(FoundationModels)
    @Guide(description: "Human-readable name of the accessory, e.g. 'Living Room Light'.")
    #endif
    var accessoryName: String

    #if canImport(FoundationModels)
    @Guide(description: "The exact characteristic type shown in the device list (e.g. 'on', 'brightness', 'hue', 'saturation', 'targetTemperature', 'active', 'colorTemperature'). Use only types that appear for that device.")
    #endif
    var characteristic: String

    #if canImport(FoundationModels)
    @Guide(description: "The numeric value to set for the characteristic. For booleans use 1 (on/true) or 0 (off/false). For brightness use 0-100. For hue use 0-360. For saturation use 0-100. For temperature use Celsius.")
    #endif
    var value: Double

    #if canImport(FoundationModels)
    @Guide(description: "A brief, friendly reason for this action shown to the user, e.g. 'Dimming lights for the evening'.")
    #endif
    var reason: String
}
