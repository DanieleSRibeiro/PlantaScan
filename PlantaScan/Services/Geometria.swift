import CoreGraphics

extension CGPoint {
    static func + (p: CGPoint, v: CGVector) -> CGPoint {
        CGPoint(x: p.x + v.dx, y: p.y + v.dy)
    }

    static func - (p: CGPoint, v: CGVector) -> CGPoint {
        CGPoint(x: p.x - v.dx, y: p.y - v.dy)
    }

    static func - (a: CGPoint, b: CGPoint) -> CGVector {
        CGVector(dx: a.x - b.x, dy: a.y - b.y)
    }

    func distancia(_ o: CGPoint) -> CGFloat {
        hypot(x - o.x, y - o.y)
    }

    static func media(_ a: CGPoint, _ b: CGPoint) -> CGPoint {
        CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)
    }
}

extension CGVector {
    static func * (v: CGVector, s: CGFloat) -> CGVector {
        CGVector(dx: v.dx * s, dy: v.dy * s)
    }

    static prefix func - (v: CGVector) -> CGVector {
        CGVector(dx: -v.dx, dy: -v.dy)
    }

    var comprimento: CGFloat { hypot(dx, dy) }

    var normalizado: CGVector {
        let l = comprimento
        return l > 1e-6 ? CGVector(dx: dx / l, dy: dy / l) : CGVector(dx: 1, dy: 0)
    }

    var perpendicular: CGVector { CGVector(dx: -dy, dy: dx) }

    var angulo: CGFloat { atan2(dy, dx) }

    func dot(_ o: CGVector) -> CGFloat { dx * o.dx + dy * o.dy }
}

enum Geometria {
    /// Área (valor absoluto) pela fórmula do laço.
    static func area(_ p: [CGPoint]) -> Double {
        guard p.count >= 3 else { return 0 }
        var s: CGFloat = 0
        for i in p.indices {
            let a = p[i]
            let b = p[(i + 1) % p.count]
            s += a.x * b.y - b.x * a.y
        }
        return Double(abs(s) / 2)
    }

    static func media(_ p: [CGPoint]) -> CGPoint {
        guard !p.isEmpty else { return .zero }
        let sx = p.reduce(CGFloat(0)) { $0 + $1.x }
        let sy = p.reduce(CGFloat(0)) { $0 + $1.y }
        return CGPoint(x: sx / CGFloat(p.count), y: sy / CGFloat(p.count))
    }

    static func centroidePoligono(_ p: [CGPoint]) -> CGPoint {
        guard p.count >= 3 else { return media(p) }
        var a: CGFloat = 0
        var cx: CGFloat = 0
        var cy: CGFloat = 0
        for i in p.indices {
            let p0 = p[i]
            let p1 = p[(i + 1) % p.count]
            let f = p0.x * p1.y - p1.x * p0.y
            a += f
            cx += (p0.x + p1.x) * f
            cy += (p0.y + p1.y) * f
        }
        guard abs(a) > 1e-6 else { return media(p) }
        return CGPoint(x: cx / (3 * a), y: cy / (3 * a))
    }

    static func contem(_ poligono: [CGPoint], _ pt: CGPoint) -> Bool {
        guard poligono.count >= 3 else { return false }
        var dentro = false
        var j = poligono.count - 1
        for i in poligono.indices {
            let pi = poligono[i]
            let pj = poligono[j]
            if (pi.y > pt.y) != (pj.y > pt.y) {
                let x = (pj.x - pi.x) * (pt.y - pi.y) / (pj.y - pi.y) + pi.x
                if pt.x < x { dentro.toggle() }
            }
            j = i
        }
        return dentro
    }

    static func distancia(ponto p: CGPoint, a: CGPoint, b: CGPoint) -> CGFloat {
        let ab = b - a
        let l2 = ab.dx * ab.dx + ab.dy * ab.dy
        guard l2 > 1e-9 else { return p.distancia(a) }
        let t = max(0, min(1, (p - a).dot(ab) / l2))
        let proj = a + ab * t
        return p.distancia(proj)
    }

    static func envoltoriaConvexa(_ pontos: [CGPoint]) -> [CGPoint] {
        let pts = pontos.sorted { $0.x == $1.x ? $0.y < $1.y : $0.x < $1.x }
        guard pts.count >= 3 else { return pts }
        func cruz(_ o: CGPoint, _ a: CGPoint, _ b: CGPoint) -> CGFloat {
            (a.x - o.x) * (b.y - o.y) - (a.y - o.y) * (b.x - o.x)
        }
        var inferior: [CGPoint] = []
        for p in pts {
            while inferior.count >= 2 && cruz(inferior[inferior.count - 2], inferior[inferior.count - 1], p) <= 0 {
                inferior.removeLast()
            }
            inferior.append(p)
        }
        var superior: [CGPoint] = []
        for p in pts.reversed() {
            while superior.count >= 2 && cruz(superior[superior.count - 2], superior[superior.count - 1], p) <= 0 {
                superior.removeLast()
            }
            superior.append(p)
        }
        return Array(inferior.dropLast() + superior.dropLast())
    }

    static func limites(_ pontos: [CGPoint]) -> CGRect {
        guard let primeiro = pontos.first else { return CGRect(x: -1, y: -1, width: 2, height: 2) }
        var minX = primeiro.x, maxX = primeiro.x, minY = primeiro.y, maxY = primeiro.y
        for p in pontos {
            minX = min(minX, p.x); maxX = max(maxX, p.x)
            minY = min(minY, p.y); maxY = max(maxY, p.y)
        }
        return CGRect(x: minX, y: minY, width: max(maxX - minX, 0.5), height: max(maxY - minY, 0.5))
    }
}
