//
//  GPS_LoggerUITests.swift
//  GPS LoggerUITests
//
//  Created by 小祝賢一 on 2025/03/22.
//

import XCTest

final class GPS_LoggerUITests: XCTestCase {

    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.

        // In UI tests it is usually best to stop immediately when a failure occurs.
        continueAfterFailure = false

        // In UI tests it’s important to set the initial state - such as interface orientation - required for your tests before they run. The setUp method is a good place to do this.
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

    /// Basic recording and measurement flow.
    @MainActor
    func testRecordAndMeasureFlow() throws {
        let app = XCUIApplication()
        app.launch()

        let startButton = app.buttons["記録開始"]
        XCTAssertTrue(startButton.waitForExistence(timeout: 2))
        startButton.tap()

        let stopButton = app.buttons["記録停止"]
        XCTAssertTrue(stopButton.waitForExistence(timeout: 2))

        let measureStart = app.buttons["距離計測開始"]
        XCTAssertTrue(measureStart.waitForExistence(timeout: 2))
        measureStart.tap()

        let measureEnd = app.buttons["距離計測終了"]
        XCTAssertTrue(measureEnd.waitForExistence(timeout: 2))
        measureEnd.tap()

        stopButton.tap()
    }

    @MainActor
    func testLaunchPerformance() throws {
        if #available(macOS 10.15, iOS 13.0, tvOS 13.0, watchOS 7.0, *) {
            // This measures how long it takes to launch your application.
            measure(metrics: [XCTApplicationLaunchMetric()]) {
                XCUIApplication().launch()
            }
        }
    }
}
