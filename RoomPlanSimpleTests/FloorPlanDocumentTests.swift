import XCTest
import SceneKit
@testable import RoomPlanSimple

final class FloorPlanDocumentTests: XCTestCase {
    func testFloorPlanDataRoundTripPreservesDocumentMetadata() throws {
        let data = makeFloorPlanData()
        let encoded = try JSONEncoder().encode(data)
        let decoded = try JSONDecoder().decode(FloorPlanData.self, from: encoded)

        XCTAssertEqual(decoded.roomName, "Living Room")
        XCTAssertEqual(decoded.roomArea, 12, accuracy: 0.001)
        XCTAssertEqual(decoded.boundary.count, 4)
        XCTAssertTrue(decoded.floorPolygons.isEmpty)
        XCTAssertEqual(decoded.elements.count, 2)
        XCTAssertEqual(decoded.presentationRotation, 0, accuracy: 0.001)
        XCTAssertEqual(decoded.elements[0].elevation, 1.25)
        XCTAssertEqual(decoded.elements[0].verticalExtent, 2.5)
        XCTAssertTrue(RoomSceneBuilder.canBuildScene(from: decoded))
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
        object.removeValue(forKey: "presentationRotation")
        object.removeValue(forKey: "floorPolygons")
        object.removeValue(forKey: "schemaVersion")
        object.removeValue(forKey: "verticalDatum")
        if var elements = object["elements"] as? [[String: Any]] {
            for index in elements.indices {
                elements[index].removeValue(forKey: "elevation")
                elements[index].removeValue(forKey: "verticalExtent")
            }
            object["elements"] = elements
        }
        let json = try JSONSerialization.data(withJSONObject: object)

        let decoded = try JSONDecoder().decode(FloorPlanData.self, from: json)
        XCTAssertEqual(decoded.roomName, "Room")
        XCTAssertEqual(decoded.roomArea, 12, accuracy: 0.001)
        XCTAssertTrue(decoded.boundary.isEmpty)
        XCTAssertTrue(decoded.floorPolygons.isEmpty)
        XCTAssertEqual(decoded.presentationRotation, 0, accuracy: 0.001)
        XCTAssertNil(decoded.elements[0].elevation)
        XCTAssertNil(decoded.elements[0].verticalExtent)
        XCTAssertEqual(decoded.schemaVersion, 0)
        XCTAssertNil(decoded.verticalDatum)
        XCTAssertFalse(RoomSceneBuilder.canBuildScene(from: decoded))
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

    func testPresentationNormalizationUsesOneRigidRotation() {
        let angle = CGFloat(17) * .pi / 180
        let elements = [
            FloorPlanElement(
                rect: CGRect(x: -2, y: -0.05, width: 4, height: 0.1),
                rotation: angle,
                type: .wall,
                label: nil
            ),
            FloorPlanElement(
                rect: CGRect(x: 2.95, y: 0, width: 3, height: 0.1),
                rotation: angle + .pi / 2,
                type: .wall,
                label: nil
            ),
            FloorPlanElement(
                rect: CGRect(x: 0.8, y: 0.6, width: 1.2, height: 0.8),
                rotation: angle + 0.23,
                type: .object(category: "sofa"),
                label: "Sofa"
            )
        ]
        let originalCenters = elements.map { CGPoint(x: $0.rect.midX, y: $0.rect.midY) }
        let originalDistance = hypot(
            originalCenters[2].x - originalCenters[0].x,
            originalCenters[2].y - originalCenters[0].y
        )

        let result = FloorPlanPresentation.normalize(elements: elements, boundary: [])
        let normalizedCenters = result.elements.map { CGPoint(x: $0.rect.midX, y: $0.rect.midY) }
        let normalizedDistance = hypot(
            normalizedCenters[2].x - normalizedCenters[0].x,
            normalizedCenters[2].y - normalizedCenters[0].y
        )

        XCTAssertEqual(result.elements[0].rotation, 0, accuracy: 0.0001)
        XCTAssertEqual(abs(result.elements[1].rotation), .pi / 2, accuracy: 0.0001)
        XCTAssertEqual(normalizedDistance, originalDistance, accuracy: 0.0001)
        XCTAssertEqual(result.elements[2].rect.size, elements[2].rect.size)
        XCTAssertEqual(result.elements[2].rotation, 0.23, accuracy: 0.0001)
    }

    func testFurnitureCategoriesUseRecognizableAssetsAndUnknownFallback() {
        XCTAssertEqual(FurnitureAssetKind("bed"), .bed)
        XCTAssertEqual(FurnitureAssetKind("washerDryer"), .washerDryer)
        XCTAssertEqual(FurnitureAssetKind("refrigerator"), .refrigerator)
        XCTAssertEqual(FurnitureAssetKind("stove"), .stove)
        XCTAssertEqual(FurnitureAssetKind("television"), .television)
        XCTAssertEqual(FurnitureAssetKind("futureCategory"), .unknown)
    }

    func testEveryCurrentRoomPlanCategoryHasLoadableBundledAsset() throws {
        XCTAssertEqual(FurnitureAssetKind.currentRoomPlanCategories.count, 16)

        for kind in FurnitureAssetKind.currentRoomPlanCategories {
            let url = try XCTUnwrap(
                FurnitureAssetCatalog.assetURL(for: kind),
                "Missing bundled model for \(kind.rawValue)"
            )
            XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
            XCTAssertNotNil(
                FurnitureAssetCatalog.makeNode(
                    kind: kind,
                    fitting: SIMD3<Float>(1.2, 1.0, 0.8)
                ),
                "Could not load bundled model for \(kind.rawValue)"
            )
        }
    }

    func testIntentionalKenneySubstitutesAreMarkedAsSemanticProxies() {
        XCTAssertTrue(FurnitureAssetKind.oven.isSemanticProxy)
        XCTAssertTrue(FurnitureAssetKind.dishwasher.isSemanticProxy)
        XCTAssertTrue(FurnitureAssetKind.fireplace.isSemanticProxy)
        XCTAssertNotNil(FurnitureAssetKind.oven.proxySourceDescription)
        XCTAssertFalse(FurnitureAssetKind.bed.isSemanticProxy)
    }

    func testFutureCategoryHasNoAssetAndUsesSafeMeasuredFallback() {
        let kind = FurnitureAssetKind("futureSDKCategory")
        XCTAssertEqual(kind, .unknown)
        XCTAssertNil(FurnitureAssetCatalog.assetURL(for: kind))

        let data = FloorPlanData(
            elements: [
                FloorPlanElement(
                    rect: CGRect(x: 0, y: 0, width: 3, height: 0.1),
                    rotation: 0,
                    type: .wall,
                    label: nil,
                    elevation: 1.25,
                    verticalExtent: 2.5
                ),
                FloorPlanElement(
                    rect: CGRect(x: 1, y: 1, width: 0.8, height: 0.6),
                    rotation: 0,
                    type: .object(category: "futureSDKCategory"),
                    label: nil,
                    elevation: 0.5,
                    verticalExtent: 1
                )
            ],
            boundingBox: CGRect(x: 0, y: 0, width: 3, height: 2),
            roomDimensions: (3, 2.5, 2),
            floorPolygons: [rectangle(x: 0, y: 0, width: 3, height: 2)]
        )

        let scene = RoomSceneBuilder.makeScene(from: data)
        let fallback = scene.rootNode.childNode(
            withName: "Neutral furniture fallback",
            recursively: true
        )
        XCTAssertNotNil(fallback)
    }

    func testRectangularFootprintIsReconstructedFromShuffledReversedWalls() throws {
        let points = [
            CGPoint(x: 0, y: 0), CGPoint(x: 4, y: 0),
            CGPoint(x: 4, y: 3), CGPoint(x: 0, y: 3)
        ]
        let walls = [
            wall(from: points[2], to: points[1]),
            wall(from: points[0], to: points[3]),
            wall(from: points[1], to: points[0]),
            wall(from: points[3], to: points[2])
        ]

        let footprint = FloorFootprint.boundary(from: walls)

        XCTAssertEqual(footprint.count, 4)
        XCTAssertEqual(FloorFootprint.area(of: footprint), 12, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(FloorFootprint.triangulate(footprint)).count, 6)
    }

    func testConcaveLShapedFootprintTriangulatesWithoutFillingNotch() throws {
        let points = [
            CGPoint(x: 0, y: 0), CGPoint(x: 4, y: 0),
            CGPoint(x: 4, y: 2), CGPoint(x: 2, y: 2),
            CGPoint(x: 2, y: 4), CGPoint(x: 0, y: 4)
        ]
        let walls = [
            wall(from: points[3], to: points[2]),
            wall(from: points[0], to: points[5]),
            wall(from: points[1], to: points[0]),
            wall(from: points[4], to: points[3]),
            wall(from: points[5], to: points[4]),
            wall(from: points[2], to: points[1])
        ]

        let footprint = FloorFootprint.boundary(from: walls)
        let triangles = try XCTUnwrap(FloorFootprint.triangulate(footprint))

        XCTAssertEqual(footprint.count, 6)
        XCTAssertEqual(FloorFootprint.area(of: footprint), 12, accuracy: 0.001)
        XCTAssertEqual(triangles.count, 12)
        XCTAssertFalse(pointInsidePolygon(CGPoint(x: 3, y: 3), polygon: footprint))
    }

    func testWallEndpointNoiseWithinToleranceStillClosesFootprint() {
        let walls = [
            wall(from: CGPoint(x: 0.02, y: 0), to: CGPoint(x: 3.98, y: 0.01)),
            wall(from: CGPoint(x: 4, y: -0.02), to: CGPoint(x: 4.01, y: 3.02)),
            wall(from: CGPoint(x: 4.03, y: 3), to: CGPoint(x: -0.02, y: 2.99)),
            wall(from: CGPoint(x: 0, y: 3.03), to: CGPoint(x: -0.01, y: -0.01))
        ]

        let footprint = FloorFootprint.boundary(from: [walls[2], walls[0], walls[3], walls[1]])

        XCTAssertEqual(footprint.count, 4)
        XCTAssertEqual(FloorFootprint.area(of: footprint), 12, accuracy: 0.15)
    }

    func testExteriorCycleIgnoresInteriorWallDeterministically() {
        let corners = [
            CGPoint(x: 0, y: 0), CGPoint(x: 4, y: 0),
            CGPoint(x: 4, y: 3), CGPoint(x: 0, y: 3)
        ]
        let walls = [
            wall(from: corners[0], to: corners[1]),
            wall(from: corners[1], to: corners[2]),
            wall(from: corners[2], to: corners[3]),
            wall(from: corners[3], to: corners[0]),
            wall(from: CGPoint(x: 2, y: 0), to: CGPoint(x: 2, y: 3))
        ]

        let footprint = FloorFootprint.boundary(from: [walls[4], walls[2], walls[0], walls[3], walls[1]])
        XCTAssertEqual(FloorFootprint.area(of: footprint), 12, accuracy: 0.001)
    }

    func testRawNonzeroDeviceOriginsNormalizeRoundTripAndAlignScene() throws {
        for floorOrigin in [CGFloat(-1.254253), CGFloat(-1.633997)] {
            let height = CGFloat(2.82)
            let objectHeight = CGFloat(0.75753665)
            let polygon = [
                CGPoint(x: -2, y: -1.5), CGPoint(x: 2, y: -1.5),
                CGPoint(x: 2, y: 1.5), CGPoint(x: -2, y: 1.5)
            ]
            let normalized = FloorPlanVerticalNormalizer.normalize(
                floors: [RawFloorComponent(polygon: polygon, elevation: floorOrigin)],
                elements: [
                    RawVerticalElement(
                        center: floorOrigin + height / 2,
                        extent: height,
                        isFloorStandingDatumCandidate: true
                    ),
                    RawVerticalElement(
                        center: floorOrigin + objectHeight / 2,
                        extent: objectHeight,
                        isFloorStandingDatumCandidate: true
                    )
                ]
            )
            XCTAssertEqual(try XCTUnwrap(normalized.datum), floorOrigin, accuracy: 0.000001)
            XCTAssertEqual(try XCTUnwrap(normalized.elementCenters[0]), height / 2, accuracy: 0.000001)
            XCTAssertEqual(
                try XCTUnwrap(normalized.elementCenters[1]),
                objectHeight / 2,
                accuracy: 0.000001
            )
            let data = FloorPlanData(
                elements: [
                    FloorPlanElement(
                        rect: CGRect(x: -2, y: -1.55, width: 4, height: 0.1),
                        rotation: 0,
                        type: .wall,
                        label: nil,
                        elevation: normalized.elementCenters[0],
                        verticalExtent: height
                    ),
                    FloorPlanElement(
                        rect: CGRect(x: -0.6, y: -0.4, width: 1.2, height: 0.8),
                        rotation: 0,
                        type: .object(category: "table"),
                        label: "Table",
                        elevation: normalized.elementCenters[1],
                        verticalExtent: objectHeight
                    )
                ],
                boundingBox: CGRect(x: -2, y: -1.5, width: 4, height: 3),
                roomDimensions: (4, Float(height), 3),
                floorPolygons: [polygon],
                floorComponents: normalized.floorComponents,
                roomArea: 12,
                verticalDatum: normalized.datum
            )

            let encoded = try JSONEncoder().encode(data)
            let decoded = try JSONDecoder().decode(FloorPlanData.self, from: encoded)
            XCTAssertEqual(decoded.schemaVersion, 3)
            XCTAssertEqual(try XCTUnwrap(decoded.verticalDatum), floorOrigin, accuracy: 0.000001)
            XCTAssertEqual(decoded.floorComponents, normalized.floorComponents)
            XCTAssertTrue(RoomSceneBuilder.canBuildScene(from: decoded))
            let scene = RoomSceneBuilder.makeScene(from: decoded)
            let floor = try XCTUnwrap(scene.rootNode.childNode(withName: "Floor", recursively: true))
            let wall = try XCTUnwrap(scene.rootNode.childNode(withName: "Wall", recursively: true))
            let table = try XCTUnwrap(scene.rootNode.childNode(withName: "Table", recursively: true))
            XCTAssertEqual(floor.boundingBox.max.y + floor.position.y, 0, accuracy: 0.001)
            XCTAssertEqual(wall.boundingBox.min.y + wall.position.y, 0, accuracy: 0.001)
            XCTAssertEqual(table.boundingBox.min.y + table.position.y, 0, accuracy: 0.001)
            let target = try XCTUnwrap(scene.rootNode.childNode(withName: "Camera target", recursively: true))
            XCTAssertGreaterThan(target.position.y, 0)
            XCTAssertLessThan(target.position.y, Float(height))
        }
    }

    func testSplitLevelFloorsRetainRelativeElevationsAndElementAlignment() throws {
        let lower = CGFloat(-1.2)
        let upper = CGFloat(-0.9)
        let wallHeight = CGFloat(2.4)
        let lowerPolygon = rectangle(x: 0, y: 0, width: 3, height: 3)
        let upperPolygon = rectangle(x: 3, y: 0, width: 3, height: 3)
        let normalized = FloorPlanVerticalNormalizer.normalize(
            floors: [
                RawFloorComponent(polygon: lowerPolygon, elevation: lower),
                RawFloorComponent(polygon: upperPolygon, elevation: upper)
            ],
            elements: [
                RawVerticalElement(
                    center: lower + wallHeight / 2,
                    extent: wallHeight,
                    isFloorStandingDatumCandidate: true
                ),
                RawVerticalElement(
                    center: upper + wallHeight / 2,
                    extent: wallHeight,
                    isFloorStandingDatumCandidate: true
                )
            ]
        )
        let data = makeVerticalFixture(
            normalization: normalized,
            polygons: [lowerPolygon, upperPolygon],
            extents: [wallHeight, wallHeight]
        )
        let decoded = try JSONDecoder().decode(
            FloorPlanData.self,
            from: JSONEncoder().encode(data)
        )
        XCTAssertEqual(
            FloorFootprint.validatedComponentsForReconstruction(from: decoded)?.count,
            2
        )
        XCTAssertTrue(RoomSceneBuilder.canBuildScene(from: decoded))
        XCTAssertEqual(decoded.floorComponents[0].elevation, -0.15, accuracy: 0.00001)
        XCTAssertEqual(decoded.floorComponents[1].elevation, 0.15, accuracy: 0.00001)
        let scene = RoomSceneBuilder.makeScene(from: decoded)
        let lowerFloor = try XCTUnwrap(scene.rootNode.childNode(withName: "Floor", recursively: true))
        let upperFloor = try XCTUnwrap(scene.rootNode.childNode(withName: "Floor 2", recursively: true))
        XCTAssertEqual(upperFloor.position.y - lowerFloor.position.y, 0.3, accuracy: 0.00001)
        let walls = scene.rootNode.childNodes(passingTest: { node, _ in node.name == "Wall" })
        XCTAssertEqual(walls.count, 2)
        XCTAssertEqual(
            walls[0].boundingBox.min.y + walls[0].position.y,
            lowerFloor.position.y,
            accuracy: 0.00001
        )
        XCTAssertEqual(
            walls[1].boundingBox.min.y + walls[1].position.y,
            upperFloor.position.y,
            accuracy: 0.00001
        )
    }

    func testRaisedPlatformKeepsFurnitureOnRaisedSlab() throws {
        let base = CGFloat(-1.25)
        let platform = base + 0.42
        let objectHeight = CGFloat(0.8)
        let basePolygon = rectangle(x: 0, y: 0, width: 4, height: 4)
        let platformPolygon = rectangle(x: 1, y: 1, width: 1.5, height: 1.5)
        let normalized = FloorPlanVerticalNormalizer.normalize(
            floors: [
                RawFloorComponent(polygon: basePolygon, elevation: base),
                RawFloorComponent(polygon: platformPolygon, elevation: platform)
            ],
            elements: [
                RawVerticalElement(
                    center: platform + objectHeight / 2,
                    extent: objectHeight,
                    isFloorStandingDatumCandidate: true
                )
            ]
        )
        let element = FloorPlanElement(
            rect: CGRect(x: 1.2, y: 1.2, width: 0.8, height: 0.8),
            rotation: 0,
            type: .object(category: "table"),
            label: "Raised table",
            elevation: normalized.elementCenters[0],
            verticalExtent: objectHeight
        )
        let data = FloorPlanData(
            elements: [element],
            boundingBox: CGRect(x: 0, y: 0, width: 4, height: 4),
            roomDimensions: (4, 2.8, 4),
            floorPolygons: [basePolygon, platformPolygon],
            floorComponents: normalized.floorComponents,
            verticalDatum: normalized.datum
        )
        let scene = RoomSceneBuilder.makeScene(from: data)
        let raisedFloor = try XCTUnwrap(scene.rootNode.childNode(withName: "Floor 2", recursively: true))
        let table = try XCTUnwrap(scene.rootNode.childNode(withName: "Raised table", recursively: true))
        XCTAssertEqual(
            table.boundingBox.min.y + table.position.y,
            raisedFloor.position.y,
            accuracy: 0.00001
        )
    }

    func testSingleLevelComponentsNormalizeToZero() {
        let polygon = rectangle(x: 0, y: 0, width: 4, height: 3)
        let normalized = FloorPlanVerticalNormalizer.normalize(
            floors: [
                RawFloorComponent(polygon: polygon, elevation: -1.4),
                RawFloorComponent(polygon: polygon, elevation: -1.4)
            ],
            elements: []
        )
        XCTAssertEqual(normalized.floorComponents.map(\.elevation), [0, 0])
    }

    func testOnlyExplicitSchemaVersionCanReconstruct() {
        let polygon = rectangle(x: 0, y: 0, width: 4, height: 3)
        for version in [0, 2, 4, 99] {
            let data = FloorPlanData(
                schemaVersion: version,
                elements: [],
                boundingBox: CGRect(x: 0, y: 0, width: 4, height: 3),
                roomDimensions: (4, 2.8, 3),
                floorPolygons: [polygon],
                verticalDatum: -1.2
            )
            XCTAssertFalse(RoomSceneBuilder.canBuildScene(from: data))
        }
        let current = FloorPlanData(
            elements: [],
            boundingBox: CGRect(x: 0, y: 0, width: 4, height: 3),
            roomDimensions: (4, 2.8, 3),
            floorPolygons: [polygon],
            verticalDatum: -1.2
        )
        XCTAssertTrue(RoomSceneBuilder.canBuildScene(from: current))
    }

    func testOneMalformedV3ComponentRejectsEntireComponentSet() {
        let valid = rectangle(x: 0, y: 0, width: 3, height: 3)
        let degenerate = [
            CGPoint(x: 3, y: 0),
            CGPoint(x: 4, y: 0),
            CGPoint(x: 5, y: 0)
        ]
        let secondValid = rectangle(x: 3, y: 0, width: 2, height: 2)
        let nonfinitePolygon = [
            CGPoint(x: 3, y: 0),
            CGPoint(x: 5, y: 0),
            CGPoint(x: CGFloat.nan, y: 2),
            CGPoint(x: 3, y: 2)
        ]
        let cases = [
            floorComponentData(
                polygons: [valid, degenerate],
                elevations: [0, 0.3]
            ),
            floorComponentData(
                polygons: [valid, secondValid],
                elevations: [0, .nan]
            ),
            floorComponentData(
                polygons: [valid, nonfinitePolygon],
                elevations: [0, 0.3]
            )
        ]

        for data in cases {
            XCTAssertNil(FloorFootprint.validatedComponentsForReconstruction(from: data))
            XCTAssertFalse(RoomSceneBuilder.canBuildScene(from: data))
        }
    }

    func testMalformedV3GateProducesNoPartialNativeScene() {
        let valid = rectangle(x: 0, y: 0, width: 3, height: 3)
        let mismatchedCompatibility = rectangle(x: 3, y: 0, width: 2, height: 2)
        let data = floorComponentData(
            polygons: [valid, mismatchedCompatibility],
            elevations: [0, 0.3],
            componentPolygons: [
                valid,
                rectangle(x: 3, y: 0, width: 2.5, height: 2)
            ]
        )

        XCTAssertFalse(RoomSceneBuilder.canBuildScene(from: data))
        let scene = RoomSceneBuilder.makeScene(from: data)
        XCTAssertNil(
            scene.rootNode.childNode(withName: "Measured room", recursively: false),
            "The viewer gate must receive nil native reconstruction and load saved USDZ"
        )
        XCTAssertNil(scene.rootNode.childNode(withName: "Floor", recursively: true))
    }

    func testSchemaV2DeviceDataDecodesButFallsBackToUSDZ() throws {
        let polygon = rectangle(x: 0, y: 0, width: 4, height: 3)
        let v2 = FloorPlanData(
            schemaVersion: 2,
            elements: [],
            boundingBox: CGRect(x: 0, y: 0, width: 4, height: 3),
            roomDimensions: (4, 2.8, 3),
            floorPolygons: [polygon],
            verticalDatum: -1.2
        )
        var json = try XCTUnwrap(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(v2)) as? [String: Any]
        )
        json.removeValue(forKey: "floorComponents")
        let decoded = try JSONDecoder().decode(
            FloorPlanData.self,
            from: JSONSerialization.data(withJSONObject: json)
        )
        XCTAssertEqual(decoded.schemaVersion, 2)
        XCTAssertTrue(decoded.floorComponents.isEmpty)
        XCTAssertFalse(RoomSceneBuilder.canBuildScene(from: decoded))
    }

    func testCameraFitUsesNarrowerViewportFieldOfView() {
        let wideRoom = SIMD3<Float>(12, 2.8, 3)
        let portrait = SceneCameraFit.distance(toFit: wideRoom, aspectRatio: 0.5)
        let landscape = SceneCameraFit.distance(toFit: wideRoom, aspectRatio: 2)
        XCTAssertGreaterThan(portrait, landscape)

        let tallRoom = SIMD3<Float>(2, 9, 2)
        let tallLandscape = SceneCameraFit.distance(toFit: tallRoom, aspectRatio: 2)
        let shortLandscape = SceneCameraFit.distance(
            toFit: SIMD3<Float>(2, 3, 2),
            aspectRatio: 2
        )
        XCTAssertGreaterThan(tallLandscape, shortLandscape)
        XCTAssertTrue(tallLandscape.isFinite)
    }

    @MainActor
    func testRoomDeletionRemovesLegacySidecarsAndEvidencePhotos() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let id = UUID()
        let room = savedRoomFixture(
            id: id,
            name: "Deletion fixture",
            floorPlanFileName: "\(id.uuidString)_floorplan.png"
        )
        let filenames = [
            room.usdzFileName,
            "\(id.uuidString).json",
            "\(id.uuidString)_floorplan.png",
            "\(id.uuidString)_floorplan.json",
            "\(id.uuidString)_wifi.json"
        ]
        for filename in filenames {
            try Data([1]).write(to: root.appendingPathComponent(filename))
        }
        let photos = root.appendingPathComponent(id.uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: photos, withIntermediateDirectories: true)
        try Data([1]).write(to: photos.appendingPathComponent("evidence.jpg"))

        let manager = RoomStorageManager(storageDirectory: root)
        try manager.deleteRoom(room)

        for filename in filenames {
            XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent(filename).path))
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: photos.path))
    }

    func testPartialBatchDeletionRetainsOnlyFailedSelectionIDs() {
        enum DeletionFailure: Error {
            case denied
        }
        let deleted = savedRoomFixture(name: "Deleted")
        let retained = savedRoomFixture(name: "Retained")

        let result = RoomBatchDeletion.perform(rooms: [deleted, retained]) { room in
            if room.id == retained.id {
                throw DeletionFailure.denied
            }
        }

        XCTAssertEqual(result.deletedRoomIDs, Set([deleted.id]))
        XCTAssertEqual(result.failedRoomIDs, Set([retained.id]))
        XCTAssertEqual(result.failures.map(\.room.id), [retained.id])
    }

    @MainActor
    func testMetadataUpdateReplacesPackageIndexWithValidJSON() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let id = UUID()
        let original = savedRoomFixture(id: id, name: "Original")
        let package = root.appendingPathComponent(id.uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: package, withIntermediateDirectories: true)
        let metadataURL = package.appendingPathComponent("\(id.uuidString).json")
        try JSONEncoder().encode(original).write(to: metadataURL)

        var edited = original
        edited.name = "Edited"
        edited.notes = "Validated"
        try RoomStorageManager(storageDirectory: root).updateRoom(edited)

        let persisted = try JSONDecoder().decode(
            SavedRoom.self,
            from: Data(contentsOf: metadataURL)
        )
        XCTAssertEqual(persisted.name, "Edited")
        XCTAssertEqual(persisted.notes, "Validated")
        XCTAssertGreaterThan(persisted.lastModified, original.lastModified)
    }

    func testNoWallDataDoesNotInventBoundingRectangleFloor() {
        let data = FloorPlanData(
            elements: [],
            boundingBox: CGRect(x: 0, y: 0, width: 8, height: 5),
            roomDimensions: (8, 2.5, 5)
        )

        XCTAssertTrue(FloorFootprint.resolvedPolygons(from: data).isEmpty)
        XCTAssertNil(RoomSceneBuilder.makeScene(from: data).rootNode.childNode(
            withName: "Floor",
            recursively: true
        ))
    }

    func testPersistedFloorPolygonSupportsNoWallCaptureAndWinsOverLegacyBoundary() {
        let lShape = [
            CGPoint(x: 0, y: 0), CGPoint(x: 4, y: 0),
            CGPoint(x: 4, y: 2), CGPoint(x: 2, y: 2),
            CGPoint(x: 2, y: 4), CGPoint(x: 0, y: 4)
        ]
        let data = FloorPlanData(
            elements: [],
            boundingBox: CGRect(x: 0, y: 0, width: 4, height: 4),
            roomDimensions: (4, 2.5, 4),
            boundary: [
                CGPoint(x: 0, y: 0), CGPoint(x: 4, y: 0),
                CGPoint(x: 4, y: 4), CGPoint(x: 0, y: 4)
            ],
            floorPolygons: [lShape]
        )

        let resolved = FloorFootprint.resolvedPolygons(from: data)

        XCTAssertEqual(resolved.count, 1)
        XCTAssertEqual(FloorFootprint.area(of: resolved[0]), 12, accuracy: 0.001)
        XCTAssertTrue(RoomSceneBuilder.canBuildScene(from: data))
        XCTAssertNotNil(RoomSceneBuilder.makeScene(from: data).rootNode.childNode(
            withName: "Floor",
            recursively: true
        ))
    }

    func testConcaveFloorSceneUsesExplicitTriangulatedGeometry() throws {
        let lShape = [
            CGPoint(x: 0, y: 0), CGPoint(x: 4, y: 0),
            CGPoint(x: 4, y: 2), CGPoint(x: 2, y: 2),
            CGPoint(x: 2, y: 4), CGPoint(x: 0, y: 4)
        ]
        let data = FloorPlanData(
            elements: [],
            boundingBox: CGRect(x: 0, y: 0, width: 4, height: 4),
            roomDimensions: (4, 2.5, 4),
            floorPolygons: [lShape]
        )

        let floor = try XCTUnwrap(RoomSceneBuilder.makeScene(from: data).rootNode.childNode(
            withName: "Floor",
            recursively: true
        ))
        let geometry = try XCTUnwrap(floor.geometry)

        XCTAssertFalse(geometry is SCNShape)
        XCTAssertEqual(geometry.elements.first?.primitiveType, .triangles)
        XCTAssertGreaterThan(geometry.elements.first?.primitiveCount ?? 0, 0)
        XCTAssertEqual(geometry.sources(for: .normal).count, 1)
    }

    private func wall(from start: CGPoint, to end: CGPoint) -> FloorPlanElement {
        let center = CGPoint(x: (start.x + end.x) / 2, y: (start.y + end.y) / 2)
        let length = hypot(end.x - start.x, end.y - start.y)
        return FloorPlanElement(
            rect: CGRect(x: center.x - length / 2, y: center.y - 0.05, width: length, height: 0.1),
            rotation: atan2(end.y - start.y, end.x - start.x),
            type: .wall,
            label: nil,
            elevation: 1.25,
            verticalExtent: 2.5
        )
    }

    private func rectangle(
        x: CGFloat,
        y: CGFloat,
        width: CGFloat,
        height: CGFloat
    ) -> [CGPoint] {
        [
            CGPoint(x: x, y: y),
            CGPoint(x: x + width, y: y),
            CGPoint(x: x + width, y: y + height),
            CGPoint(x: x, y: y + height)
        ]
    }

    private func makeVerticalFixture(
        normalization: FloorPlanVerticalNormalization,
        polygons: [[CGPoint]],
        extents: [CGFloat]
    ) -> FloorPlanData {
        let elements = extents.enumerated().map { index, extent in
            FloorPlanElement(
                rect: CGRect(
                    x: CGFloat(index) * 3,
                    y: -0.05,
                    width: 3,
                    height: 0.1
                ),
                rotation: 0,
                type: .wall,
                label: nil,
                elevation: normalization.elementCenters[index],
                verticalExtent: extent
            )
        }
        return FloorPlanData(
            elements: elements,
            boundingBox: CGRect(x: 0, y: 0, width: 6, height: 3),
            roomDimensions: (6, 2.8, 3),
            floorPolygons: polygons,
            floorComponents: normalization.floorComponents,
            verticalDatum: normalization.datum
        )
    }

    private func floorComponentData(
        polygons: [[CGPoint]],
        elevations: [CGFloat],
        componentPolygons: [[CGPoint]]? = nil
    ) -> FloorPlanData {
        let persistedPolygons = componentPolygons ?? polygons
        return FloorPlanData(
            elements: [],
            boundingBox: CGRect(x: 0, y: 0, width: 5, height: 3),
            roomDimensions: (5, 2.8, 3),
            floorPolygons: polygons,
            floorComponents: zip(persistedPolygons, elevations).map {
                FloorComponent(polygon: $0.0, elevation: $0.1)
            },
            verticalDatum: -1.2
        )
    }

    private func savedRoomFixture(
        id: UUID = UUID(),
        name: String,
        floorPlanFileName: String? = nil
    ) -> SavedRoom {
        return SavedRoom(
            id: id,
            name: name,
            date: Date(timeIntervalSince1970: 0),
            wallCount: 1,
            doorCount: 0,
            windowCount: 0,
            objectCount: 0,
            floorArea: 8,
            roomWidth: 4,
            roomHeight: 2.8,
            roomDepth: 2,
            usdzFileName: "\(id.uuidString).usdz",
            floorPlanFileName: floorPlanFileName,
            roomType: .unknown,
            roomTypeConfidence: 0
        )
    }

    private func pointInsidePolygon(_ point: CGPoint, polygon: [CGPoint]) -> Bool {
        var inside = false
        var previous = polygon.count - 1
        for current in polygon.indices {
            let lhs = polygon[current]
            let rhs = polygon[previous]
            if (lhs.y > point.y) != (rhs.y > point.y),
               point.x < (rhs.x - lhs.x) * (point.y - lhs.y) / (rhs.y - lhs.y) + lhs.x {
                inside.toggle()
            }
            previous = current
        }
        return inside
    }

    private func makeFloorPlanData() -> FloorPlanData {
        FloorPlanData(
            elements: [
                FloorPlanElement(
                    rect: CGRect(x: 0, y: 0, width: 4, height: 0.1),
                    rotation: .pi / 8,
                    type: .wall,
                    label: nil,
                    elevation: 1.25,
                    verticalExtent: 2.5
                ),
                FloorPlanElement(
                    rect: CGRect(x: 1, y: 1, width: 1.2, height: 0.8),
                    rotation: .pi / 4,
                    type: .object(category: "table"),
                    label: "Table",
                    elevation: 0.4,
                    verticalExtent: 0.8
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
