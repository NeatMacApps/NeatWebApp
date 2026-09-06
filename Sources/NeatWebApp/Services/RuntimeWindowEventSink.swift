import AppKit

@MainActor
protocol RuntimeWindowEventSink: AnyObject {
    func webAppWindowDidRequestClose(_ controller: WebAppWindowController)

    func webAppWindowDidUpdate(
        appID: String,
        phase: RuntimePhase,
        windowFrame: CGRect?,
        floatingIconFrame: CGRect?
    )

    func webAppWindowDidFocus(appID: String, windowFrame: CGRect?)
}
