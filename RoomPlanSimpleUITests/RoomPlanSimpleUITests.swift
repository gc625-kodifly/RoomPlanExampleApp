//
//  RoomPlanSimpleUITests.swift
//  RoomPlanSimpleUITests
//
//  Created by Holger Trahe on 04.12.25.
//  Copyright © 2025 Apple. All rights reserved.
//

import XCTest

final class RoomPlanSimpleUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testHomeScreenPrimaryActionsExist() throws {
        let app = XCUIApplication()
        app.launch()

        XCTAssertTrue(app.buttons["home.newScan"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["home.savedRooms"].exists)
    }

    @MainActor
    func testOpenSavedRoomsWorkspace() throws {
        let app = XCUIApplication()
        app.launch()

        let savedRooms = app.buttons["home.savedRooms"]
        XCTAssertTrue(savedRooms.waitForExistence(timeout: 5))
        savedRooms.tap()

        XCTAssertTrue(app.searchFields["savedRooms.search"].waitForExistence(timeout: 5)
            || app.otherElements["savedRooms.search"].waitForExistence(timeout: 2)
            || app.navigationBars.element.waitForExistence(timeout: 5))
    }

    @MainActor
    func testLaunchPerformance() throws {
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            XCUIApplication().launch()
        }
    }
}
