import Foundation
import SwiftData
import UllageCore

/// A saved scan.
///
/// The dossier is stored as encoded JSON with a few fields lifted out alongside it. Modelling
/// every nested optional as its own `@Model` would buy nothing — nothing queries the inside of
/// a dossier — while costing a migration every time the schema gains a field. The lifted
/// fields are the ones the cellar list actually sorts and searches on.
@Model
final class ScanRecord {
    var id: UUID = UUID()
    var savedAt: Date = Date()
    var producer: String = ""
    var wineName: String?
    var vintage: Int?
    var regionSummary: String?
    /// Denormalised so the cellar can show "at peak" without decoding every dossier on scroll.
    var drinkingWindowStart: Int?
    var drinkingWindowEnd: Int?
    var peakStart: Int?
    var peakEnd: Int?

    @Attribute(.externalStorage) var thumbnailData: Data?
    @Attribute(.externalStorage) var dossierData: Data = Data()

    init(dossier: WineDossier, thumbnailData: Data?, savedAt: Date = Date()) {
        self.id = dossier.id
        self.savedAt = savedAt
        self.thumbnailData = thumbnailData
        self.producer = dossier.identity.producer
        self.wineName = dossier.identity.wineName
        self.vintage = dossier.identity.vintage
        self.regionSummary = dossier.origin.appellation?.value ?? dossier.origin.region?.value
        self.drinkingWindowStart = dossier.drinkingWindow.startYear
        self.drinkingWindowEnd = dossier.drinkingWindow.endYear
        self.peakStart = dossier.drinkingWindow.peakStartYear
        self.peakEnd = dossier.drinkingWindow.peakEndYear
        self.dossierData = (try? JSONEncoder().encode(dossier)) ?? Data()
    }

    /// The stored dossier, or nil if it was written by an incompatible build.
    var dossier: WineDossier? {
        try? JSONDecoder().decode(WineDossier.self, from: dossierData)
    }

    var displayTitle: String {
        guard let wineName, wineName.caseInsensitiveCompare(producer) != .orderedSame else {
            return producer
        }
        return "\(producer) \(wineName)"
    }

    var vintageText: String {
        vintage.map(String.init) ?? "NV"
    }

    /// Recomputed from the stored years rather than stored, so a bottle saved years ago still
    /// reports where it is in its life today.
    var drinkingStatus: DrinkingWindow.Status {
        DrinkingWindow(
            startYear: drinkingWindowStart,
            endYear: drinkingWindowEnd,
            peakStartYear: peakStart,
            peakEndYear: peakEnd
        ).status()
    }
}
