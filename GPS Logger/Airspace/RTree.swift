import Foundation
import CoreLocation

struct RTreeRect {
    var minX: Double
    var minY: Double
    var maxX: Double
    var maxY: Double

    func intersects(_ other: RTreeRect) -> Bool {
        return !(other.minX > maxX || other.maxX < minX ||
                 other.minY > maxY || other.maxY < minY)
    }

    mutating func expand(toInclude rect: RTreeRect) {
        minX = Swift.min(minX, rect.minX)
        minY = Swift.min(minY, rect.minY)
        maxX = Swift.max(maxX, rect.maxX)
        maxY = Swift.max(maxY, rect.maxY)
    }

    static func union(_ a: RTreeRect, _ b: RTreeRect) -> RTreeRect {
        return RTreeRect(minX: min(a.minX, b.minX),
                         minY: min(a.minY, b.minY),
                         maxX: max(a.maxX, b.maxX),
                         maxY: max(a.maxY, b.maxY))
    }
}

final class RTree<Element> {
    private class Node {
        var rect: RTreeRect
        var children: [Node] = []
        var items: [(RTreeRect, Element)] = []
        var leaf: Bool

        init(rect: RTreeRect, leaf: Bool) {
            self.rect = rect
            self.leaf = leaf
        }
    }

    private let maxEntries = 8
    private var root: Node

    init() {
        root = Node(rect: RTreeRect(minX: .infinity, minY: .infinity, maxX: -.infinity, maxY: -.infinity), leaf: true)
    }

    func insert(rect: RTreeRect, value: Element) {
        insert(rect: rect, value: value, node: root)
        if root.items.count > maxEntries {
            split(node: root)
        }
    }

    private func insert(rect: RTreeRect, value: Element, node: Node) {
        if node.leaf {
            node.items.append((rect, value))
            node.rect.expand(toInclude: rect)
        } else {
            var best = node.children.first!
            var minIncrease = area(of: RTreeRect.union(best.rect, rect)) - area(of: best.rect)
            for child in node.children.dropFirst() {
                let inc = area(of: RTreeRect.union(child.rect, rect)) - area(of: child.rect)
                if inc < minIncrease {
                    minIncrease = inc
                    best = child
                }
            }
            insert(rect: rect, value: value, node: best)
            node.rect.expand(toInclude: rect)
        }
    }

    private func split(node: Node) {
        let entries = node.items
        guard entries.count > 1 else { return }
        let axis = width(of: node.rect) > height(of: node.rect) ? 0 : 1
        let sorted = entries.sorted { a, b in
            if axis == 0 {
                return (a.0.minX + a.0.maxX) < (b.0.minX + b.0.maxX)
            } else {
                return (a.0.minY + a.0.maxY) < (b.0.minY + b.0.maxY)
            }
        }
        let mid = sorted.count / 2
        let leftNode = Node(rect: sorted[0].0, leaf: true)
        for e in sorted[0..<mid] {
            leftNode.items.append(e)
            leftNode.rect.expand(toInclude: e.0)
        }
        let rightNode = Node(rect: sorted[mid].0, leaf: true)
        for e in sorted[mid..<sorted.count] {
            rightNode.items.append(e)
            rightNode.rect.expand(toInclude: e.0)
        }
        node.leaf = false
        node.items.removeAll()
        node.children = [leftNode, rightNode]
    }

    func search(point: CLLocationCoordinate2D) -> [Element] {
        let rect = RTreeRect(minX: point.longitude, minY: point.latitude, maxX: point.longitude, maxY: point.latitude)
        return search(rect: rect)
    }

    func search(rect: RTreeRect) -> [Element] {
        return search(rect: rect, node: root)
    }

    private func search(rect: RTreeRect, node: Node) -> [Element] {
        guard node.rect.intersects(rect) else { return [] }
        var results: [Element] = []
        if node.leaf {
            for (r, value) in node.items where r.intersects(rect) {
                results.append(value)
            }
        } else {
            for child in node.children {
                results.append(contentsOf: search(rect: rect, node: child))
            }
        }
        return results
    }

    private func area(of rect: RTreeRect) -> Double {
        return width(of: rect) * height(of: rect)
    }

    private func width(of rect: RTreeRect) -> Double { rect.maxX - rect.minX }
    private func height(of rect: RTreeRect) -> Double { rect.maxY - rect.minY }
}
