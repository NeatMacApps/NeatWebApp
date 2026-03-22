import AppKit
import SwiftUI

struct BrowserContainerView: View {
    let session: BrowserSession

    var body: some View {
        VStack(spacing: 0) {
            BrowserWindowDragBar(session: session)

            BrowserWebView(session: session)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(.black)
        .ignoresSafeArea(.container, edges: .top)
    }
}

private struct BrowserWindowDragBar: View {
    let session: BrowserSession

    var body: some View {
        @Bindable var bindableSession = session

        return ZStack {
            WindowDragHandle()

            HStack {
                BrowserChromeButton(
                    systemImage: "xmark",
                    foregroundStyle: Color.primary.opacity(0.82),
                    action: session.closeWindow
                )
                .help("Close Window")

                Spacer()

                BrowserChromeButton(
                    systemImage: bindableSession.isPinned ? "pin.fill" : "pin",
                    foregroundStyle: Color.primary.opacity(bindableSession.isPinned ? 1 : 0.82),
                    isHighlighted: bindableSession.isPinned,
                    action: session.togglePinned
                )
                .help(bindableSession.isPinned ? "Disable Always on Top" : "Enable Always on Top")
            }
            .padding(.horizontal, 8)
        }
        .frame(height: 24)
        .background(WindowChromeMaterial())
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(.primary.opacity(0.08))
                .frame(height: 0.5)
        }
    }
}

private struct BrowserChromeButton: View {
    let systemImage: String
    let foregroundStyle: Color
    var isHighlighted = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(foregroundStyle)
                .frame(width: 24, height: 24)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(Color.primary.opacity(isHighlighted ? 0.12 : 0))
                )
        }
        .buttonStyle(.plain)
        .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
    }
}

private struct WindowChromeMaterial: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .titlebar
        view.blendingMode = .withinWindow
        view.state = .active
        view.isEmphasized = false
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = .titlebar
        nsView.blendingMode = .withinWindow
        nsView.state = .active
        nsView.isEmphasized = false
    }
}

private struct WindowDragHandle: NSViewRepresentable {
    func makeNSView(context: Context) -> WindowDragHandleView {
        WindowDragHandleView()
    }

    func updateNSView(_ nsView: WindowDragHandleView, context: Context) {}
}

private final class WindowDragHandleView: NSView {
    override var isOpaque: Bool {
        false
    }

    override func mouseDown(with event: NSEvent) {
        window?.performDrag(with: event)
    }
}
