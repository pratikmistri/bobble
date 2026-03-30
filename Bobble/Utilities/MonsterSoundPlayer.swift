import AppKit
import Foundation

enum MonsterSoundCue {
    case turnStarted
    case turnCompleted
}

final class MonsterSoundPlayer {
    static let shared = MonsterSoundPlayer()

    private enum Resource {
        static let subdirectory = "Sounds"
        static let fileExtension = "wav"
        static let startGrowl = "monster-growl-start"
        static let completionGrowl = "monster-growl-complete"
    }

    private var cachedSounds: [MonsterSoundCue: NSSound] = [:]

    private init() {}

    func play(_ cue: MonsterSoundCue) {
        if Thread.isMainThread {
            playOnMainThread(cue)
            return
        }

        DispatchQueue.main.async { [weak self] in
            self?.playOnMainThread(cue)
        }
    }

    private func playOnMainThread(_ cue: MonsterSoundCue) {
        guard let sound = sound(for: cue) else { return }
        sound.stop()
        sound.play()
    }

    private func sound(for cue: MonsterSoundCue) -> NSSound? {
        if let cached = cachedSounds[cue] {
            return cached
        }

        let resourceName: String
        let volume: Float
        switch cue {
        case .turnStarted:
            resourceName = Resource.startGrowl
            volume = 0.65
        case .turnCompleted:
            resourceName = Resource.completionGrowl
            volume = 0.75
        }

        guard let url = soundURL(forResource: resourceName),
              let sound = NSSound(contentsOf: url, byReference: true) else {
            return nil
        }

        sound.volume = volume
        cachedSounds[cue] = sound
        return sound
    }

    private func soundURL(forResource resourceName: String) -> URL? {
        if let nested = Bundle.main.url(
            forResource: resourceName,
            withExtension: Resource.fileExtension,
            subdirectory: Resource.subdirectory
        ) {
            return nested
        }

        return Bundle.main.url(
            forResource: resourceName,
            withExtension: Resource.fileExtension
        )
    }
}
