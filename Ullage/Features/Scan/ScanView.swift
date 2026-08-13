import PhotosUI
import SwiftData
import SwiftUI
import UllageCore
import UIKit

/// The main screen: photograph a bottle, watch it get researched, read the result.
///
/// Isolated to the main actor as a whole rather than relying on `body` alone: every computed
/// subview here reads the camera controller and the scan view model, both of which are
/// main-actor isolated.
@MainActor
struct ScanView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(\.modelContext) private var modelContext

    @State private var camera = CameraController()
    @State private var model: ScanViewModel
    @State private var photoSelection: PhotosPickerItem?
    @State private var isShowingSettings = false
    @State private var isShowingManualEntry = false
    @State private var manualEntry = ""
    @State private var savedDossierID: UUID?

    init(settings: AppSettings) {
        _model = State(initialValue: ScanViewModel(makeService: { settings.makeIntelligenceService() }))
    }

    var body: some View {
        NavigationStack {
            Group {
                switch model.phase {
                case .composing:
                    captureScreen
                case .working:
                    workingScreen
                case .finished:
                    if let dossier = model.dossier {
                        DossierView(
                            dossier: dossier,
                            labelImage: model.images.first?.image,
                            onSave: { save(dossier) },
                            isSaved: savedDossierID == dossier.id
                        )
                    }
                case .failed:
                    failureScreen
                }
            }
            .navigationTitle(navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbarContent }
            .sheet(isPresented: $isShowingSettings) {
                SettingsView()
            }
            .alert("Describe the bottle", isPresented: $isShowingManualEntry) {
                TextField("Producer, wine and vintage", text: $manualEntry)
                    .textInputAutocapitalization(.words)
                Button("Cancel", role: .cancel) {}
                Button("Research") {
                    model.research(manualEntry: manualEntry)
                }
            } message: {
                Text("For example: Ridge Monte Bello 2016. Ullage will research it without a photo.")
            }
            .task {
                await camera.prepare()
            }
            .onChange(of: photoSelection) { _, selection in
                guard let selection else { return }
                Task { await importPhoto(selection) }
            }
            .onChange(of: model.phase) { _, phase in
                // The viewfinder is pointless while research runs, and it costs battery.
                if phase == .working { camera.stop() } else if phase == .composing { camera.start() }
            }
        }
    }

    private var navigationTitle: String {
        switch model.phase {
        case .composing: return "Ullage"
        case .working: return model.reading?.displayTitle ?? "Researching"
        case .finished: return model.dossier?.identity.vintageText ?? "Wine"
        case .failed: return "No luck"
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            if model.phase == .composing {
                NavigationLink {
                    CellarView()
                } label: {
                    Label("Cellar", systemImage: "square.stack.3d.up")
                }
            } else {
                Button("New scan", systemImage: "arrow.counterclockwise") {
                    savedDossierID = nil
                    model.reset()
                }
            }
        }
        ToolbarItem(placement: .topBarTrailing) {
            Button("Settings", systemImage: "gearshape") {
                isShowingSettings = true
            }
        }
    }

    // MARK: - Capture

    private var captureScreen: some View {
        VStack(spacing: 0) {
            viewfinder
                .frame(maxHeight: .infinity)

            VStack(spacing: 14) {
                if settings.isInDemoMode {
                    demoBanner
                }

                if !model.images.isEmpty {
                    thumbnailStrip
                }

                HStack(spacing: 20) {
                    PhotosPicker(selection: $photoSelection, matching: .images) {
                        Label("Library", systemImage: "photo.on.rectangle")
                            .font(.callout)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)

                    Button {
                        Task { await capture() }
                    } label: {
                        Label("Capture", systemImage: "camera.fill")
                            .font(.callout.weight(.semibold))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(camera.authorization != .authorized || camera.isCapturing)
                }

                Button {
                    model.start()
                } label: {
                    Text(model.images.count > 1 ? "Identify from \(model.images.count) photos" : "Identify this wine")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .tint(Theme.accent)
                .disabled(!model.canStart)

                Button("Type it in instead") {
                    manualEntry = ""
                    isShowingManualEntry = true
                }
                .font(.footnote)
            }
            .padding()
            .background(.bar)
        }
    }

    @ViewBuilder
    private var viewfinder: some View {
        ZStack {
            switch camera.authorization {
            case .authorized:
                CameraPreviewView(session: camera.session)
                    .overlay(alignment: .center) { framingGuide }
                    .overlay(alignment: .topTrailing) { torchButton }
                    .overlay(alignment: .bottom) { hint }
            case .notDetermined:
                ProgressView("Starting the camera")
            case .denied, .restricted:
                cameraUnavailable(
                    title: "Camera access is off",
                    message: "Turn it on in Settings, or pick a photo from your library.",
                    showsSystemSettings: true
                )
            case .unavailable:
                cameraUnavailable(
                    title: "No camera here",
                    message: "Choose a photo of a label from your library instead.",
                    showsSystemSettings: false
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
    }

    /// A frame to line the bottle up in. Not a scanning region — the whole image is sent — but
    /// it does get people to fill the frame, which is the single biggest factor in whether the
    /// small print comes out legible.
    private var framingGuide: some View {
        RoundedRectangle(cornerRadius: 18)
            .stroke(.white.opacity(0.6), style: StrokeStyle(lineWidth: 2, dash: [10, 8]))
            .padding(.horizontal, 44)
            .padding(.vertical, 80)
            .allowsHitTesting(false)
    }

    private var hint: some View {
        Text(model.images.isEmpty
             ? "Fill the frame with the front label"
             : "Now the back label, if there is one")
            .font(.footnote)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(.black.opacity(0.45), in: Capsule())
            .foregroundStyle(.white)
            .padding(.bottom, 20)
    }

    @ViewBuilder
    private var torchButton: some View {
        if camera.isTorchAvailable {
            Button {
                camera.toggleTorch()
            } label: {
                Image(systemName: camera.isTorchOn ? "bolt.fill" : "bolt.slash")
                    .padding(10)
                    .background(.black.opacity(0.45), in: Circle())
                    .foregroundStyle(.white)
            }
            .padding()
        }
    }

    private func cameraUnavailable(title: String, message: String, showsSystemSettings: Bool) -> some View {
        ContentUnavailableView {
            Label(title, systemImage: "camera.metering.unknown")
        } description: {
            Text(message)
        } actions: {
            if showsSystemSettings, let url = URL(string: UIApplication.openSettingsURLString) {
                Link("Open Settings", destination: url)
            }
        }
        .foregroundStyle(.white)
    }

    private var thumbnailStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(model.images) { captured in
                    VStack(spacing: 4) {
                        Image(uiImage: captured.image)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 56, height: 74)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .overlay(alignment: .topTrailing) {
                                Button {
                                    model.remove(captured)
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundStyle(.white, .black.opacity(0.6))
                                }
                                .padding(2)
                            }
                        Text(captured.role.displayName)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.horizontal, 2)
        }
        .frame(height: 96)
    }

    private var demoBanner: some View {
        Button {
            isShowingSettings = true
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "sparkles")
                VStack(alignment: .leading, spacing: 1) {
                    Text("Demo mode").font(.caption.weight(.semibold))
                    Text("Add an OpenAI key to scan real bottles")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.caption2)
            }
            .padding(10)
            .background(Theme.accent.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Working and failure

    private var workingScreen: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                if let reading = model.reading {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(reading.displayTitle)
                            .font(.title2.weight(.semibold))
                        if let subtitle = reading.displaySubtitle {
                            Text(subtitle).foregroundStyle(.secondary)
                        }
                        if reading.confidence.warrantsConfirmation {
                            Label(
                                "Not certain about this — checking it against what's online",
                                systemImage: "questionmark.circle"
                            )
                            .font(.caption)
                            .foregroundStyle(.orange)
                        }
                    }
                }

                ResearchLogView(log: model.log)

                Button("Cancel", role: .cancel) {
                    model.cancel()
                }
                .font(.footnote)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
        }
    }

    private var failureScreen: some View {
        ContentUnavailableView {
            Label("Couldn't identify that", systemImage: "questionmark.diamond")
        } description: {
            VStack(spacing: 8) {
                if let message = model.errorMessage {
                    Text(message)
                }
                if let suggestion = model.errorSuggestion {
                    Text(suggestion).font(.footnote)
                }
            }
        } actions: {
            VStack(spacing: 12) {
                if model.isRetryable {
                    Button("Try again") { model.retry() }
                        .buttonStyle(.borderedProminent)
                        .tint(Theme.accent)
                }
                Button("Start over") {
                    model.reset()
                }
                Button("Type it in instead") {
                    manualEntry = model.reading?.researchSubject ?? ""
                    isShowingManualEntry = true
                }
                .font(.footnote)
            }
        }
    }

    // MARK: - Actions

    private func capture() async {
        do {
            let image = try await camera.capturePhoto()
            model.add(image)
        } catch {
            // A failed shutter is self-evident on screen; there is nothing useful to say.
        }
    }

    private func importPhoto(_ item: PhotosPickerItem) async {
        defer { photoSelection = nil }
        guard let data = try? await item.loadTransferable(type: Data.self),
              let image = UIImage(data: data) else { return }
        model.add(image)
    }

    private func save(_ dossier: WineDossier) {
        let thumbnail = model.images.first.flatMap { ImagePreparer.thumbnail($0.image) }
        modelContext.insert(ScanRecord(dossier: dossier, thumbnailData: thumbnail))
        try? modelContext.save()
        savedDossierID = dossier.id
    }
}
