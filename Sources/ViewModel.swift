import Foundation
import AppKit

@MainActor
final class InstallerViewModel: ObservableObject {
    enum Phase {
        case ready
        case scanning
        case reviewing
        case installing
        case finished
    }

    @Published var phase: Phase = .ready
    @Published var summary: FontInstallSummary?
    @Published var candidates: [FontCandidate] = []
    @Published var selectedCandidateIDs = Set<String>()
    @Published var preparationErrors: [String] = []
    @Published var sourceNames: [String] = []
    @Published var wasAutomaticallyDetected = false

    private var temporaryDirectories: [URL] = []
    private var pendingRequests: [([URL], Bool)] = []

    var isBusy: Bool { phase == .scanning || phase == .installing }
    var selectedCount: Int { selectedCandidateIDs.count }

    func prepare(urls: [URL], automaticallyDetected: Bool = false) {
        guard !urls.isEmpty else { return }
        if isBusy || phase == .reviewing {
            pendingRequests.append((urls, automaticallyDetected))
            return
        }

        cleanTemporaryDirectories()
        phase = .scanning
        summary = nil
        candidates = []
        selectedCandidateIDs = []
        preparationErrors = []
        sourceNames = []
        wasAutomaticallyDetected = automaticallyDetected

        Task {
            let prepared = await Task.detached(priority: .userInitiated) {
                FontBatchPreparer().prepare(urls: urls)
            }.value

            candidates = prepared.candidates
            selectedCandidateIDs = Set(prepared.candidates.map(\.id))
            preparationErrors = prepared.errors
            sourceNames = prepared.sourceNames
            temporaryDirectories = prepared.temporaryDirectories

            if prepared.candidates.isEmpty {
                summary = FontInstallSummary(discoveredCount: 0, items: [])
                phase = .finished
                NSSound(named: "Basso")?.play()
            } else {
                phase = .reviewing
                NSSound(named: automaticallyDetected ? "Ping" : "Pop")?.play()
                NSApp.activate(ignoringOtherApps: true)
            }
        }
    }

    func installSelected() {
        guard phase == .reviewing else { return }
        let selectedURLs = candidates
            .filter { selectedCandidateIDs.contains($0.id) }
            .map(\.url)
        guard !selectedURLs.isEmpty else { return }

        phase = .installing
        Task {
            let result = await Task.detached(priority: .userInitiated) {
                FontInstaller().install(from: selectedURLs)
            }.value
            summary = result
            phase = .finished
            cleanTemporaryDirectories()
            NSSound(named: result.failedCount == 0 ? "Glass" : "Basso")?.play()
        }
    }

    func toggleSelection(for candidate: FontCandidate) {
        if selectedCandidateIDs.contains(candidate.id) {
            selectedCandidateIDs.remove(candidate.id)
        } else {
            selectedCandidateIDs.insert(candidate.id)
        }
    }

    func selectAll() {
        selectedCandidateIDs = Set(candidates.map(\.id))
    }

    func selectRegularWeights() {
        let regularIDs = candidates.filter(\.isRegularWeight).map(\.id)
        selectedCandidateIDs = Set(regularIDs.isEmpty ? candidates.map(\.id) : regularIDs)
    }

    func clearSelection() {
        selectedCandidateIDs.removeAll()
    }

    func cancelReview() {
        reset()
    }

    func reset() {
        guard !isBusy else { return }
        cleanTemporaryDirectories()
        summary = nil
        candidates = []
        selectedCandidateIDs = []
        preparationErrors = []
        sourceNames = []
        wasAutomaticallyDetected = false
        phase = .ready
        processNextRequestIfNeeded()
    }

    private func processNextRequestIfNeeded() {
        guard !pendingRequests.isEmpty else { return }
        let next = pendingRequests.removeFirst()
        prepare(urls: next.0, automaticallyDetected: next.1)
    }

    private func cleanTemporaryDirectories() {
        for directory in temporaryDirectories {
            try? FileManager.default.removeItem(at: directory)
        }
        temporaryDirectories.removeAll()
    }
}

