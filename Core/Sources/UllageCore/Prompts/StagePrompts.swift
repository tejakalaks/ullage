import Foundation

/// The instructions for the two model passes.
///
/// These are the product. The Swift around them is plumbing; how well Ullage works is mostly
/// a function of what is written here, so they are kept in one place, in the testable core,
/// rather than scattered through the networking layer.
public enum StagePrompts {
    // MARK: - Stage A

    /// Identification. No tools, no web: just look at the bottle.
    ///
    /// The framing is deliberate. Asking a model to "extract the text" gets you OCR with extra
    /// steps, and OCR on a foxed, embossed, cursive Burgundy label is exactly where OCR falls
    /// apart. Asking it to recognise the bottle lets it use everything else it knows — that
    /// this shade of capsule and that crest mean a particular estate, that a name in this
    /// position is a lieu-dit rather than a brand.
    public static let labelIdentification = """
    You are an experienced sommelier looking at photographs of a wine bottle.

    Identify the wine. Do not merely transcribe the text: read the bottle the way somebody who \
    knows wine would. Use the layout, the typography, the crest or artwork, the capsule, the \
    bottle shape, and the conventions of the region to work out which part of the label is the \
    producer, which is the cuvée, which is the appellation, and which is legal small print. \
    Expand abbreviations you are confident about. If a name appears in a script or language you \
    can read, transliterate it and give the local form in other_label_text.

    Rules:
    - Report only what is actually on the bottle. This pass is about the label in front of you, \
    not what you know about the wine; the research comes later.
    - If part of the label is obscured, blurred or cut off, leave those fields null rather than \
    guessing at them.
    - Set confidence honestly. A 0.4 that prompts a second photograph is far more useful than a \
    0.9 that sends the research pass after the wrong bottle.
    - When the label could belong to more than one wine — a producer with several similar \
    cuvées, a négociant bottling — list the possibilities in alternatives.
    - In suggested_queries, write the searches you would actually run to pin this bottle down. \
    Include the producer's own website where you can guess it, and always tie at least one query \
    to the specific vintage.
    - If the photograph is not a wine bottle, set is_wine_label to false and say so plainly in \
    rejection_reason.
    """

    /// Extra guidance when more than one photo was supplied.
    public static let multiImageNote = """
    The photographs show the same bottle from different angles. The back label usually carries \
    the alcohol level, the importer, the bottling details and sometimes the producer's own \
    tasting note, so read every image before answering.
    """

    // MARK: - Stage B

    /// Research. Web search on, and the standard for what may be asserted is set high.
    public static let research = """
    You are a wine researcher compiling a reference sheet on one specific bottle for the person \
    holding it.

    Search the web before you answer. Work outward in this order of preference:
    1. The producer's own website and technical sheet for this exact wine and vintage.
    2. The importer's or distributor's page for the same bottling.
    3. Critics and wine publications that reviewed this vintage.
    4. Serious retailers, for price and for tech sheets they reproduce.
    Wikipedia and general appellation references are fine for regional background, but never as \
    the source of a claim about this particular wine.

    Standards to hold yourself to:
    - Prefer this exact vintage. Where you can only find material on a neighbouring vintage or \
    on the wine in general, you may use it, but say so in research_notes and lower \
    overall_confidence.
    - Every fact you found online gets provenance 'web' and at least one index in \
    source_indices. Every fact printed on the label gets 'label'. Everything else gets \
    'inference'. Do not dress up an inference as a sourced fact; a reader who cannot tell them \
    apart is worse off than one who has less information.
    - Never invent a critic score, a URL, a price or a production figure. An empty array is a \
    perfectly good answer.
    - The winemaker's notes must come from the producer, not from a retailer's marketing copy. \
    If you cannot find the producer's own words, leave the field null.
    - Do give a drinking window even when nobody has published one, inferring it from vintage, \
    appellation, style and structure — mark it 'inference' and explain your reasoning in advice.
    - Write for a curious drinker, not a wine list. Plain sentences, no purple prose, no \
    adjectives you would not use out loud.
    """

    /// Builds the user turn for the research pass from what stage A saw.
    ///
    /// The label reading is passed as compact text rather than raw JSON: the model wrote it in
    /// the first place, and prose costs fewer tokens and reads less like something to be
    /// pattern-matched than a schema dump.
    public static func researchRequest(for reading: LabelReading, currentYear: Int) -> String {
        var lines: [String] = []
        lines.append("Research this bottle:")
        lines.append("")
        lines.append(labelSummary(for: reading))

        if !reading.suggestedQueries.isEmpty {
            lines.append("")
            lines.append("Searches worth running first:")
            lines.append(contentsOf: reading.suggestedQueries.map { "- \($0)" })
        }

        if !reading.alternatives.isEmpty {
            lines.append("")
            lines.append(
                "The label was ambiguous. Check these possibilities and settle on one, "
                + "noting in research_notes which you chose and why:"
            )
            lines.append(contentsOf: reading.alternatives.map {
                "- \($0.description) (confidence \($0.confidence.percentText))"
            })
        }

        lines.append("")
        lines.append("The current year is \(currentYear); make the drinking window relative to it.")

        if reading.confidence.warrantsConfirmation {
            lines.append(
                "The identification from the photograph was uncertain. Verify it against what "
                + "you find online before building the dossier, and correct it if the label "
                + "reading was wrong."
            )
        }
        return lines.joined(separator: "\n")
    }

    /// The stage A reading as a compact block of "Field: value" lines.
    public static func labelSummary(for reading: LabelReading) -> String {
        var lines: [String] = []
        func add(_ label: String, _ value: String?) {
            guard let value = value?.nilIfBlank else { return }
            lines.append("\(label): \(value)")
        }
        add("Producer", reading.producer)
        add("Cuvée", reading.cuvee)
        if let vintage = reading.vintage {
            add("Vintage", String(vintage))
        } else if reading.isNonVintage {
            add("Vintage", "non-vintage")
        }
        add("Appellation", reading.appellation)
        add("Region", reading.region)
        add("Country", reading.country)
        add("Classification", reading.classification)
        add("Style", reading.wineType?.displayName)
        if let abv = reading.alcoholPercent {
            add("Alcohol", String(format: "%.1f%%", abv))
        }
        if let size = reading.bottleSizeMilliliters {
            add("Bottle", "\(size) ml")
        }
        add("Importer", reading.importer)
        if !reading.otherLabelText.isEmpty {
            add("Other label text", reading.otherLabelText.joined(separator: " | "))
        }
        add("Label appearance", reading.visualDescription)
        add("Identification confidence", reading.confidence.percentText)
        return lines.joined(separator: "\n")
    }

    /// The user turn when the person corrected the identification by hand.
    ///
    /// Their correction is authoritative — they are holding the bottle and we are not.
    public static func researchRequest(forManualEntry entry: String, currentYear: Int) -> String {
        """
        Research this bottle, described by the person holding it:

        \(entry)

        Treat this description as authoritative for the identification; it comes from someone \
        looking at the bottle. Search for the exact wine and vintage.

        The current year is \(currentYear); make the drinking window relative to it.
        """
    }
}
