import AVFoundation
import Combine
import MediaPlayer
import SwiftUI
import UIKit

@MainActor
final class RadioPlayer: ObservableObject {
    @Published private(set) var isPlaying = false
    @Published private(set) var statusMessage = "Conectando à rádio…"
    @Published var isMuted = true {
        didSet { player.isMuted = isMuted }
    }

    private let streamURL = URL(string: "https://streaming.ima.sp.gov.br/educativa.mp3")!
    private let player = AVPlayer()
    private let nowPlayingSession: MPNowPlayingSession
    private var currentItem: AVPlayerItem?
    private var isPreparingItem = false
    private var wantsPlayback = false
    private var itemObservation: NSKeyValueObservation?
    private var playbackObservation: NSKeyValueObservation?
    private var remoteCommandCenter: MPRemoteCommandCenter { nowPlayingSession.remoteCommandCenter }

    init() {
        nowPlayingSession = MPNowPlayingSession(players: [player])
        nowPlayingSession.automaticallyPublishesNowPlayingInfo = false
        player.isMuted = isMuted
        player.automaticallyWaitsToMinimizeStalling = true
        configureRemoteCommands()

        playbackObservation = player.observe(\.timeControlStatus, options: [.initial, .new]) { [weak self] player, _ in
            Task { @MainActor in
                guard let self else { return }
                switch player.timeControlStatus {
                case .playing:
                    self.isPlaying = true
                    self.statusMessage = "Ao vivo"
                    self.updateNowPlayingInfo(isPlaying: true)
                case .waitingToPlayAtSpecifiedRate:
                    self.isPlaying = false
                    self.statusMessage = "Conectando ou aguardando o sinal…"
                    // Keep the Now Playing card active while AVPlayer buffers.
                    self.updateNowPlayingInfo(isPlaying: self.wantsPlayback)
                case .paused:
                    self.isPlaying = false
                    self.updateNowPlayingInfo(isPlaying: false)
                    if self.wantsPlayback == false {
                        self.statusMessage = "Pausada"
                    }
                @unknown default:
                    self.isPlaying = false
                }
            }
        }
    }

    func play() {
        wantsPlayback = true
        updateNowPlayingInfo(isPlaying: true)
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            statusMessage = "Erro ao configurar o áudio: \(error.localizedDescription)"
        }

        if let currentItem {
            if currentItem.status == .failed {
                currentItem.cancelPendingSeeks()
                prepareRadioItem()
            } else {
                player.playImmediately(atRate: 1)
            }
        } else {
            prepareRadioItem()
        }
    }

    func pause() {
        wantsPlayback = false
        player.pause()
        isPlaying = false
        statusMessage = "Pausada"
        updateNowPlayingInfo(isPlaying: false)
    }

    private func prepareRadioItem() {
        guard !isPreparingItem else { return }
        isPreparingItem = true
        statusMessage = "Conectando à Rádio Educativa…"

        let item = AVPlayerItem(url: streamURL)
        item.preferredForwardBufferDuration = 3
        install(item: item)
    }

    private func install(item: AVPlayerItem) {
        currentItem = item
        isPreparingItem = false
        itemObservation = item.observe(\.status, options: [.initial, .new]) { [weak self] item, _ in
            Task { @MainActor in
                guard let self else { return }
                if item.status == .failed {
                    self.statusMessage = "Não foi possível carregar a rádio: \(item.error?.localizedDescription ?? "erro desconhecido")"
                    self.isPlaying = false
                    self.wantsPlayback = false
                    self.updateNowPlayingInfo(isPlaying: false)
                }
            }
        }

        player.replaceCurrentItem(with: item)
        if wantsPlayback {
            player.playImmediately(atRate: 1)
        }
    }

    private func configureRemoteCommands() {
        remoteCommandCenter.playCommand.isEnabled = true
        remoteCommandCenter.pauseCommand.isEnabled = true
        remoteCommandCenter.togglePlayPauseCommand.isEnabled = true
        remoteCommandCenter.nextTrackCommand.isEnabled = false
        remoteCommandCenter.previousTrackCommand.isEnabled = false
        remoteCommandCenter.changePlaybackPositionCommand.isEnabled = false

        remoteCommandCenter.playCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.play() }
            return .success
        }
        remoteCommandCenter.pauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.pause() }
            return .success
        }
        remoteCommandCenter.togglePlayPauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.wantsPlayback ? self.pause() : self.play()
            }
            return .success
        }
    }

    private func updateNowPlayingInfo(isPlaying: Bool) {
        let info: [String: Any] = [
            MPMediaItemPropertyTitle: "Educazam",
            MPMediaItemPropertyArtist: "Rádio Educativa Campinas",
            MPMediaItemPropertyAlbumTitle: "Transmissão ao vivo",
            MPNowPlayingInfoPropertyMediaType: MPNowPlayingInfoMediaType.audio.rawValue,
            MPNowPlayingInfoPropertyIsLiveStream: true,
            MPNowPlayingInfoPropertyDefaultPlaybackRate: 1.0,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0
        ]
        nowPlayingSession.nowPlayingInfoCenter.nowPlayingInfo = info
        if isPlaying && !nowPlayingSession.isActive {
            nowPlayingSession.becomeActiveIfPossible { isActive in
                if !isActive {
                    NSLog("Educazam: o iOS não ativou a sessão Now Playing.")
                }
            }
        }
    }
}

struct ContentView: View {
    @StateObject private var radio = RadioPlayer()
    @StateObject private var motion = ContentViewMotion()

    private let ink = Color(red: 0.12, green: 0.14, blue: 0.24)
    private let coral = Color(red: 0.96, green: 0.34, blue: 0.30)
    private let violet = Color(red: 0.37, green: 0.32, blue: 0.91)

    var body: some View {
        VStack(spacing: 30) {
            Spacer()

            radioArtwork

            VStack(spacing: 10) {
                Text("Rádio Educativa")
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .tracking(-0.7)
                    .foregroundStyle(ink)

                HStack(spacing: 7) {
                    Circle()
                        .fill(radio.isPlaying ? Color(red: 0.16, green: 0.66, blue: 0.48) : .orange)
                        .frame(width: 7, height: 7)
                    Text(radio.statusMessage)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            }

            HStack(spacing: 14) {
                actionCard(
                    title: radio.isMuted ? "Ativar som" : "Mutar rádio",
                    subtitle: radio.isMuted ? "Rádio no mudo" : "Som ligado",
                    symbol: radio.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill",
                    animationTrigger: radio.isMuted ? 1 : 0,
                    colors: radio.isMuted
                        ? [Color(red: 0.98, green: 0.48, blue: 0.35), coral]
                        : [Color(red: 0.19, green: 0.70, blue: 0.62), Color(red: 0.10, green: 0.55, blue: 0.54)],
                    accessibilityLabel: radio.isMuted ? "Ativar som da rádio" : "Mutar rádio"
                ) {
                    withAnimation(.spring(response: 0.34, dampingFraction: 0.62)) {
                        radio.isMuted.toggle()
                    }
                }

                actionCard(
                    title: "Abrir Shazam",
                    subtitle: "Descobrir a música",
                    symbol: "waveform",
                    animationTrigger: motion.shazamTap,
                    colors: [violet, Color(red: 0.57, green: 0.34, blue: 0.88)],
                    accessibilityLabel: "Identificar música com o atalho do Shazam"
                ) {
                    motion.shazamTap += 1
                    runShazamShortcut()
                }
            }
            .frame(maxWidth: 560)

            Spacer()
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            LinearGradient(
                colors: [Color(red: 1.0, green: 0.98, blue: 0.96), Color(red: 0.96, green: 0.96, blue: 1.0)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
        }
        .preferredColorScheme(.light)
        .onAppear {
            radio.play()
            withAnimation(.easeInOut(duration: 2.1).repeatForever(autoreverses: true)) {
                motion.radioPulse = true
            }
        }
    }

    private var radioArtwork: some View {
        ZStack {
            Circle()
                .stroke(coral.opacity(motion.radioPulse ? 0.03 : 0.14), lineWidth: 1)
                .frame(width: motion.radioPulse ? 154 : 126, height: motion.radioPulse ? 154 : 126)
            Circle()
                .stroke(violet.opacity(motion.radioPulse ? 0.07 : 0.16), lineWidth: 1)
                .frame(width: motion.radioPulse ? 124 : 104, height: motion.radioPulse ? 124 : 104)
            Circle()
                .fill(LinearGradient(colors: [Color.white, Color(red: 1, green: 0.91, blue: 0.88)], startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: 88, height: 88)
                .shadow(color: coral.opacity(0.18), radius: 22, y: 10)
            Image(systemName: "dot.radiowaves.left.and.right")
                .font(.system(size: 39, weight: .medium))
                .symbolRenderingMode(.palette)
                .foregroundStyle(violet, coral)
                .scaleEffect(motion.radioPulse ? 1.04 : 0.96)
                .animation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true), value: motion.radioPulse)
        }
        .frame(width: 160, height: 160)
        .accessibilityHidden(true)
    }

    private func actionCard(
        title: String,
        subtitle: String,
        symbol: String,
        animationTrigger: Int,
        colors: [Color],
        accessibilityLabel: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 14) {
                Image(systemName: symbol)
                    .font(.system(size: 23, weight: .semibold))
                    .symbolEffect(.bounce, value: animationTrigger)
                    .frame(width: 48, height: 48)
                    .background(.white.opacity(0.2), in: RoundedRectangle(cornerRadius: 16, style: .continuous))

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Text(subtitle)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white.opacity(0.8))
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, minHeight: 132, alignment: .leading)
            .padding(16)
            .background {
                RoundedRectangle(cornerRadius: 25, style: .continuous)
                    .fill(LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing))
                    .overlay(alignment: .topTrailing) {
                        Circle()
                            .fill(.white.opacity(0.10))
                            .frame(width: 100, height: 100)
                            .offset(x: 30, y: -36)
                            .clipShape(RoundedRectangle(cornerRadius: 25, style: .continuous))
                    }
                    .shadow(color: colors.last!.opacity(0.22), radius: 14, y: 8)
            }
            .contentShape(RoundedRectangle(cornerRadius: 25, style: .continuous))
        }
        .buttonStyle(ActionCardButtonStyle())
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint(subtitle)
    }

    private func runShazamShortcut() {
        var components = URLComponents()
        components.scheme = "shortcuts"
        components.host = "run-shortcut"
        components.queryItems = [URLQueryItem(name: "name", value: "Atalho do Shazam")]

        guard let url = components.url else {
            return
        }

        UIApplication.shared.open(url)
    }

}

private struct ActionCardButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .brightness(configuration.isPressed ? 0.07 : 0)
            .animation(.spring(response: 0.28, dampingFraction: 0.62), value: configuration.isPressed)
    }
}

@MainActor
private final class ContentViewMotion: ObservableObject {
    @Published var radioPulse = false
    @Published var shazamTap = 0
}
