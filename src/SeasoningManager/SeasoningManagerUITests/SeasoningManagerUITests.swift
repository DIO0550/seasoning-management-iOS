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
    func testProductRegistrationCancelAndBackDiscardInput() throws {
        let app = makeApplication()
        app.launch()
        XCTAssertTrue(app.staticTexts["商品はまだありません"].waitForExistence(timeout: 5))
        let cancelledName = "Cancel-\(UUID().uuidString)"
        let backName = "Back-\(UUID().uuidString)"
        let type = "!UI-\(UUID().uuidString)"

        openRegistration(in: app)
        enterProduct(name: cancelledName, type: type, in: app)
        app.buttons["product-form-cancel"].tap()

        XCTAssertTrue(app.navigationBars["商品一覧"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["商品はまだありません"].waitForExistence(timeout: 5))
        XCTAssertFalse(productRow(name: cancelledName, type: type, in: app).exists)
        openRegistration(in: app)
        try assertBlankForm(in: app)
        enterProduct(name: backName, type: type, in: app)

        // キャンセルとは別に、標準の戻る操作でも入力だけを捨てる。
        let backButton = app.navigationBars["商品登録"].buttons["商品一覧"]
        XCTAssertTrue(backButton.isHittable)
        backButton.tap()

        XCTAssertTrue(app.navigationBars["商品一覧"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["商品はまだありません"].waitForExistence(timeout: 5))
        XCTAssertFalse(productRow(name: backName, type: type, in: app).exists)
        openRegistration(in: app)
        try assertBlankForm(in: app)
        app.buttons["product-form-cancel"].tap()

        app.terminate()
        app.launch()
        XCTAssertTrue(app.navigationBars["商品一覧"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["商品はまだありません"].waitForExistence(timeout: 5))
        XCTAssertFalse(productRow(name: cancelledName, type: type, in: app).exists)
        XCTAssertFalse(productRow(name: backName, type: type, in: app).exists)
    }

    @MainActor
    func testProductRegistrationSavesAndSurvivesRelaunch() throws {
        let app = makeApplication()
        app.launch()
        XCTAssertTrue(app.staticTexts["商品はまだありません"].waitForExistence(timeout: 5))
        let name = "Product-\(UUID().uuidString)"
        let type = "!UI-\(UUID().uuidString)"

        openRegistration(in: app)
        enterProduct(name: "  \(name)  ", type: "  \(type)  ", in: app)
        app.buttons["product-form-save"].tap()

        XCTAssertTrue(app.navigationBars["商品一覧"].waitForExistence(timeout: 5))
        XCTAssertTrue(productRow(name: name, type: type, in: app).waitForExistence(timeout: 5))

        app.terminate()
        app.launch()

        XCTAssertTrue(app.navigationBars["商品一覧"].waitForExistence(timeout: 5))
        XCTAssertTrue(productRow(name: name, type: type, in: app).waitForExistence(timeout: 5))
    }

    @MainActor
    func testProductRegistrationShowsRequiredErrorAndPreservesInput() throws {
        let app = makeApplication()
        app.launch()
        XCTAssertTrue(app.staticTexts["商品はまだありません"].waitForExistence(timeout: 5))
        let type = "!UI-\(UUID().uuidString)"

        openRegistration(in: app)
        enterProduct(name: "   ", type: type, in: app)
        app.buttons["product-form-save"].tap()

        XCTAssertTrue(app.staticTexts["product-form-name-error"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.navigationBars["商品登録"].exists)
        XCTAssertEqual(app.textFields["product-form-name"].value as? String, "   ")
        XCTAssertEqual(app.textFields["product-form-type"].value as? String, type)

        app.buttons["product-form-cancel"].tap()
        XCTAssertTrue(app.navigationBars["商品一覧"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["商品はまだありません"].waitForExistence(timeout: 5))
    }

    @MainActor
    private func makeApplication() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-test-store-id", UUID().uuidString]
        return app
    }

    @MainActor
    private func openRegistration(in app: XCUIApplication) {
        let productList = app.navigationBars["商品一覧"]
        XCTAssertTrue(productList.waitForExistence(timeout: 5))
        let registerButton = productList.buttons["product-list-register"]
        XCTAssertTrue(registerButton.isHittable)
        registerButton.tap()
        XCTAssertTrue(app.navigationBars["商品登録"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.textFields["product-form-name"].waitForExistence(timeout: 5))
    }

    @MainActor
    private func enterProduct(name: String, type: String, in app: XCUIApplication) {
        let nameField = app.textFields["product-form-name"]
        nameField.tap()
        nameField.typeText(name)
        let typeField = app.textFields["product-form-type"]
        typeField.tap()
        typeField.typeText(type)
    }

    @MainActor
    private func assertBlankForm(in app: XCUIApplication) throws {
        let name = try XCTUnwrap(app.textFields["product-form-name"].value as? String)
        let type = try XCTUnwrap(app.textFields["product-form-type"].value as? String)

        // 未入力欄のvalueはOSにより空文字かプレースホルダーになる。
        XCTAssertTrue(["", "名前"].contains(name))
        XCTAssertTrue(["", "種類"].contains(type))
        XCTAssertFalse(app.staticTexts["product-form-name-error"].exists)
    }

    @MainActor
    private func productRow(name: String, type: String, in app: XCUIApplication) -> XCUIElement {
        let label = "商品名、\(name)、種類、\(type)、未開封、0本、使用中、0本"
        return app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", label)).firstMatch
    }

    @MainActor
    func testLaunchPerformance() throws {
        // This measures how long it takes to launch your application.
        let app = makeApplication()
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            app.launch()
        }
    }
}
