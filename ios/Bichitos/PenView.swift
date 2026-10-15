import os
import SwiftUI

/// Keeps the world across launches: opens the pen and fast-forwards the time away (off the main thread),
/// saves when the app leaves the foreground and every 30 s, and tells what happened meanwhile.
struct PenView<Content: View>: View {
    let content: (WorldScene) -> Content

    init(@ViewBuilder content: @escaping (WorldScene) -> Content) { self.content = content }

    @Environment(\.scenePhase) private var phase
    // Screenshot launches (CI) never touch the real save.
    @State private var pen: Pen? = CommandLine.arguments.contains { $0.hasPrefix("-screenshot") } ? nil : Pen()
    @State private var scene: WorldScene?
    @State private var lastSaved = Date()
    @State private var wasInBackground = false
    @State private var catchingUp = false
    @State private var slow = false
    @State private var away: [String] = []
    @State private var showAway = false
    @State private var broken: Pen.Opening?
    private let log = Logger(subsystem: "com.santilega.bichitos", category: "pen")

    var body: some View {
        ZStack {
            Color.mist.ignoresSafeArea()
            if let scene { content(scene) }
            if slow {
                Text(language == .es ? "Mientras no estabas…" : "While you were away…")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.inkDim)
            }
        }
        .task { await open() }
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30))
                if phase == .active { save() }
            }
        }
        .onChange(of: phase) { _, now in
            switch now {
            case .background: save(); wasInBackground = true
            case .inactive: save()
            case .active:
                if wasInBackground { Task { await resume() } }
                wasInBackground = false
            @unknown default: break
            }
        }
        .sheet(isPresented: $showAway) { AwaySummary(lines: away, language: language) }
        .alert(language == .es ? "Tu terrario no se pudo abrir" : "Your terrarium couldn't be opened",
               isPresented: Binding(get: { broken != nil }, set: { if !$0 { broken = nil } })) {
            Button("OK") {}
        } message: {
            if broken?.backup != nil {
                Text(language == .es ? "Guardamos una copia del archivo dañado y empezamos uno nuevo."
                                     : "We kept a copy of the damaged file and started a new one.")
            } else {
                Text(language == .es ? "No se pudo apartar el archivo dañado, así que esta vez no se guardará nada."
                                     : "The damaged file couldn't be moved aside, so nothing will be saved this time.")
            }
        }
    }

    private var language: Language { scene?.world.language ?? .es }

    private func open() async {
        let args = CommandLine.arguments
        if args.contains("-screenshot") {
            // `-border` stages the edge between two districts instead.
            scene = args.contains("-border") ? Terrarium.border() : Terrarium.screenshot()
            return
        }
        let pen = self.pen
        show(await offMain {
            if args.contains("-screenshot-away") { return Pen.fastForward(Terrarium.away(), from: Date() - 3 * 3600, to: Date()) }
            return pen?.open() ?? Pen.Opening()
        })
    }

    /// Back from the background: the scene stood still meanwhile, so fast-forward the time away too.
    private func resume() async {
        guard let scene, pen != nil, !catchingUp else { return }
        scene.isPaused = true
        let world = scene.world, since = lastSaved
        show(await offMain { Pen.fastForward(world, from: since, to: Date()) })
    }

    /// Runs the fast-forward off the main thread; past 0.3 s it says so on screen.
    private func offMain(_ work: @escaping @Sendable () -> Pen.Opening) async -> Pen.Opening {
        catchingUp = true
        let hint = Task {
            try? await Task.sleep(for: .milliseconds(300))
            if !Task.isCancelled { slow = true }
        }
        let opening = await Task.detached(priority: .userInitiated, operation: work).value
        hint.cancel()
        slow = false
        catchingUp = false
        return opening
    }

    private func show(_ opening: Pen.Opening) {
        if let world = opening.world {
            log.notice("catch-up took \(opening.took, format: .fixed(precision: 3)) s, \(opening.away.count) summary lines")
            if let scene {
                scene.fastForwarded(to: world)
                scene.isPaused = false
            } else {
                scene = WorldScene(world: world)
            }
        } else if scene == nil {
            scene = Terrarium.random()
        }
        if opening.broken {
            log.error("broken save, backup: \(opening.backup?.path ?? "none", privacy: .public)")
            if opening.backup == nil { pen = nil }
            broken = opening
        }
        lastSaved = Date()
        away = opening.away
        showAway = !away.isEmpty
    }

    private func save() {
        guard let pen, let scene, !catchingUp else { return }
        let now = Date()
        do {
            try pen.save(scene.world, at: now)
            lastSaved = now
        } catch {
            log.error("save failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}

/// "Mientras no estabas": what happened while the app was closed.
struct AwaySummary: View {
    let lines: [String]
    let language: Language
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(language == .es ? "Mientras no estabas" : "While you were away")
                .font(.system(size: 18, weight: .heavy, design: .rounded))
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(lines, id: \.self) { line in
                        Text(line)
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            Button(language == .es ? "¡Vale!" : "Got it") { dismiss() }
                .buttonStyle(PrimaryButtonStyle())
        }
        .foregroundStyle(Color.ink)
        .padding(24)
        .presentationDetents([.medium, .large])
        .presentationCornerRadius(28)
        .presentationBackground(Color.card)
    }
}
