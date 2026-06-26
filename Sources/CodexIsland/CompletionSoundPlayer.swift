import AppKit
import Foundation

final class CompletionSoundPlayer {
    static let shared = CompletionSoundPlayer()

    private let cooldown: TimeInterval = 10
    private var lastPlayDate: Date = .distantPast
    private var sound: NSSound?

    private init() {}

    func playCompleted() {
        let now = Date()
        guard now.timeIntervalSince(lastPlayDate) >= cooldown else { return }
        lastPlayDate = now

        guard let sound = completionSound() else { return }
        sound.stop()
        sound.currentTime = 0
        sound.play()
    }

    private func completionSound() -> NSSound? {
        if let sound { return sound }

        guard let url = Bundle.module.url(forResource: "complete", withExtension: "mp3") else {
            return nil
        }

        let loaded = NSSound(contentsOf: url, byReference: false)
        loaded?.volume = 1.0
        sound = loaded
        return loaded
    }
}
