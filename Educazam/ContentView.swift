import AVFoundation
import Combine
import SwiftUI

@MainActor
final class RadioPlayer: ObservableObject {
    @Published private(set) var isPlaying = false
    @Published private(set) var statusMessage = "Conectando à rádio…"
    @Published var isMuted = false {
        didSet { player.isMuted = isMuted }
    }

    private let player = AVPlayer()
    private var itemObservation: NSKeyValueObservation?
    private var playbackObservation: NSKeyValueObservation?

    init() {
        let item = AVPlayerItem(url: URL(string: "https://streaming.ima.sp.gov.br/educativa.mp3")!)
        item.preferredForwardBufferDuration = 3
        player.replaceCurrentItem(with: item)
        player.isMuted = isMuted
        player.automaticallyWaitsToMinimizeStalling = true

        itemObservation = item.observe(\.status, options: [.initial, .new]) { [weak self] item, _ in
            Task { @MainActor in
                guard let self else { return }
                if item.status == .failed {
                    self.statusMessage = "Não foi possível carregar a transmissão. Toque em Tentar novamente."
                    self.isPlaying = false
                } else if item.status == .readyToPlay {
                    self.statusMessage = "Transmissão carregada"
                }
            }
        }
        playbackObservation = player.observe(\.timeControlStatus, options: [.initial, .new]) { [weak self] player, _ in
            Task { @MainActor in
                guard let self else { return }
                switch player.timeControlStatus {
                case .playing:
                    self.isPlaying = true
                    self.statusMessage = "Ao vivo"
                case .waitingToPlayAtSpecifiedRate:
                    self.isPlaying = false
                    self.statusMessage = "Conectando ou aguardando o sinal…"
                case .paused:
                    self.isPlaying = false
                    if player.currentItem?.status == .readyToPlay {
                        self.statusMessage = "Pausada"
                    }
                @unknown default:
                    self.isPlaying = false
                }
            }
        }
    }

    func play() {
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try AVAudioSession.sharedInstance().setActive(true)
            statusMessage = "Conectando à Rádio Educativa…"
            player.playImmediately(atRate: 1)
        } catch {
            statusMessage = "Erro de áudio: \(error.localizedDescription)"
            isPlaying = false
        }
    }

    func pause() {
        player.pause()
        isPlaying = false
        statusMessage = "Pausada"
    }
}

struct ContentView: View {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var radio = RadioPlayer()

    var body: some View {
        VStack(spacing: 28) {
            Spacer()

            Image(systemName: "dot.radiowaves.left.and.right")
                .font(.system(size: 42, weight: .light))
                .foregroundStyle(.black)

            VStack(spacing: 8) {
                Text("Rádio Educativa")
                    .font(.system(size: 28, weight: .semibold, design: .rounded))
                    .foregroundStyle(.black)
                Text(radio.statusMessage)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Text("A identificação de músicas está desativada nesta versão.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 260)

            HStack(spacing: 16) {
                Button {
                    radio.isPlaying ? radio.pause() : radio.play()
                } label: {
                    Label(radio.isPlaying ? "Pausar" : "Tocar", systemImage: radio.isPlaying ? "pause.fill" : "play.fill")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 15)
                }
                .buttonStyle(.borderedProminent)
                .tint(.black)

                Button {
                    radio.isMuted.toggle()
                } label: {
                    Label(radio.isMuted ? "Sem áudio" : "Com áudio", systemImage: radio.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 15)
                }
                .buttonStyle(.bordered)
                .tint(.black)
            }

            Spacer()
        }
        .padding(28)
        .background(.white)
        .preferredColorScheme(.light)
        .onAppear { radio.play() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                if !radio.isPlaying { radio.play() }
            } else if phase == .background {
                radio.pause()
            }
        }
    }
}
