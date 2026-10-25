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
    func testProductListOpensDetailsAndReturnsToList() throws {
        let app = makeApplication()
        app.launch()
        XCTAssertTrue(app.staticTexts["商品はまだありません"].waitForExistence(timeout: 5))
        let name = "Detail-\(UUID().uuidString)"
        let type = "!UI-\(UUID().uuidString)"

        openRegistration(in: app)
        enterProduct(name: name, type: type, in: app)
        app.buttons["product-form-save"].tap()
        let row = productRow(name: name, type: type, in: app)
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.tap()

        let navigationBar = app.navigationBars["商品詳細"]
        XCTAssertTrue(navigationBar.waitForExistence(timeout: 5))
        let nameRow = app.descendants(matching: .any)["product-detail-name"]
        let typeRow = app.descendants(matching: .any)["product-detail-type"]
        let priceRow = app.descendants(matching: .any)["product-detail-price"]
        XCTAssertTrue(nameRow.waitForExistence(timeout: 5))
        XCTAssertEqual(nameRow.label, "名前、\(name)")
        XCTAssertEqual(typeRow.label, "種類、\(type)")
        XCTAssertEqual(priceRow.label, "価格、未設定")
        XCTAssertTrue(app.staticTexts["画像なし"].exists)

        // 標準の戻る操作で一覧へ戻り、選択した商品が残ることを確かめる。
        navigationBar.buttons["商品一覧"].tap()
        XCTAssertTrue(app.navigationBars["商品一覧"].waitForExistence(timeout: 5))
        XCTAssertTrue(productRow(name: name, type: type, in: app).exists)
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
    func testProductEditingSavesToDetailsAndSurvivesRelaunch() throws {
        let app = makeApplication()
        app.launch()
        registerAndOpenDetail(name: "Before", type: "Type", in: app)
        openEditing(in: app)
        assertForm(name: "Before", type: "Type", in: app)

        try replaceFormValue("After", field: "product-form-name", in: app)
        try replaceFormValue("Edited", field: "product-form-type", in: app)
        app.buttons["product-form-save"].tap()

        assertDetail(name: "After", type: "Edited", in: app)
        app.navigationBars["商品詳細"].buttons["商品一覧"].tap()
        XCTAssertTrue(productRow(name: "After", type: "Edited", in: app).waitForExistence(timeout: 5))
        XCTAssertFalse(productRow(name: "Before", type: "Type", in: app).exists)

        app.terminate()
        app.launch()

        let row = productRow(name: "After", type: "Edited", in: app)
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        XCTAssertFalse(productRow(name: "Before", type: "Type", in: app).exists)
        row.tap()
        assertDetail(name: "After", type: "Edited", in: app)
        openEditing(in: app)
        assertForm(name: "After", type: "Edited", in: app)
    }

    @MainActor
    func testProductEditingCancelAndBackKeepSavedValues() throws {
        let app = makeApplication()
        app.launch()
        registerAndOpenDetail(name: "Before", type: "Type", in: app)
        openEditing(in: app)
        try replaceFormValue("Cancelled", field: "product-form-name", in: app)
        try replaceFormValue("Changed", field: "product-form-type", in: app)

        app.buttons["product-form-cancel"].tap()

        assertDetail(name: "Before", type: "Type", in: app)
        openEditing(in: app)
        assertForm(name: "Before", type: "Type", in: app)
        try replaceFormValue("Discarded", field: "product-form-name", in: app)
        try replaceFormValue("Changed", field: "product-form-type", in: app)

        // 標準の戻る操作でも、編集途中の内容を保存しない。
        app.navigationBars["商品編集"].buttons["商品詳細"].tap()

        assertDetail(name: "Before", type: "Type", in: app)
        openEditing(in: app)
        assertForm(name: "Before", type: "Type", in: app)
        app.buttons["product-form-cancel"].tap()
        app.terminate()
        app.launch()

        XCTAssertTrue(productRow(name: "Before", type: "Type", in: app).waitForExistence(timeout: 5))
        XCTAssertFalse(productRow(name: "Cancelled", type: "Changed", in: app).exists)
        XCTAssertFalse(productRow(name: "Discarded", type: "Changed", in: app).exists)
    }

    @MainActor
    func testProductEditingRequiredErrorKeepsInputAndAllowsCorrection() throws {
        let app = makeApplication()
        app.launch()
        registerAndOpenDetail(name: "Before", type: "Type", in: app)
        openEditing(in: app)
        try replaceFormValue("   ", field: "product-form-name", in: app)
        try replaceFormValue("Edited", field: "product-form-type", in: app)

        app.buttons["product-form-save"].tap()

        XCTAssertTrue(app.staticTexts["product-form-name-error"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.navigationBars["商品編集"].exists)
        assertForm(name: "   ", type: "Edited", in: app)
        try replaceFormValue("Corrected", field: "product-form-name", in: app)
        app.buttons["product-form-save"].tap()

        assertDetail(name: "Corrected", type: "Edited", in: app)
    }

    @MainActor
    func testOptionalInputsSaveAndReopenAfterRelaunch() throws {
        let app = makeApplication()
        app.launch()
        openRegistration(in: app)
        enterProduct(name: "Extras", type: "Type", in: app)
        try replaceFormValue("0", field: "product-form-price", in: app)
        try replaceFormValue("12.34", field: "product-form-calories", in: app)
        try replaceFormValue("0", field: "product-form-fat", in: app)
        try replaceFormValue("4.56", field: "product-form-sugar", in: app)
        try replaceFormValue("15", field: "product-form-basis-amount", in: app)
        try replaceFormValue("mL", field: "product-form-basis-unit", in: app)
        app.buttons["product-form-save"].tap()
        XCTAssertTrue(productRow(name: "Extras", type: "Type", in: app).waitForExistence(timeout: 5))
        app.terminate()
        app.launch()
        let row = productRow(name: "Extras", type: "Type", in: app)
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.tap()
        openEditing(in: app)

        XCTAssertEqual(formField("product-form-price", in: app).value as? String, "0")
        XCTAssertEqual(formField("product-form-calories", in: app).value as? String, "12.34")
        try assertBlankOptionalField("product-form-protein", in: app)
        XCTAssertEqual(formField("product-form-fat", in: app).value as? String, "0")
        XCTAssertEqual(formField("product-form-sugar", in: app).value as? String, "4.56")
        try assertBlankOptionalField("product-form-carbohydrates", in: app)
        XCTAssertEqual(formField("product-form-basis-amount", in: app).value as? String, "15")
        XCTAssertEqual(formField("product-form-basis-unit", in: app).value as? String, "mL")
    }

    @MainActor
    func testOptionalInputErrorsKeepValuesAndAllowCorrection() throws {
        let app = makeApplication()
        app.launch()
        openRegistration(in: app)
        enterProduct(name: "Corrected", type: "Type", in: app)
        try replaceFormValue("-1", field: "product-form-price", in: app)
        app.buttons["product-form-save"].tap()

        XCTAssertTrue(app.staticTexts["product-form-price-error"].waitForExistence(timeout: 5))
        XCTAssertEqual(formField("product-form-price", in: app).value as? String, "-1")
        try replaceFormValue("0", field: "product-form-price", in: app)
        try replaceFormValue("1.234", field: "product-form-calories", in: app)
        app.buttons["product-form-save"].tap()
        XCTAssertTrue(app.staticTexts["product-form-calories-error"].waitForExistence(timeout: 5))
        XCTAssertEqual(formField("product-form-calories", in: app).value as? String, "1.234")
        try replaceFormValue("0", field: "product-form-calories", in: app)
        app.buttons["product-form-save"].tap()
        let amount = formField("product-form-basis-amount", in: app)
        XCTAssertTrue(amount.isHittable)
        XCTAssertTrue(app.staticTexts["product-form-basis-amount-error"].exists)
        try replaceFormValue("0", field: "product-form-basis-amount", in: app)
        app.buttons["product-form-save"].tap()
        XCTAssertTrue(app.staticTexts["product-form-basis-amount-error"].label.contains("0より大きい"))
        try replaceFormValue("100", field: "product-form-basis-amount", in: app)
        app.buttons["product-form-save"].tap()
        XCTAssertTrue(formField("product-form-basis-unit", in: app).isHittable)
        XCTAssertTrue(app.staticTexts["product-form-basis-unit-error"].waitForExistence(timeout: 5))
        try replaceFormValue("g", field: "product-form-basis-unit", in: app)
        app.buttons["product-form-save"].tap()

        let row = productRow(name: "Corrected", type: "Type", in: app)
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.tap()
        openEditing(in: app)
        XCTAssertEqual(formField("product-form-price", in: app).value as? String, "0")
        XCTAssertEqual(formField("product-form-calories", in: app).value as? String, "0")
    }

    @MainActor
    func testOptionalEditingCancelAndClearLastNutrient() throws {
        let app = makeApplication()
        app.launch()
        registerAndOpenDetail(name: "Clear", type: "Type", in: app)
        openEditing(in: app)
        try replaceFormValue("0", field: "product-form-price", in: app)
        try replaceFormValue("0", field: "product-form-calories", in: app)
        try replaceFormValue("100", field: "product-form-basis-amount", in: app)
        try replaceFormValue("g", field: "product-form-basis-unit", in: app)
        app.buttons["product-form-save"].tap()
        openEditing(in: app)
        try replaceFormValue("398", field: "product-form-price", in: app)
        try replaceFormValue("1.23", field: "product-form-calories", in: app)
        app.buttons["product-form-cancel"].tap()
        openEditing(in: app)
        XCTAssertEqual(formField("product-form-price", in: app).value as? String, "0")
        XCTAssertEqual(formField("product-form-calories", in: app).value as? String, "0")

        // 最後の栄養素だけ消し、欄に残った基準が保存されないことを再編集で確かめる。
        try replaceFormValue("", field: "product-form-price", in: app)
        try replaceFormValue("", field: "product-form-calories", in: app)
        app.buttons["product-form-save"].tap()
        openEditing(in: app)
        try assertBlankOptionalField("product-form-price", in: app)
        try assertBlankOptionalField("product-form-calories", in: app)
        try assertBlankOptionalField("product-form-basis-amount", in: app)
        try assertBlankOptionalField("product-form-basis-unit", in: app)
    }

    @MainActor
    private func formField(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
        let field = app.textFields[identifier]
        let form = app.collectionViews.firstMatch
        // 未生成のセルを探す場合は一度上端へ戻し、上から順に探す。
        if !field.exists {
            for _ in 0..<6 {
                form.swipeDown()
            }
        }

        for _ in 0..<12 {
            if field.isHittable {
                return field
            }

            if field.exists, field.frame.minY < app.navigationBars.firstMatch.frame.maxY {
                form.swipeDown()
            } else {
                form.swipeUp()
            }
        }

        XCTAssertTrue(field.isHittable, "入力欄を操作できない: \(identifier)")
        return field
    }

    @MainActor
    private func assertBlankOptionalField(_ identifier: String, in app: XCUIApplication) throws {
        let field = formField(identifier, in: app)
        let value = try XCTUnwrap(field.value as? String)
        XCTAssertTrue(["", field.placeholderValue ?? ""].contains(value))
    }

    @MainActor
    private func registerAndOpenDetail(name: String, type: String, in app: XCUIApplication) {
        openRegistration(in: app)
        enterProduct(name: name, type: type, in: app)
        app.buttons["product-form-save"].tap()
        let row = productRow(name: name, type: type, in: app)
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.tap()
        assertDetail(name: name, type: type, in: app)
    }

    @MainActor
    private func openEditing(in app: XCUIApplication) {
        let detail = app.navigationBars["商品詳細"]
        XCTAssertTrue(detail.waitForExistence(timeout: 5))
        let edit = detail.buttons["product-detail-edit"]
        XCTAssertTrue(edit.isHittable)
        edit.tap()
        XCTAssertTrue(app.navigationBars["商品編集"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.textFields["product-form-name"].waitForExistence(timeout: 5))
    }

    @MainActor
    private func assertForm(name: String, type: String, in app: XCUIApplication) {
        XCTAssertEqual(app.textFields["product-form-name"].value as? String, name)
        XCTAssertEqual(app.textFields["product-form-type"].value as? String, type)
    }

    @MainActor
    private func assertDetail(name: String, type: String, in app: XCUIApplication) {
        XCTAssertTrue(app.navigationBars["商品詳細"].waitForExistence(timeout: 5))
        let nameRow = app.descendants(matching: .any)["product-detail-name"]
        XCTAssertTrue(nameRow.waitForExistence(timeout: 5))
        XCTAssertEqual(nameRow.label, "名前、\(name)")
        XCTAssertEqual(app.descendants(matching: .any)["product-detail-type"].label, "種類、\(type)")
    }

    @MainActor
    private func replaceFormValue(_ value: String, field: String, in app: XCUIApplication) throws {
        let textField = formField(field, in: app)
        let current = try XCTUnwrap(textField.value as? String)
        let content = current == textField.placeholderValue ? "" : current
        textField.tap()
        textField.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: content.count) + value)
        if value.isEmpty {
            try assertBlankOptionalField(field, in: app)
            return
        }

        XCTAssertEqual(textField.value as? String, value)
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
