import AppKit
import SwiftUI

/// Activity, not a percentage: the filesystem's total work is unknown until traversal finishes.
struct ScanActivityBar: View {
    let paused: Bool
    let stopping: Bool

    var body: some View {
        Group {
            if paused {
                // A stationary marker preserves the active state without repetitive motion.
                Capsule().fill(MapStyle.line)
                    .overlay { Capsule().fill(stopping ? MapStyle.warning : MapStyle.accent).frame(width: 36) }
                    .frame(height: 4)
                    .accessibilityElement()
                    .accessibilityLabel(stopping ? "Waiting for scan to stop" : "Scan in progress")
                    .accessibilityValue("Total work unknown")
                    .accessibilityIdentifier("atlas.scanActivity.static")
            } else {
                NativeScanActivityBar()
            }
        }
    }
}

private struct NativeScanActivityBar: NSViewRepresentable {
    func makeNSView(context: Context) -> NSProgressIndicator {
        let indicator = NSProgressIndicator()
        indicator.style = .bar
        indicator.controlSize = .small
        indicator.isIndeterminate = true
        indicator.isDisplayedWhenStopped = true
        indicator.setAccessibilityLabel("Scan in progress; total work unknown")
        indicator.setAccessibilityIdentifier("atlas.scanActivity.bar")
        indicator.startAnimation(nil)
        return indicator
    }

    func updateNSView(_ indicator: NSProgressIndicator, context: Context) {
        indicator.startAnimation(nil)
    }

    static func dismantleNSView(_ indicator: NSProgressIndicator, coordinator: ()) {
        indicator.stopAnimation(nil)
    }
}
