import Foundation

@MainActor
protocol WebAppRuntimeCoordinating {
    func open(_ definition: WebAppDefinition, preferredGeometry: ScreenNotchGeometry?)
    func focus(appID: String)
    func collapse(appID: String)
    func expand(appID: String)
    func terminate(appID: String)
    func terminateAll()
    func increaseZoom(appID: String)
    func decreaseZoom(appID: String)
    func resetZoom(appID: String)
    func reloadDefinition(_ definition: WebAppDefinition)
    func refreshRegistry()
    func prepareStandbyRuntime()
    func releaseStandbyRuntimeForMemoryPressure()
}
