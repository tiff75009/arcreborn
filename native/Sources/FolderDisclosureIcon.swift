// SPDX-License-Identifier: MPL-2.0
import AppKit
import QuartzCore

/// Two faces share a bottom fold. Shearing them in opposite directions keeps
/// the tab and the rounded corners recognisable throughout the gesture.
final class FolderDisclosureIcon: NSView {
    static let size: CGFloat = 24
    private let back = CAShapeLayer()
    private let flap = CAShapeLayer()
    private var folderID: String?
    private var isOpen = false
    private var gear: NSImageView?

    private static let closedBack: CGPath = {
        let p = CGMutablePath()
        p.move(to: CGPoint(x: 5.7, y: 3.3))
        p.addQuadCurve(to: CGPoint(x: 3.5, y: 5.6), control: CGPoint(x: 3.5, y: 3.3))
        p.addLine(to: CGPoint(x: 3.5, y: 18.2))
        p.addQuadCurve(to: CGPoint(x: 5.8, y: 20.5), control: CGPoint(x: 3.5, y: 20.5))
        p.addLine(to: CGPoint(x: 9.9, y: 20.5))
        p.addQuadCurve(to: CGPoint(x: 11.1, y: 20.1), control: CGPoint(x: 10.6, y: 20.5))
        p.addLine(to: CGPoint(x: 13.1, y: 18.7))
        p.addQuadCurve(to: CGPoint(x: 14.2, y: 18.4), control: CGPoint(x: 13.6, y: 18.4))
        p.addLine(to: CGPoint(x: 18.5, y: 18.4))
        p.addQuadCurve(to: CGPoint(x: 20.5, y: 16.2), control: CGPoint(x: 20.5, y: 18.4))
        p.addLine(to: CGPoint(x: 20.5, y: 5.5))
        p.addQuadCurve(to: CGPoint(x: 18.3, y: 3.3), control: CGPoint(x: 20.5, y: 3.3))
        p.closeSubpath()
        return p
    }()
    private static let closedFlap = CGPath(roundedRect: CGRect(x: 3.5, y: 3.3, width: 17, height: 13.3),
                                           cornerWidth: 2.1, cornerHeight: 2.1, transform: nil)
    private static func unfolded(_ path: CGPath, lean: CGFloat) -> CGPath {
        let hinge = CGPoint(x: 12, y: 3.3)
        var transform = CGAffineTransform(a: 0.84, b: 0, c: lean, d: 0.83,
                                         tx: hinge.x * 0.16 - hinge.y * lean, ty: hinge.y * 0.17)
        return path.copy(using: &transform)!
    }
    private static let openBack = unfolded(closedBack, lean: -0.22)
    private static let openFlap = unfolded(closedFlap, lean: 0.29)

    init() {
        super.init(frame: NSRect(x: 0, y: 0, width: Self.size, height: Self.size))
        wantsLayer = true
        for face in [back, flap] {
            face.frame = bounds
            face.lineJoin = .round
            layer?.addSublayer(face)
        }
        setAccessibilityElement(false)
    }
    required init?(coder: NSCoder) { fatalError() }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        let scale = window?.backingScaleFactor ?? 2
        back.contentsScale = scale
        flap.contentsScale = scale
    }

    func configure(_ folder: NativeFolder, ink: NSColor, tint: NSColor, animated: Bool) {
        let open = !folder.collapsed
        let changed = folderID != folder.id || isOpen != open
        let animate = animated && folderID == folder.id && window != nil && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        folderID = folder.id
        isOpen = open

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        back.strokeColor = ink.cgColor
        flap.strokeColor = ink.cgColor
        back.fillColor = (tint.blended(withFraction: 0.27, of: .white) ?? tint).cgColor
        flap.fillColor = (tint.blended(withFraction: 0.17, of: .black) ?? tint).cgColor
        if changed {
            pose(back, path: open ? Self.openBack : Self.closedBack, animated: animate, duration: open ? 0.24 : 0.21)
            pose(flap, path: open ? Self.openFlap : Self.closedFlap, animated: animate, duration: open ? 0.30 : 0.25)
        }
        CATransaction.commit()

        if folder.liveHost != nil && gear == nil {
            let mark = NSImageView(image: NSImage(systemSymbolName: "gearshape.fill", accessibilityDescription: nil) ?? NSImage())
            mark.frame = NSRect(x: 9, y: 5, width: 7, height: 7)
            addSubview(mark)
            gear = mark
        }
        gear?.isHidden = folder.liveHost == nil
        gear?.contentTintColor = ink
    }

    private func pose(_ face: CAShapeLayer, path: CGPath, animated: Bool, duration: Double) {
        let displayed = face.presentation() ?? face
        let start = displayed.path
        let weight = displayed.lineWidth
        face.removeAnimation(forKey: "fold")
        face.path = path
        face.lineWidth = isOpen ? 1.25 : 1.65
        guard animated, let start else { return }

        let shape = CABasicAnimation(keyPath: "path")
        shape.duration = duration
        shape.fromValue = start
        shape.toValue = path
        let stroke = CABasicAnimation(keyPath: "lineWidth")
        stroke.duration = duration
        stroke.fromValue = weight
        stroke.toValue = face.lineWidth
        let motion = CAAnimationGroup()
        motion.animations = [shape, stroke]
        motion.duration = duration
        motion.timingFunction = CAMediaTimingFunction(controlPoints: 0.19, 0.83, 0.25, 1)
        face.add(motion, forKey: "fold")
    }
}
