import Foundation

enum ThemeAppearance: String, Codable, CaseIterable { case automatic, light, dark }

struct ThemePoint: Codable, Equatable {
    var color: String
    var x: Double
    var y: Double
}

struct SpaceTheme: Codable, Equatable {
    var points: [ThemePoint]
    var gradient: Double = 0.5
    var grain: Double = 0
    var pickerVersion: Int? = nil

    static func solid(_ color: String) -> SpaceTheme {
        SpaceTheme(points: [ThemePoint(color: color.uppercased(), x: 0.35, y: 0.4)], gradient: 0)
    }
    func validated() -> Bool {
        (pickerVersion == nil || pickerVersion == 1) && (1...(pickerVersion == nil ? 4 : 3)).contains(points.count) && gradient.isFinite && (0...1).contains(gradient)
        && grain.isFinite && (0...1).contains(grain)
        && points.allSatisfy {
            Self.normalizedHex($0.color) == $0.color && $0.x.isFinite && $0.y.isFinite
            && (0...1).contains($0.x) && (0...1).contains($0.y)
        }
    }
    static func normalizedHex(_ value: String) -> String? {
        let raw = value.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let digits = raw.hasPrefix("#") ? String(raw.dropFirst()) : raw
        guard digits.range(of: "^[0-9A-F]{6}$", options: .regularExpression) != nil else { return nil }
        return "#" + digits
    }

    /// Legacy coordinates positioned gradient lights. The new field is a polar
    /// color wheel: angle is hue, distance controls chroma and brightness.
    func preparedForColorWheel() -> SpaceTheme {
        guard pickerVersion != 1 || points.count > 3 else { return self }
        var copy = self
        copy.points = points.prefix(3).map { Self.wheelPoint(color:$0.color) }
        copy.pickerVersion = 1
        return copy
    }
    static func wheelPoint(color: String) -> ThemePoint {
        let value = UInt32(color.trimmingCharacters(in:CharacterSet(charactersIn:"#")),radix:16) ?? 0
        let r = Double((value >> 16)&255)/255, g = Double((value >> 8)&255)/255, b = Double(value&255)/255
        let hi = max(r,max(g,b)), lo = min(r,min(g,b)), delta = hi-lo
        var hue = 0.0
        if delta > 0 {
            if hi == r { hue = ((g-b)/delta).truncatingRemainder(dividingBy:6) }
            else if hi == g { hue = (b-r)/delta+2 }
            else { hue = (r-g)/delta+4 }
            hue /= 6; if hue < 0 { hue += 1 }
        }
        let saturation = hi == 0 ? 0 : delta/hi
        let radius = max(0.08,min(0.96,max(saturation*0.6,(hi-0.35)/0.65)))
        return ThemePoint(color:color,x:0.5+cos(hue*2 * .pi)*radius*0.46,y:0.5+sin(hue*2 * .pi)*radius*0.46)
    }
    static func wheelColor(x: Double, y: Double) -> String {
        let dx = (x-0.5)/0.46, dy = (y-0.5)/0.46
        let radius = min(1,hypot(dx,dy))
        var hue = atan2(dy,dx)/(2 * .pi); if hue < 0 { hue += 1 }
        let saturation = min(1,radius*2.8), value = 0.35+0.65*min(1,radius*2.2)
        let h = hue*6, chroma = value*saturation, second = chroma*(1-abs(h.truncatingRemainder(dividingBy:2)-1)), m = value-chroma
        let rgb: (Double,Double,Double)
        switch Int(h)%6 {
        case 0: rgb = (chroma,second,0)
        case 1: rgb = (second,chroma,0)
        case 2: rgb = (0,chroma,second)
        case 3: rgb = (0,second,chroma)
        case 4: rgb = (second,0,chroma)
        default: rgb = (chroma,0,second)
        }
        return String(format:"#%02X%02X%02X",Int(((rgb.0+m)*255).rounded()),Int(((rgb.1+m)*255).rounded()),Int(((rgb.2+m)*255).rounded()))
    }
    /// Apply one rotation and one radial scale to the entire harmony, from the
    /// gesture's initial snapshot. No drift, independent clamping or color jumps at edges.
    func movingColor(_ index: Int, toX x: Double, y: Double) -> SpaceTheme {
        guard points.indices.contains(index), x.isFinite, y.isFinite else { return self }
        let initial = preparedForColorWheel()
        let source = initial.points[index]
        let sx = source.x-0.5, sy = source.y-0.5
        let tx = x-0.5, ty = y-0.5
        let sourceRadius = max(0.001,hypot(sx,sy))
        let angle = atan2(ty,tx)-atan2(sy,sx)
        let largest = initial.points.map { hypot($0.x-0.5,$0.y-0.5) }.max() ?? sourceRadius
        let scale = min(max(0.012,hypot(tx,ty))/sourceRadius,0.46/max(0.001,largest))
        var result = initial
        result.points = initial.points.map { point in
            let dx = point.x-0.5, dy = point.y-0.5
            let px = 0.5+(dx*cos(angle)-dy*sin(angle))*scale
            let py = 0.5+(dx*sin(angle)+dy*cos(angle))*scale
            return ThemePoint(color:Self.wheelColor(x:px,y:py),x:px,y:py)
        }
        return result
    }
    mutating func addHarmonyColor() {
        self = preparedForColorWheel()
        guard points.count < 3 else { return }
        let first = points[0], angle = [0.0,Double.pi,Double.pi/2,-Double.pi/2][points.count]
        let dx = first.x-0.5, dy = first.y-0.5
        let x = 0.5+(dx*cos(angle)-dy*sin(angle))*0.82, y = 0.5+(dx*sin(angle)+dy*cos(angle))*0.82
        points.append(ThemePoint(color:Self.wheelColor(x:x,y:y),x:x,y:y))
        gradient = max(gradient,0.65)
    }
}
