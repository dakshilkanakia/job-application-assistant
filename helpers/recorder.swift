import Foundation
setvbuf(stdout, nil, _IONBF, 0)
import AVFoundation
import ScreenCaptureKit

guard CommandLine.arguments.count > 2 else {
    print("usage: recorder <micOutPath> <sysOutPath>")
    exit(1)
}
let micPath = CommandLine.arguments[1]
let sysPath = CommandLine.arguments[2]

let engine = AVAudioEngine()
let inputNode = engine.inputNode
let inputFormat = inputNode.outputFormat(forBus: 0)
var micFile: AVAudioFile?
do {
    micFile = try AVAudioFile(forWriting: URL(fileURLWithPath: micPath), settings: inputFormat.settings)
} catch {
    print("MIC FILE OPEN FAILED: \(error)")
}
inputNode.installTap(onBus: 0, bufferSize: 1024, format: inputFormat) { buffer, _ in
    try? micFile?.write(from: buffer)
}
do {
    try engine.start()
    print("MIC STARTED")
} catch {
    print("MIC START FAILED: \(error)")
}

class SysAudioRecorder: NSObject, SCStreamOutput, SCStreamDelegate {
    var writer: AVAssetWriter?
    var input: AVAssetWriterInput?
    var started = false
    func setup(path: String) {
        let url = URL(fileURLWithPath: path)
        try? FileManager.default.removeItem(at: url)
        writer = try? AVAssetWriter(outputURL: url, fileType: .m4a)
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 48000,
            AVNumberOfChannelsKey: 2,
            AVEncoderBitRateKey: 128000
        ]
        input = AVAssetWriterInput(mediaType: .audio, outputSettings: settings)
        input?.expectsMediaDataInRealTime = true
        if let input = input, writer?.canAdd(input) == true { writer?.add(input) }
    }
    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .audio, sampleBuffer.isValid, CMSampleBufferDataIsReady(sampleBuffer) else { return }
        guard let writer = writer, let input = input else { return }
        if !started {
            writer.startWriting()
            writer.startSession(atSourceTime: CMSampleBufferGetPresentationTimeStamp(sampleBuffer))
            started = true
            print("SYS AUDIO STARTED")
        }
        if input.isReadyForMoreMediaData { input.append(sampleBuffer) }
    }
    func stream(_ stream: SCStream, didStopWithError error: Error) {
        print("SYS STREAM ERROR: \(error)")
    }
    func finish(completion: @escaping () -> Void) {
        guard started, let input = input, let writer = writer else { completion(); return }
        input.markAsFinished()
        writer.finishWriting(completionHandler: completion)
    }
}
let recorder = SysAudioRecorder()
recorder.setup(path: sysPath)
var sysStream: SCStream?

Task {
    do {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let display = content.displays.first else { print("NO DISPLAY"); return }
        let filter = SCContentFilter(display: display, excludingApplications: [], exceptingWindows: [])
        let config = SCStreamConfiguration()
        config.capturesAudio = true
        config.excludesCurrentProcessAudio = true
        config.width = 2
        config.height = 2
        config.minimumFrameInterval = CMTime(value: 1, timescale: 1)
        let stream = SCStream(filter: filter, configuration: config, delegate: recorder)
        sysStream = stream
        try stream.addStreamOutput(recorder, type: .audio, sampleHandlerQueue: DispatchQueue(label: "audio.queue"))
        try await stream.startCapture()
        print("SYS CAPTURE STARTED")
    } catch {
        print("SYS CAPTURE FAILED: \(error)")
    }
}

var shouldStop = false
signal(SIGTERM) { _ in shouldStop = true }
signal(SIGINT) { _ in shouldStop = true }

while !shouldStop {
    RunLoop.current.run(until: Date().addingTimeInterval(0.1))
}

print("STOPPING")
engine.stop()
inputNode.removeTap(onBus: 0)
micFile = nil

var sysFinished = false
Task {
    if let s = sysStream { try? await s.stopCapture() }
    recorder.finish { sysFinished = true }
}
while !sysFinished {
    RunLoop.current.run(until: Date().addingTimeInterval(0.05))
}

print("DONE")
exit(0)
