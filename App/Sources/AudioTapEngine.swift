import CoreAudio
import Foundation
import CAudioRing

// Captures the system audio mix with a Core Audio process tap and buffers it for the
// render thread. The tap and aggregate-device setup is adapted from AudioCap,
// copyright (c) 2024 Guilherme Rambo, BSD 2-Clause licence
// (https://github.com/insidegui/AudioCap, licenses/AudioCap-BSD-2-Clause.txt).

final class AudioTapEngine {
    enum Error: Swift.Error {
        case coreAudio(String, OSStatus)
        case ringAllocation
    }

    private(set) var sampleRate = 44100.0
    private(set) var channelCount = 2

    private var tapID = AudioObjectID(kAudioObjectUnknown)
    private var aggregateID = AudioObjectID(kAudioObjectUnknown)
    private var ioProcID: AudioDeviceIOProcID?
    private var ring: OpaquePointer?
    private let queue = DispatchQueue(label: "fishtank.audio-tap", qos: .userInitiated)

    func start() throws {
        let description = CATapDescription(stereoGlobalTapButExcludeProcesses: [])
        description.uuid = UUID()
        description.muteBehavior = .unmuted

        var err = AudioHardwareCreateProcessTap(description, &tapID)
        guard err == noErr else { throw Error.coreAudio("create tap", err) }

        let format = try readTapStreamDescription()
        sampleRate = format.mSampleRate
        channelCount = Int(format.mChannelsPerFrame)

        let outputUID = try readDefaultOutputDeviceUID()
        let aggregate: [String: Any] = [
            kAudioAggregateDeviceNameKey: "Fishtank Tap",
            kAudioAggregateDeviceUIDKey: UUID().uuidString,
            kAudioAggregateDeviceMainSubDeviceKey: outputUID,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceSubDeviceListKey: [
                [kAudioSubDeviceUIDKey: outputUID]
            ],
            kAudioAggregateDeviceTapListKey: [
                [
                    kAudioSubTapDriftCompensationKey: true,
                    kAudioSubTapUIDKey: description.uuid.uuidString,
                ]
            ],
        ]
        err = AudioHardwareCreateAggregateDevice(aggregate as CFDictionary, &aggregateID)
        guard err == noErr else { throw Error.coreAudio("create aggregate device", err) }

        guard let ring = audio_ring_create(65536) else { throw Error.ringAllocation }
        self.ring = ring

        err = AudioDeviceCreateIOProcIDWithBlock(&ioProcID, aggregateID, queue) { _, inInputData, _, _, _ in
            let buffers = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: inInputData))
            for buffer in buffers {
                guard let data = buffer.mData else { continue }
                let count = Int(buffer.mDataByteSize) / MemoryLayout<Float>.size
                audio_ring_write(ring, data.assumingMemoryBound(to: Float.self), count)
            }
        }
        guard err == noErr else { throw Error.coreAudio("create IO proc", err) }

        err = AudioDeviceStart(aggregateID, ioProcID)
        guard err == noErr else { throw Error.coreAudio("start device", err) }
    }

    func read(into buffer: UnsafeMutablePointer<Float>, maxSamples: Int) -> Int {
        guard let ring else { return 0 }
        return audio_ring_read(ring, buffer, maxSamples)
    }

    func stop() {
        if aggregateID != kAudioObjectUnknown, let procID = ioProcID {
            AudioDeviceStop(aggregateID, procID)
            AudioDeviceDestroyIOProcID(aggregateID, procID)
            ioProcID = nil
        }
        if aggregateID != kAudioObjectUnknown {
            AudioHardwareDestroyAggregateDevice(aggregateID)
            aggregateID = AudioObjectID(kAudioObjectUnknown)
        }
        if tapID != kAudioObjectUnknown {
            AudioHardwareDestroyProcessTap(tapID)
            tapID = AudioObjectID(kAudioObjectUnknown)
        }
        if let ring {
            audio_ring_destroy(ring)
            self.ring = nil
        }
    }

    deinit {
        stop()
    }

    private func readTapStreamDescription() throws -> AudioStreamBasicDescription {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioTapPropertyFormat,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var format = AudioStreamBasicDescription()
        var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        let err = AudioObjectGetPropertyData(tapID, &address, 0, nil, &size, &format)
        guard err == noErr else { throw Error.coreAudio("read tap format", err) }
        return format
    }

    private func readDefaultOutputDeviceUID() throws -> String {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultSystemOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var deviceID = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        var err = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &deviceID
        )
        guard err == noErr else { throw Error.coreAudio("read default output device", err) }

        address.mSelector = kAudioDevicePropertyDeviceUID
        var uid: CFString = "" as CFString
        size = UInt32(MemoryLayout<CFString>.size)
        err = withUnsafeMutablePointer(to: &uid) { pointer in
            AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, pointer)
        }
        guard err == noErr else { throw Error.coreAudio("read device UID", err) }
        return uid as String
    }
}
