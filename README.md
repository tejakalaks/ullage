# Ullage

An iOS app that photographs a wine label and tells you what the bottle is: where it comes
from, what the winemaker says about it, when to drink it, and what it goes with.

*Ullage* is the empty space between the wine and the cork.

## What makes it different from a label scanner

There is no OCR anywhere in this app. No `VNRecognizeText`, no `DataScannerViewController`, no
text-extraction step at all. OCR is the wrong tool for wine: labels are foil-stamped, cursive,
foxed, embossed, in scripts the phone has never seen, and half the useful information is
implied by convention rather than printed. A model that reads "Ch. Musar" as five characters
learns nothing; one that recognises the estate, the region and the house style has actually
understood the bottle.

So the photograph goes straight to a multimodal model, and the app works in two passes.

**Pass one — identification.** The photographs go to a vision model with no tools and a strict
JSON schema. It is asked to read the bottle the way a sommelier would: work out which words are
the producer, which are the cuvée, which are the appellation, and which are importer small
print, using layout, typography, the crest, the capsule and regional convention. It reports a
confidence score, alternative identifications when the label is ambiguous, and — usefully — the
web searches it thinks would pin the bottle down. This pass is fast, so there is something on
screen within a couple of seconds.

**Pass two — research.** Its own reading is handed back to a model with web search enabled,
along with the photographs again, so that anything the research contradicts can be checked
against the bottle. It works outward from the producer's own tech sheet to the importer, to
critics, to serious retailers, and returns a dossier under a second strict schema. This pass is
streamed, and every search it runs appears in the interface as it happens.

**Every fact is tagged with where it came from** — read off the label, found online, or
inferred by the model — and sourced claims carry the page they came from. A drinking window
printed on a tech sheet and one guessed from the vintage are very different claims, and the app
refuses to draw them the same way.

## Building it

Requires **Xcode 16 or newer** (the project file uses the synchronised-folder format) and an
iOS 17 device or simulator.

```bash
git clone https://github.com/tejakalaks/ullage.git
cd ullage
open Ullage.xcodeproj
```

Set your own team under Signing & Capabilities and run. The camera needs a real device; in the
simulator the app offers the photo library instead.

The `Ullage.xcodeproj` in the repository was written by hand rather than generated, since it was
built without a Mac. If it ever gives trouble, `project.yml` describes the same target and
`xcodegen generate` will rebuild it.

## Adding your API key

The app runs in **demo mode** until you give it a key: it shows one real, fully populated
sample wine so you can see what it does before signing up for anything.

To scan real bottles, open Settings (the gear, top right) and paste an
[OpenAI API key](https://platform.openai.com/api-keys). Settings will verify it against the API
before storing it, so a mistyped key is caught there rather than half-way through a scan.

The key is stored in the keychain as a generic password with
`kSecAttrAccessibleWhenUnlockedThisDeviceOnly`, which means it is unreadable while the phone is
locked, is not included in backups, and does not sync to your other devices. It is never written
to `UserDefaults`.

Scans are billed to your own OpenAI account. A scan is one small vision call plus one
web-grounded research call; the Settings screen offers a "Quick" preset and a switch to turn web
search off if you want to spend less.

### A note on shipping this

A key on the device is a key the user can extract, which is fine for your own build and not fine
for the App Store. For a real release, put a small server between the app and OpenAI and have it
hold the key. Everything that touches the network is behind `WineIntelligenceService`, so that
is one new conformance rather than a rewrite.

## Layout

```
Core/                     UllageCore: no UIKit, builds and tests on Linux
  Sources/UllageCore/
    Models/               WineDossier, LabelReading, DrinkingWindow, Provenance
    Schema/               the strict JSON schema, plus a validator for it
    Prompts/              the instructions for both passes
    Parsing/              Responses API envelope, SSE, JSON extraction
    Scan/                 scan progress and the research log
  Tests/UllageCoreTests/  88 tests, fixture-driven

Ullage/                   the app: everything needing UIKit or SwiftUI
  Features/Scan/          camera, capture, the scan pipeline
  Features/Result/        the dossier screen
  Features/Cellar/        saved bottles
  Features/Settings/      API key, models, onboarding
  Core/AI/                the live service and the demo stand-in
  Core/Net/               Responses API client
  Core/Storage/           keychain, settings, SwiftData record
```

The split is deliberate. Everything that can be tested without a simulator — the schema, the
prompts, the decoding, the drinking-window arithmetic, the SSE parsing, the research log — lives
in `UllageCore` and is covered by tests. The app target is the part that genuinely needs a
device.

```bash
cd Core && swift test
```

## Things worth knowing if you work on this

- **The prompts are the product.** They are in
  [`Core/Sources/UllageCore/Prompts/StagePrompts.swift`](Core/Sources/UllageCore/Prompts/StagePrompts.swift).
  How good this app is depends far more on what is written there, and in the field descriptions
  in [`WineSchema.swift`](Core/Sources/UllageCore/Schema/WineSchema.swift), than on any of the
  Swift around them. The schema descriptions are not documentation; they are the instructions
  the model follows most closely.
- **Strict mode is unforgiving.** Every object must set `additionalProperties: false` and list
  every property in `required`; optional fields are spelled as nullable types. Breaking either
  gets you an opaque 400. `SchemaValidator` checks this in a unit test instead.
- **The drinking window is computed, never stored.** A bottle saved in 2026 and reopened in 2031
  reports where it is in its life today.
- **`JSONValue` serialises itself.** `JSONEncoder` backs keyed containers with a dictionary and
  emits keys in arbitrary order, which would scramble the schema on every run.
- **Don't use `AsyncBytes.lines` for SSE.** It drops empty lines, and an empty line is precisely
  how a server-sent event ends.
