import AudioToolbox
import CoreAudio
import Foundation
import Observation

struct AudioOutputDevice: Identifiable, Hashable {
    let id: AudioDeviceID
    let name: String
    let transport: UInt32

    /// SF Symbol matching the kind of device.
    var symbol: String {
        let lower = name.lowercased()
        switch transport {
        case kAudioDeviceTransportTypeBuiltIn:
            return "laptopcomputer"
        case kAudioDeviceTransportTypeBluetooth, kAudioDeviceTransportTypeBluetoothLE:
            if lower.contains("airpods max") { return "airpodsmax" }
            if lower.contains("airpods pro") { return "airpodspro" }
            if lower.contains("airpods") { return "airpods" }
            if lower.contains("beats") { return "beats.headphones" }
            if lower.contains("speaker") || lower.contains("boom") || lower.contains("jbl") { return "hifispeaker.fill" }
            return "headphones"
        case kAudioDeviceTransportTypeHDMI, kAudioDeviceTransportTypeDisplayPort:
            return "display"
        case kAudioDeviceTransportTypeAirPlay:
            return "airplayaudio"
        case kAudioDeviceTransportTypeUSB, kAudioDeviceTransportTypeThunderbolt, kAudioDeviceTransportTypeFireWire:
            return lower.contains("headphone") || lower.contains("headset") ? "headphones" : "hifispeaker"
        case kAudioDeviceTransportTypeVirtual, kAudioDeviceTransportTypeAggregate:
            return "waveform"
        default:
            return "speaker.wave.2"
        }
    }
}

/// Output devices, the current default output, and its volume, kept in sync via CoreAudio listeners
/// (so switching in Control Center, or AirPods connecting, shows up immediately).
@Observable
final class AudioOutputService {
    static let shared = AudioOutputService()

    private(set) var devices: [AudioOutputDevice] = []
    private(set) var currentID: AudioDeviceID = kAudioObjectUnknown
    private(set) var volume: Float = 0
    private(set) var isMuted = false
    /// False for devices whose volume is set on the device itself (e.g. many HDMI monitors).
    private(set) var hasVolumeControl = false

    var current: AudioOutputDevice? { devices.first { $0.id == currentID } }

    @ObservationIgnored private let queue = DispatchQueue.main
    @ObservationIgnored private var volumeListenerDevice: AudioDeviceID = kAudioObjectUnknown
    // Kept as stored blocks: removing a CoreAudio listener requires the identical block.
    @ObservationIgnored private var systemListener: AudioObjectPropertyListenerBlock = { _, _ in }
    @ObservationIgnored private var volumeListener: AudioObjectPropertyListenerBlock = { _, _ in }

    private init() {
        systemListener = { [weak self] _, _ in self?.refresh() }
        volumeListener = { [weak self] _, _ in self?.readVolume() }
        var devicesAddress = Self.address(kAudioHardwarePropertyDevices)
        var defaultAddress = Self.address(kAudioHardwarePropertyDefaultOutputDevice)
        let system = AudioObjectID(kAudioObjectSystemObject)
        AudioObjectAddPropertyListenerBlock(system, &devicesAddress, queue, systemListener)
        AudioObjectAddPropertyListenerBlock(system, &defaultAddress, queue, systemListener)
        refresh()
    }

    // MARK: Actions

    func select(_ device: AudioOutputDevice) {
        var id = device.id
        var address = Self.address(kAudioHardwarePropertyDefaultOutputDevice)
        let status = AudioObjectSetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, UInt32(MemoryLayout<AudioDeviceID>.size), &id
        )
        if status == noErr { refresh() }
    }

    func setVolume(_ value: Float) {
        var value = min(max(value, 0), 1)
        var address = Self.address(kAudioHardwareServiceDeviceProperty_VirtualMainVolume, scope: kAudioDevicePropertyScopeOutput)
        guard AudioObjectHasProperty(currentID, &address) else { return }
        AudioObjectSetPropertyData(currentID, &address, 0, nil, UInt32(MemoryLayout<Float>.size), &value)
        volume = value
        if isMuted, value > 0 { setMuted(false) }
    }

    func setMuted(_ muted: Bool) {
        var value: UInt32 = muted ? 1 : 0
        var address = Self.address(kAudioDevicePropertyMute, scope: kAudioDevicePropertyScopeOutput)
        guard AudioObjectHasProperty(currentID, &address) else { return }
        AudioObjectSetPropertyData(currentID, &address, 0, nil, UInt32(MemoryLayout<UInt32>.size), &value)
        isMuted = muted
    }

    // MARK: Reading

    func refresh() {
        devices = Self.allDeviceIDs()
            .filter { Self.hasOutputStreams($0) && !Self.isHidden($0) }
            .map { AudioOutputDevice(id: $0, name: Self.name(of: $0), transport: Self.transport(of: $0)) }
            .sorted { lhs, rhs in
                // Built-in speakers first, then alphabetical.
                if (lhs.transport == kAudioDeviceTransportTypeBuiltIn) != (rhs.transport == kAudioDeviceTransportTypeBuiltIn) {
                    return lhs.transport == kAudioDeviceTransportTypeBuiltIn
                }
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
        currentID = Self.defaultOutputID()
        watchVolume(of: currentID)
        readVolume()
    }

    private func readVolume() {
        var volumeAddress = Self.address(kAudioHardwareServiceDeviceProperty_VirtualMainVolume, scope: kAudioDevicePropertyScopeOutput)
        hasVolumeControl = AudioObjectHasProperty(currentID, &volumeAddress)
        if hasVolumeControl {
            var value: Float = 0
            var size = UInt32(MemoryLayout<Float>.size)
            if AudioObjectGetPropertyData(currentID, &volumeAddress, 0, nil, &size, &value) == noErr { volume = value }
        }
        var muteAddress = Self.address(kAudioDevicePropertyMute, scope: kAudioDevicePropertyScopeOutput)
        var muted: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        if AudioObjectHasProperty(currentID, &muteAddress),
           AudioObjectGetPropertyData(currentID, &muteAddress, 0, nil, &size, &muted) == noErr
        {
            isMuted = muted != 0
        } else {
            isMuted = false
        }
    }

    /// Moves the volume/mute listeners to the current default device.
    private func watchVolume(of device: AudioDeviceID) {
        guard device != volumeListenerDevice else { return }
        var volumeAddress = Self.address(kAudioHardwareServiceDeviceProperty_VirtualMainVolume, scope: kAudioDevicePropertyScopeOutput)
        var muteAddress = Self.address(kAudioDevicePropertyMute, scope: kAudioDevicePropertyScopeOutput)
        if volumeListenerDevice != kAudioObjectUnknown {
            AudioObjectRemovePropertyListenerBlock(volumeListenerDevice, &volumeAddress, queue, volumeListener)
            AudioObjectRemovePropertyListenerBlock(volumeListenerDevice, &muteAddress, queue, volumeListener)
        }
        volumeListenerDevice = device
        guard device != kAudioObjectUnknown else { return }
        AudioObjectAddPropertyListenerBlock(device, &volumeAddress, queue, volumeListener)
        AudioObjectAddPropertyListenerBlock(device, &muteAddress, queue, volumeListener)
    }

    // MARK: CoreAudio helpers

    private static func address(
        _ selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal
    ) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
    }

    private static func allDeviceIDs() -> [AudioDeviceID] {
        var address = address(kAudioHardwarePropertyDevices)
        var size: UInt32 = 0
        let system = AudioObjectID(kAudioObjectSystemObject)
        guard AudioObjectGetPropertyDataSize(system, &address, 0, nil, &size) == noErr else { return [] }
        var ids = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(system, &address, 0, nil, &size, &ids) == noErr else { return [] }
        return ids
    }

    private static func defaultOutputID() -> AudioDeviceID {
        var address = address(kAudioHardwarePropertyDefaultOutputDevice)
        var id = AudioDeviceID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &id)
        return id
    }

    private static func hasOutputStreams(_ id: AudioDeviceID) -> Bool {
        var address = address(kAudioDevicePropertyStreams, scope: kAudioDevicePropertyScopeOutput)
        var size: UInt32 = 0
        return AudioObjectGetPropertyDataSize(id, &address, 0, nil, &size) == noErr && size > 0
    }

    private static func isHidden(_ id: AudioDeviceID) -> Bool {
        var address = address(kAudioDevicePropertyIsHidden)
        var hidden: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        return AudioObjectGetPropertyData(id, &address, 0, nil, &size, &hidden) == noErr && hidden != 0
    }

    private static func name(of id: AudioDeviceID) -> String {
        var address = address(kAudioObjectPropertyName)
        var name: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, &name) == noErr, let name else { return "Unknown" }
        return name.takeRetainedValue() as String
    }

    private static func transport(of id: AudioDeviceID) -> UInt32 {
        var address = address(kAudioDevicePropertyTransportType)
        var transport: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        AudioObjectGetPropertyData(id, &address, 0, nil, &size, &transport)
        return transport
    }
}
