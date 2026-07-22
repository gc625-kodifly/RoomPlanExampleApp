import XCTest
@testable import RoomPlanSimple

final class FloorPlanDocumentTests: XCTestCase {
    func testFloorPlanDataRoundTripPreservesDocumentMetadata() throws {
        let data = makeFloorPlanData()
        let encoded = try JSONEncoder().encode(data)
        let decoded = try JSONDecoder().decode(FloorPlanData.self, from: encoded)

        XCTAssertEqual(decoded.roomName, "Living Room")
        XCTAssertEqual(decoded.roomArea, 12, accuracy: 0.001)
        XCTAssertEqual(decoded.boundary.count, 4)
        XCTAssertEqual(decoded.elements.count, 2)
    }

    func testLegacyFloorPlanDataGetsCompatibleDefaults() throws {
        let encoded = try JSONEncoder().encode(makeFloorPlanData())
        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        )
        object.removeValue(forKey: "boundary")
        object.removeValue(forKey: "roomArea")
        object.removeValue(forKey: "roomName")
        object.removeValue(forKey: "createdAt")
        let json = try JSONSerialization.data(withJSONObject: object)

        let decoded = try JSONDecoder().decode(FloorPlanData.self, from: json)
        XCTAssertEqual(decoded.roomName, "Room")
        XCTAssertEqual(decoded.roomArea, 12, accuracy: 0.001)
        XCTAssertTrue(decoded.boundary.isEmpty)
    }

    func testSVGIncludesProfessionalDocumentFeaturesAndRotation() {
        let svg = FloorPlanExporter.exportToSVG(data: makeFloorPlanData())

        XCTAssertTrue(svg.contains("SpatialSense Floor Plan"))
        XCTAssertTrue(svg.contains("SPATIALSENSE"))
        XCTAssertTrue(svg.contains("marker id=\"arrow\""))
        XCTAssertTrue(svg.contains("rotate("))
        XCTAssertTrue(svg.contains("12.0 m²"))
        XCTAssertTrue(svg.contains(">N</text>"))
    }

    func testDXFUsesRotatedElementCoordinates() {
        let data = makeFloorPlanData()
        let dxf = FloorPlanExporter.exportToDXF(data: data)

        XCTAssertTrue(dxf.contains("LWPOLYLINE"))
        XCTAssertTrue(dxf.contains("WALLS"))
        XCTAssertTrue(dxf.contains("OBJECTS"))
    }

    func testProfessionalRendererProducesRequestedCanvasSize() {
        let image = FloorPlanDocumentRenderer.image(
            data: makeFloorPlanData(),
            size: CGSize(width: 800, height: 1000)
        )
        XCTAssertEqual(image.size, CGSize(width: 800, height: 1000))
    }

    func testRotatedBoundsContainNinetyDegreeWall() {
        let rect = CGRect(x: 1, y: 2, width: 4, height: 0.1)
        let bounds = FloorPlanData.boundingRect(of: rect, rotatedBy: .pi / 2)

        XCTAssertEqual(bounds.width, 0.1, accuracy: 0.001)
        XCTAssertEqual(bounds.height, 4, accuracy: 0.001)
        XCTAssertEqual(bounds.midX, rect.midX, accuracy: 0.001)
        XCTAssertEqual(bounds.midY, rect.midY, accuracy: 0.001)
    }

    func testWallsAlwaysHaveVisiblePlanThickness() {
        XCTAssertEqual(FloorPlanData.normalizedWallThickness(0), 0.10)
        XCTAssertEqual(FloorPlanData.normalizedWallThickness(0.04), 0.10)
        XCTAssertEqual(FloorPlanData.normalizedWallThickness(0.18), 0.18)
    }

    private func makeFloorPlanData() -> FloorPlanData {
        FloorPlanData(
            elements: [
                FloorPlanElement(
                    rect: CGRect(x: 0, y: 0, width: 4, height: 0.1),
                    rotation: .pi / 8,
                    type: .wall,
                    label: nil
                ),
                FloorPlanElement(
                    rect: CGRect(x: 1, y: 1, width: 1.2, height: 0.8),
                    rotation: .pi / 4,
                    type: .object(category: "table"),
                    label: "Table"
                )
            ],
            boundingBox: CGRect(x: 0, y: 0, width: 4, height: 3),
            roomDimensions: (4, 2.5, 3),
            boundary: [
                CGPoint(x: 0, y: 0),
                CGPoint(x: 4, y: 0),
                CGPoint(x: 4, y: 3),
                CGPoint(x: 0, y: 3)
            ],
            roomArea: 12,
            roomName: "Living Room",
            createdAt: Date(timeIntervalSince1970: 0)
        )
    }
}
