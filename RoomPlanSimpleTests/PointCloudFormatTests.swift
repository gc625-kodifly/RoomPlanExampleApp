import XCTest
@testable import RoomPlanSimple

final class PointCloudFormatTests: XCTestCase {
    func testFullRangeYCbCrConversionPreservesNeutralBlackAndWhite() {
        let black = PointCloudColorSampler.yCbCrToRGB(y: 0, cb: 128, cr: 128)
        XCTAssertEqual(black, .init(red: 0, green: 0, blue: 0))

        let white = PointCloudColorSampler.yCbCrToRGB(y: 255, cb: 128, cr: 128)
        XCTAssertEqual(white, .init(red: 255, green: 255, blue: 255))
    }

    func testVideoRangeYCbCrConversionPreservesNeutralBlackAndWhite() {
        let black = PointCloudColorSampler.yCbCrToRGB(
            y: 16,
            cb: 128,
            cr: 128,
            fullRange: false
        )
        XCTAssertEqual(black, .init(red: 0, green: 0, blue: 0))

        let white = PointCloudColorSampler.yCbCrToRGB(
            y: 235,
            cb: 128,
            cr: 128,
            fullRange: false
        )
        XCTAssertGreaterThanOrEqual(white.red, 250)
        XCTAssertGreaterThanOrEqual(white.green, 250)
        XCTAssertGreaterThanOrEqual(white.blue, 250)
    }

    func testColoredPCDRoundTrip() throws {
        let points = [
            PointCloudExporter.ColoredPoint(
                position: SIMD3<Float>(1, 2, 3),
                color: .init(red: 12, green: 34, blue: 56)
            ),
            PointCloudExporter.ColoredPoint(
                position: SIMD3<Float>(-1, 0.5, 7),
                color: .init(red: 200, green: 150, blue: 100)
            )
        ]
        let url = temporaryURL(extension: "pcd")
        defer { try? FileManager.default.removeItem(at: url) }

        try PointCloudExporter.writePCD(points, to: url)
        let contents = try String(contentsOf: url, encoding: .utf8)
        XCTAssertTrue(contents.contains("TYPE F F F F"))
        let loaded = try PointCloudFileLoader.loadPCD(from: url)

        XCTAssertEqual(loaded.count, 2)
        XCTAssertEqual(loaded[0].color, points[0].color)
        XCTAssertEqual(loaded[1].position, points[1].position)
    }

    func testColoredPLYRoundTripPreservesFaces() throws {
        let vertices = [
            PointCloudExporter.ColoredPoint(position: .zero, color: .init(red: 255, green: 0, blue: 0)),
            PointCloudExporter.ColoredPoint(position: SIMD3<Float>(1, 0, 0), color: .init(red: 0, green: 255, blue: 0)),
            PointCloudExporter.ColoredPoint(position: SIMD3<Float>(0, 1, 0), color: .init(red: 0, green: 0, blue: 255))
        ]
        let mesh = PointCloudExporter.ColoredMesh(
            vertices: vertices,
            faces: [SIMD3<UInt32>(0, 1, 2)]
        )
        let url = temporaryURL(extension: "ply")
        defer { try? FileManager.default.removeItem(at: url) }

        try PointCloudExporter.writePLY(mesh, to: url)
        let loaded = try PointCloudFileLoader.loadPLY(from: url)

        XCTAssertEqual(loaded.vertices.count, 3)
        XCTAssertEqual(loaded.faces, mesh.faces)
        XCTAssertEqual(loaded.vertices[2].color, vertices[2].color)
    }

    func testVoxelFilterAveragesPositionAndColor() throws {
        let points = [
            PointCloudExporter.ColoredPoint(
                position: SIMD3<Float>(0.001, 0, 0),
                color: .init(red: 10, green: 30, blue: 50)
            ),
            PointCloudExporter.ColoredPoint(
                position: SIMD3<Float>(0.009, 0, 0),
                color: .init(red: 30, green: 50, blue: 70)
            )
        ]

        let filtered = try PointCloudExporter.voxelFiltered(points, voxelSize: 0.02)

        XCTAssertEqual(filtered.count, 1)
        XCTAssertEqual(filtered[0].position.x, 0.005, accuracy: 0.0001)
        XCTAssertEqual(filtered[0].color, .init(red: 20, green: 40, blue: 60))
    }

    private func temporaryURL(extension fileExtension: String) -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension(fileExtension)
    }
}
