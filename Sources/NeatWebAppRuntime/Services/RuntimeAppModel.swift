import Foundation
import Observation

@Observable
@MainActor
final class RuntimeAppModel {
    let definition: WebAppDefinition
    var phase: RuntimePhase = .launching
    var windowFrame: CGRect?
    var floatingIconFrame: CGRect?

    init(definition: WebAppDefinition) {
        self.definition = definition
    }

    func update(
        phase: RuntimePhase,
        windowFrame: CGRect?,
        floatingIconFrame: CGRect?
    ) {
        self.phase = phase
        self.windowFrame = windowFrame
        self.floatingIconFrame = floatingIconFrame
    }
}
