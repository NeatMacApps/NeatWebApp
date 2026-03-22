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

        return ZStack(alignment: .trailing) {
            WindowDragHandle()

            Button(action: session.togglePinned) {
                Image(systemName: bindableSession.isPinned ? "pin.fill" : "pin")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.black.opacity(bindableSession.isPinned ? 1 : 0.82))
                    .frame(width: 24, height: 24)
                    .background(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(.black.opacity(bindableSession.isPinned ? 0.14 : 0))
                    )
            }
            .buttonStyle(.plain)
            .padding(.trailing, 8)
            .help(bindableSession.isPinned ? "Disable Always on Top" : "Enable Always on Top")
        }
        .frame(height: 24)
        .background(.white)
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
