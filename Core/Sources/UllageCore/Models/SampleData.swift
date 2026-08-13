import Foundation

/// Realistic data for SwiftUI previews and for demo mode before an API key is entered.
///
/// It is deliberately a real, findable wine with a mixture of sourced and inferred fields, so
/// the provenance badges and the "also consulted" section are exercised rather than sitting
/// unused until the first live scan.
public enum SampleData {
    public static let citations: [Citation] = [
        Citation(
            title: "Château Musar — Red 2015",
            url: "https://chateaumusar.com/wines/chateau-musar-red/",
            note: "Producer page"
        ),
        Citation(
            title: "Château Musar Red 2015 — technical sheet",
            url: "https://chateaumusar.com/tech-sheets/musar-red-2015.pdf",
            note: "Producer tech sheet"
        ),
        Citation(
            title: "Bekaa Valley 2015 vintage report",
            url: "https://www.decanter.com/wine/lebanon-2015-vintage-report/",
            note: "Vintage conditions"
        ),
        Citation(
            title: "Château Musar Red 2015 tasting note",
            url: "https://vinous.com/wines/chateau-musar-red-2015",
            note: "Critic review"
        )
    ]

    public static var dossier: WineDossier {
        WineDossier(
            identity: WineDossier.Identity(
                producer: "Château Musar",
                wineName: "Red",
                vintage: 2015,
                wineType: .red,
                alcoholPercent: 14,
                bottleSizeMilliliters: 750,
                summary: """
                Musar's flagship red, a Bekaa Valley blend of Cabernet Sauvignon, Cinsault and \
                Carignan aged in French oak and released only after seven years. The 2015 is a \
                warm, generous vintage in a house style that has changed remarkably little \
                since the 1960s.
                """
            ),
            origin: WineDossier.Origin(
                country: Attributed(value: "Lebanon", provenance: .label),
                region: Attributed(value: "Bekaa Valley", provenance: .label),
                subregion: Attributed(value: "Aana, Kefraya and Deir el Ahmar", provenance: .web, sourceIndices: [0]),
                appellation: Attributed(value: "Vin du Liban", provenance: .label),
                terroirNotes: Attributed(
                    value: """
                    Vineyards sit at around 1,000 metres on gravelly soils over limestone, with \
                    hot days, cold nights and almost no summer rain. The altitude is what keeps \
                    acidity in a climate this warm.
                    """,
                    provenance: .web,
                    sourceIndices: [0, 2]
                )
            ),
            composition: [
                WineDossier.GrapeShare(name: "Cabernet Sauvignon", percentage: 33),
                WineDossier.GrapeShare(name: "Cinsault", percentage: 33),
                WineDossier.GrapeShare(name: "Carignan", percentage: 33)
            ],
            winemaking: WineDossier.Winemaking(
                winemakerNotes: Attributed(
                    value: """
                    "The 2015 harvest was early and healthy. We fermented in concrete, then aged \
                    the three varieties separately in French Nevers oak for twelve months before \
                    blending. The wine spent a further three years in bottle in our cellars \
                    before release."
                    """,
                    provenance: .web,
                    sourceIndices: [1]
                ),
                vinification: Attributed(
                    value: "Fermented in cement vats with indigenous yeasts; varieties vinified separately.",
                    provenance: .web,
                    sourceIndices: [1]
                ),
                aging: Attributed(
                    value: "Twelve months in French Nevers oak barrels, then blended and bottle-aged for three years before release.",
                    provenance: .web,
                    sourceIndices: [1]
                ),
                viticulture: Attributed(
                    value: "Dry-farmed bush vines, some over fifty years old, farmed without synthetic treatments.",
                    provenance: .web,
                    sourceIndices: [0]
                ),
                isOrganic: true,
                productionQuantity: Attributed(value: "Around 400,000 bottles", provenance: .web, sourceIndices: [0])
            ),
            tasting: WineDossier.Tasting(
                nose: Attributed(
                    value: "Dried figs, sour cherry, cedar and a lick of volatile lift that is part of the house signature.",
                    provenance: .web,
                    sourceIndices: [3]
                ),
                palate: Attributed(
                    value: "Medium-bodied and savoury rather than sweet, with tea leaf, plum skin and a dusty, resolved tannin.",
                    provenance: .web,
                    sourceIndices: [3]
                ),
                finish: Attributed(
                    value: "Long, dry and faintly bitter in the way good Musar always is.",
                    provenance: .web,
                    sourceIndices: [3]
                ),
                structure: WineDossier.Tasting.Structure(body: 3, acidity: 4, tannin: 3, sweetness: 1)
            ),
            drinkingWindow: DrinkingWindow(
                startYear: 2022,
                endYear: 2040,
                peakStartYear: 2026,
                peakEndYear: 2034,
                advice: "Drinking well now with an hour in a decanter, but there is no hurry at all — Musar reds routinely go three decades.",
                decantMinutes: 60,
                servingTemperatureCelsius: ClosedRangeBox(lower: 16, upper: 18),
                provenance: .web,
                sourceIndices: [1, 3]
            ),
            pairings: [
                "Slow-roasted lamb shoulder with cumin",
                "Mujadara with crisp onions",
                "Grilled aubergine and tahini",
                "Aged sheep's-milk cheese"
            ],
            ratings: [
                WineDossier.Rating(
                    critic: "Vinous",
                    score: "93",
                    scale: 100,
                    numericScore: 93,
                    reviewExcerpt: "Classic Musar, savoury and layered, with the volatile lift that defines the house.",
                    sourceIndex: 3
                )
            ],
            priceEstimate: WineDossier.PriceEstimate(
                low: 28,
                high: 42,
                currency: "USD",
                market: "US retail, 2026",
                provenance: .web,
                sourceIndices: [0]
            ),
            sources: citations,
            overallConfidence: Confidence(0.92),
            researchNotes: "Blend proportions vary slightly by vintage; the producer publishes them only as approximate thirds."
        )
    }

    public static var labelReading: LabelReading {
        LabelReading(
            producer: "Château Musar",
            cuvee: "Red",
            vintage: 2015,
            appellation: "Vin du Liban",
            region: "Bekaa Valley",
            country: "Lebanon",
            wineType: .red,
            alcoholPercent: 14,
            bottleSizeMilliliters: 750,
            otherLabelText: ["Gaston Hochar", "Mis en bouteille au château"],
            visualDescription: "Cream label with a fine engraved château and a maroon capsule.",
            confidence: Confidence(0.94),
            suggestedQueries: [
                "Château Musar Red 2015 technical sheet",
                "chateaumusar.com Musar Red 2015",
                "Château Musar 2015 vintage Bekaa Valley review"
            ]
        )
    }
}
