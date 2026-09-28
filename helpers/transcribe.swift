import Foundation
setvbuf(stdout, nil, _IONBF, 0)
import Speech

guard CommandLine.arguments.count > 2 else {
    print("usage: transcribe <audioPath> <outputTextPath>")
    exit(1)
}
let path = CommandLine.arguments[1]
let outPath = CommandLine.arguments[2]

func writeResult(_ text: String) {
    try? text.write(toFile: outPath, atomically: true, encoding: .utf8)
}

var finished = false
var finalText = ""

SFSpeechRecognizer.requestAuthorization { status in
    print("AUTH STATUS: \(status.rawValue)")
    guard status == .authorized else {
        writeResult("")
        finished = true
        return
    }
    guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US")), recognizer.isAvailable else {
        print("RECOGNIZER UNAVAILABLE")
        writeResult("")
        finished = true
        return
    }
    let request = SFSpeechURLRecognitionRequest(url: URL(fileURLWithPath: path))
    request.requiresOnDeviceRecognition = true
    print("STARTING RECOGNITION TASK")
    recognizer.recognitionTask(with: request) { result, error in
        if let error = error {
            print("TRANSCRIBE ERROR: \(error)")
            writeResult("")
            finished = true
            return
        }
        if let result = result {
            print("GOT RESULT, isFinal=\(result.isFinal): \(result.bestTranscription.formattedString)")
            if result.isFinal {
                finalText = result.bestTranscription.formattedString
                writeResult(finalText)
                finished = true
            }
        }
    }
}

let deadline = Date().addingTimeInterval(20)
while !finished && Date() < deadline {
    RunLoop.current.run(until: Date().addingTimeInterval(0.1))
}
if !finished {
    print("TIMED OUT WAITING FOR RESULT")
    writeResult("")
}
print("DONE")
exit(0)
