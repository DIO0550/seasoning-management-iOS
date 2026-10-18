//
//  SeasoningManagerUITests.swift
//  SeasoningManagerUITests
//
//  Created by DIO on 2026/09/28.
//

import XCTest

final class SeasoningManagerUITests: XCTestCase {

    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.

        // In UI tests it is usually best to stop immediately when a failure occurs.
        continueAfterFailure = false

        // In UI tests it’s important to set the initial state - such as interface orientation - required for your tests before they run. The setUp method is a good place to do this.
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

    @MainActor
    func testProductRegistrationNavigationAndBack() throws {
        let app = XCUIApplication()
        app.launch()

        // 保存済み商品の有無によらず、共通の登録操作から遷移できる。
        let productList = app.navigationBars["商品一覧"]
        XCTAssertTrue(productList.waitForExistence(timeout: 5))

        let registerButton = productList.buttons["product-list-register"]
        XCTAssertTrue(registerButton.isHittable)
        registerButton.tap()

        let registration = app.navigationBars["商品登録"]
        XCTAssertTrue(registration.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["商品登録機能は準備中です"].exists)
        XCTAssertFalse(app.buttons["保存"].exists)
        XCTAssertFalse(app.textFields.firstMatch.exists)

        // 暫定画面の標準戻るボタンで一覧と登録操作に戻れる。
        let backButton = registration.buttons.element(boundBy: 0)
        XCTAssertTrue(backButton.isHittable)
        backButton.tap()

        XCTAssertTrue(productList.waitForExistence(timeout: 5))
        XCTAssertTrue(registerButton.isHittable)
    }

    @MainActor
    func testLaunchPerformance() throws {
        // This measures how long it takes to launch your application.
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            XCUIApplication().launch()
        }
    }
}
