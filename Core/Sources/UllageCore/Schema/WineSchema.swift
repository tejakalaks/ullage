import Foundation

/// The JSON schemas the two model passes are constrained to.
///
/// These mirror `LabelReading` and `WineDossier` exactly. The field descriptions are not
/// documentation for us — they are the instructions the model actually follows most closely,
/// so they carry the rules that matter: cite what you find, admit what you don't.
public enum WineSchema {
    public static let labelReadingName = "label_reading"
    public static let dossierName = "wine_dossier"

    private static let provenanceEnum = Schema.stringEnum(
        Provenance.allCases.map(\.rawValue),
        """
        Where this value came from. 'label' if it is printed on the bottle in the photo, \
        'web' if you found it in a source you searched, 'inference' if it is your own \
        estimate. Never claim 'web' without a matching entry in source_indices.
        """
    )

    private static func attributedString(_ description: String) -> JSONValue {
        Schema.nullable(Schema.object(
            description,
            [
                ("value", Schema.string("The text itself. Never a placeholder such as 'unknown'.")),
                ("provenance", provenanceEnum),
                ("source_indices", Schema.array(
                    of: Schema.integer(),
                    "Zero-based indices into the top-level sources array supporting this value."
                ))
            ]
        ))
    }

    // MARK: - Stage A: reading the label

    public static var labelReading: JSONValue {
        Schema.object(
            "Your reading of the wine label in the photographs.",
            [
                ("is_wine_label", Schema.boolean(
                    "False if the photographs do not show a wine bottle or label at all."
                )),
                ("rejection_reason", Schema.nullable(Schema.string(
                    "If is_wine_label is false, or the label is unreadable, say briefly why."
                ))),
                ("producer", Schema.nullable(Schema.string(
                    "The estate, domaine, château or brand that made the wine. Expand abbreviations you are sure of (Ch. -> Château)."
                ))),
                ("cuvee", Schema.nullable(Schema.string(
                    "The specific wine or cuvée name, distinct from the producer, if the label carries one."
                ))),
                ("vintage", Schema.nullable(Schema.integer(
                    "Four-digit vintage year. Null for non-vintage bottles or if you cannot read it."
                ))),
                ("is_non_vintage", Schema.boolean(
                    "True only if the label positively indicates non-vintage (NV, multi-vintage, sin cosecha)."
                )),
                ("appellation", Schema.nullable(Schema.string(
                    "The appellation or denomination exactly as written, e.g. 'Gevrey-Chambertin 1er Cru', 'Barolo DOCG', 'Napa Valley AVA'."
                ))),
                ("region", Schema.nullable(Schema.string("The wider wine region, e.g. 'Burgundy', 'Piedmont'."))),
                ("country", Schema.nullable(Schema.string("Country of origin."))),
                ("wine_type", Schema.nullable(Schema.stringEnum(
                    WineType.allCases.map(\.rawValue),
                    "Style of wine, judged from the label and the colour of the glass and capsule if visible."
                ))),
                ("alcohol_percent", Schema.nullable(Schema.number("Stated alcohol by volume, as a number, e.g. 13.5."))),
                ("bottle_size_ml", Schema.nullable(Schema.integer("Stated bottle volume in millilitres, e.g. 750."))),
                ("classification", Schema.nullable(Schema.string(
                    "Quality classification printed on the label, e.g. 'Grand Cru Classé', 'Riserva', 'Gran Reserva'."
                ))),
                ("importer", Schema.nullable(Schema.string("Importer or distributor named in the back-label small print."))),
                ("other_label_text", Schema.array(
                    of: Schema.string(),
                    "Any other legible text that could help identify this exact bottling: bottling dates, lot or cask numbers, 'mis en bouteille au domaine', awards."
                )),
                ("visual_description", Schema.nullable(Schema.string(
                    "Describe the label's appearance in a sentence or two: artwork, crest, typography, capsule colour. This matters when the text is worn or in an unfamiliar script."
                ))),
                ("confidence", Schema.number(
                    "0 to 1: how sure you are of this identification. Be honest; a low score here is more useful than a confident guess."
                )),
                ("alternatives", Schema.array(
                    of: Schema.object(nil, [
                        ("description", Schema.string("A different wine this label could plausibly be.")),
                        ("confidence", Schema.number("0 to 1."))
                    ]),
                    "Other plausible identifications, best first. Empty if the label is unambiguous."
                )),
                ("suggested_queries", Schema.array(
                    of: Schema.string(),
                    "Two to five web searches that would pin down this exact wine and vintage. Prefer the producer's own site and specific vintage pages over generic terms."
                ))
            ]
        )
    }

    // MARK: - Stage B: the researched dossier

    public static var dossier: JSONValue {
        Schema.object(
            "A researched profile of one specific wine and vintage.",
            [
                ("identity", Schema.object(nil, [
                    ("producer", Schema.string("Full, correctly spelled producer name.")),
                    ("wine_name", Schema.nullable(Schema.string("The cuvée or bottling name, if distinct from the producer."))),
                    ("vintage", Schema.nullable(Schema.integer("Four-digit vintage year, or null if non-vintage."))),
                    ("is_non_vintage", Schema.boolean("True for non-vintage bottlings.")),
                    ("wine_type", Schema.stringEnum(WineType.allCases.map(\.rawValue), "Style of wine.")),
                    ("alcohol_percent", Schema.nullable(Schema.number("Alcohol by volume for this vintage."))),
                    ("bottle_size_ml", Schema.nullable(Schema.integer("Bottle volume in millilitres."))),
                    ("summary", Schema.nullable(Schema.string(
                        "Two or three sentences on what this wine is and why it is worth knowing about. Write for someone holding the bottle, deciding whether to open it tonight."
                    )))
                ])),
                ("origin", Schema.object(nil, [
                    ("country", attributedString("Country of origin.")),
                    ("region", attributedString("Wine region, e.g. 'Burgundy', 'Rioja'.")),
                    ("subregion", attributedString("Subregion or district, e.g. 'Côte de Nuits', 'Rioja Alta'.")),
                    ("appellation", attributedString("Appellation, DOCG, AVA or equivalent.")),
                    ("vineyard", attributedString("Single vineyard, cru or named site, if this bottling comes from one.")),
                    ("classification", attributedString("Official classification or quality tier.")),
                    ("terroir_notes", attributedString(
                        "What makes this place taste the way it does: soils, altitude, aspect, climate, vine age. Two or three sentences."
                    ))
                ])),
                ("composition", Schema.array(
                    of: Schema.object(nil, [
                        ("name", Schema.string("Grape variety name.")),
                        ("percentage", Schema.nullable(Schema.number(
                            "Share of the blend, 0 to 100. Null if the blend is known but the proportions are not published. Do not invent proportions."
                        )))
                    ]),
                    "The grape varieties in this specific wine. Empty if you could not establish them."
                )),
                ("winemaking", Schema.object(nil, [
                    ("winemaker_notes", attributedString(
                        """
                        What the producer themselves say about this wine, quoted or closely paraphrased from \
                        their own tech sheet or website. This is the single most valuable field: prefer the \
                        producer's voice over a retailer's marketing copy, and leave it null rather than \
                        substituting someone else's description.
                        """
                    )),
                    ("vinification", attributedString("How the wine was made: fermentation vessel, temperature, whole cluster, maceration length, malolactic.")),
                    ("aging", attributedString("Élevage: vessel type and size, proportion of new oak, time in barrel and in bottle.")),
                    ("viticulture", attributedString("Vineyard practice: farming, yields, harvest method and date.")),
                    ("is_organic", Schema.nullable(Schema.boolean("True only if certified or explicitly stated organic."))),
                    ("is_biodynamic", Schema.nullable(Schema.boolean("True only if certified or explicitly stated biodynamic."))),
                    ("is_vegan", Schema.nullable(Schema.boolean("True only if explicitly stated vegan or unfined and unfiltered."))),
                    ("production_quantity", attributedString("How much was made, e.g. '4,800 bottles'."))
                ])),
                ("tasting", Schema.object(nil, [
                    ("nose", attributedString("The aromas, from published notes for this vintage where possible.")),
                    ("palate", attributedString("The palate: fruit, structure, texture, weight.")),
                    ("finish", attributedString("The finish: length and what lingers.")),
                    ("structure", Schema.nullable(Schema.object(
                        "Structural profile, each 1 to 5. Null for any axis you cannot judge.",
                        [
                            ("body", Schema.nullable(Schema.integer("1 = very light, 5 = very full."))),
                            ("acidity", Schema.nullable(Schema.integer("1 = soft, 5 = racy."))),
                            ("tannin", Schema.nullable(Schema.integer("1 = negligible, 5 = firm and grippy. Null for most whites."))),
                            ("sweetness", Schema.nullable(Schema.integer("1 = bone dry, 5 = lusciously sweet.")))
                        ]
                    )))
                ])),
                ("drinking_window", Schema.object(
                    "When to drink it. Give a window whenever you reasonably can, even if you must infer it from the vintage, appellation and style — but set provenance to 'inference' when you do.",
                    [
                        ("start_year", Schema.nullable(Schema.integer("First year the wine is worth opening."))),
                        ("end_year", Schema.nullable(Schema.integer("Last year it is likely to still be rewarding."))),
                        ("peak_start_year", Schema.nullable(Schema.integer("First year of the peak drinking period, inside the wider window."))),
                        ("peak_end_year", Schema.nullable(Schema.integer("Last year of the peak drinking period."))),
                        ("advice", Schema.nullable(Schema.string("A sentence of practical advice, e.g. 'drink now, but a further five years will add complexity'."))),
                        ("decant_minutes", Schema.nullable(Schema.integer("Recommended decanting time in minutes. Null if decanting is not advised."))),
                        ("serving_temperature_celsius", Schema.nullable(Schema.object(nil, [
                            ("lower", Schema.number("Lower bound in degrees Celsius.")),
                            ("upper", Schema.number("Upper bound in degrees Celsius."))
                        ]))),
                        ("provenance", provenanceEnum),
                        ("source_indices", Schema.array(of: Schema.integer(), "Indices into sources supporting this window."))
                    ]
                )),
                ("pairings", Schema.array(
                    of: Schema.string(),
                    "Three to six specific food pairings. Name dishes, not categories: 'roast duck with cherries' rather than 'poultry'."
                )),
                ("ratings", Schema.array(
                    of: Schema.object(nil, [
                        ("critic", Schema.string("Critic or publication, e.g. 'Vinous', 'Jancis Robinson'.")),
                        ("score", Schema.string("The score as written, e.g. '94' or '17.5'.")),
                        ("scale", Schema.nullable(Schema.number("The maximum of the scale, usually 100 or 20."))),
                        ("numeric_score", Schema.nullable(Schema.number("The score as a number, for comparison."))),
                        ("review_excerpt", Schema.nullable(Schema.string("A short quote from the review."))),
                        ("source_index", Schema.nullable(Schema.integer("Index into sources for this score.")))
                    ]),
                    "Critic scores for this exact wine and vintage. Only include scores you actually found; never estimate one."
                )),
                ("price_estimate", Schema.nullable(Schema.object(
                    "Typical retail price. A price is meaningless without a market and a date, so fill in 'market'.",
                    [
                        ("low", Schema.nullable(Schema.number("Lower end of typical retail price."))),
                        ("high", Schema.nullable(Schema.number("Upper end of typical retail price."))),
                        ("currency", Schema.string("ISO currency code, e.g. 'USD', 'GBP', 'EUR'.")),
                        ("market", Schema.nullable(Schema.string("Which market and when, e.g. 'US retail, 2026'."))),
                        ("provenance", provenanceEnum),
                        ("source_indices", Schema.array(of: Schema.integer(), "Indices into sources for this price."))
                    ]
                ))),
                ("sources", Schema.array(
                    of: Schema.object(nil, [
                        ("title", Schema.string("Page or publication title.")),
                        ("url", Schema.string("Full URL of a page you actually consulted.")),
                        ("note", Schema.nullable(Schema.string("What this source contributed, e.g. 'producer tech sheet'.")))
                    ]),
                    "Every page you relied on, in the order other fields reference them. Do not list a URL you did not open."
                )),
                ("overall_confidence", Schema.number(
                    "0 to 1: how confident you are that this dossier describes the bottle in the photograph. Lower it when you had to fall back on the producer's range rather than this exact vintage."
                )),
                ("research_notes", Schema.nullable(Schema.string(
                    "What you could not establish, and any caveats — for example 'no vintage-specific notes were published; the tasting note describes the 2019 rather than the 2020'. Null if the research was clean."
                )))
            ]
        )
    }
}
