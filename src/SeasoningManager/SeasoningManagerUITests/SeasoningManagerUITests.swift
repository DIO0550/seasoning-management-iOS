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
        try enterProduct(name: cancelledName, type: type, in: app)
        app.buttons["product-form-cancel"].tap()

        XCTAssertTrue(app.navigationBars["商品一覧"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["商品はまだありません"].waitForExistence(timeout: 5))
        XCTAssertFalse(productRow(name: cancelledName, type: type, in: app).exists)
        openRegistration(in: app)
        try assertBlankForm(in: app)
        try enterProduct(name: backName, type: type, in: app)

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
        try enterProduct(name: "  \(name)  ", type: "  \(type)  ", in: app)
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
        try enterProduct(name: name, type: type, in: app)
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
        try enterProduct(name: "   ", type: type, in: app)
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
        try registerAndOpenDetail(name: "Before", type: "Type", in: app)
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
        try registerAndOpenDetail(name: "Before", type: "Type", in: app)
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
        try registerAndOpenDetail(name: "Before", type: "Type", in: app)
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
        try enterProduct(name: "Extras", type: "Type", in: app)
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

        let price = try formField("product-form-price", in: app)
        XCTAssertEqual(price.value as? String, "0")
        XCTAssertEqual(price.label, "価格、円、任意")
        XCTAssertEqual(try formField("product-form-calories", in: app).value as? String, "12.34")
        try assertBlankOptionalField("product-form-protein", in: app)
        XCTAssertEqual(try formField("product-form-fat", in: app).value as? String, "0")
        XCTAssertEqual(try formField("product-form-sugar", in: app).value as? String, "4.56")
        try assertBlankOptionalField("product-form-carbohydrates", in: app)
        let basisAmount = try formField("product-form-basis-amount", in: app)
        XCTAssertEqual(basisAmount.value as? String, "15")
        XCTAssertEqual(basisAmount.label, "基準量、栄養素を入力した場合は必須")
        XCTAssertEqual(try formField("product-form-basis-unit", in: app).value as? String, "mL")
    }

    @MainActor
    func testOptionalInputErrorsKeepValuesAndAllowCorrection() throws {
        let app = makeApplication()
        app.launch()
        openRegistration(in: app)
        try enterProduct(name: "Corrected", type: "Type", in: app)
        try replaceFormValue("-1", field: "product-form-price", in: app)
        app.buttons["product-form-save"].tap()

        XCTAssertTrue(app.staticTexts["product-form-price-error"].waitForExistence(timeout: 5))
        XCTAssertEqual(try formField("product-form-price", in: app).value as? String, "-1")
        try replaceFormValue("0", field: "product-form-price", in: app)
        try replaceFormValue("1.234", field: "product-form-calories", in: app)
        app.buttons["product-form-save"].tap()
        XCTAssertTrue(app.staticTexts["product-form-calories-error"].waitForExistence(timeout: 5))
        XCTAssertEqual(try formField("product-form-calories", in: app).value as? String, "1.234")
        try replaceFormValue("0", field: "product-form-calories", in: app)
        app.buttons["product-form-save"].tap()
        let amount = try formField("product-form-basis-amount", in: app)
        XCTAssertTrue(amount.isHittable)
        XCTAssertTrue(app.staticTexts["product-form-basis-amount-error"].exists)
        try replaceFormValue("0", field: "product-form-basis-amount", in: app)
        app.buttons["product-form-save"].tap()
        XCTAssertTrue(app.staticTexts["product-form-basis-amount-error"].label.contains("0より大きい"))
        try replaceFormValue("100", field: "product-form-basis-amount", in: app)
        app.buttons["product-form-save"].tap()
        XCTAssertTrue(try formField("product-form-basis-unit", in: app).isHittable)
        XCTAssertTrue(app.staticTexts["product-form-basis-unit-error"].waitForExistence(timeout: 5))
        try replaceFormValue("g", field: "product-form-basis-unit", in: app)
        app.buttons["product-form-save"].tap()

        let row = productRow(name: "Corrected", type: "Type", in: app)
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.tap()
        openEditing(in: app)
        XCTAssertEqual(try formField("product-form-price", in: app).value as? String, "0")
        XCTAssertEqual(try formField("product-form-calories", in: app).value as? String, "0")
    }

    @MainActor
    func testOptionalEditingCancelAndClearLastNutrient() throws {
        let app = makeApplication()
        app.launch()
        try registerAndOpenDetail(name: "Clear", type: "Type", in: app)
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
        XCTAssertEqual(try formField("product-form-price", in: app).value as? String, "0")
        XCTAssertEqual(try formField("product-form-calories", in: app).value as? String, "0")

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

    private enum FormInputFailure: Error {
        case unavailable
    }

    @MainActor
    private func formField(_ identifier: String, in app: XCUIApplication) throws -> XCUIElement {
        let field = app.textFields[identifier]
        // 未生成のセルは、上端へ戻してから下へ探す。各操作の前に領域を取り直す。
        if !field.exists {
            for _ in 0..<12 {
                if field.exists {
                    break
                }

                try scrollForm(towardTop: true, in: app)
            }
        }

        for _ in 0..<24 {
            let safeFrame = try formInteractionFrame(in: app)
            if field.exists {
                let frame = field.frame
                if !frame.isEmpty, safeFrame.contains(frame), field.isHittable {
                    return field
                }

                try scrollForm(towardTop: frame.minY < safeFrame.minY, in: app)
            } else {
                try scrollForm(towardTop: false, in: app)
            }
        }

        let safeFrame = try formInteractionFrame(in: app)
        XCTFail("入力欄を操作できない: \(identifier)、欄: \(field.frame)、操作領域: \(safeFrame)")
        throw FormInputFailure.unavailable
    }

    @MainActor
    private func formInteractionFrame(in app: XCUIApplication) throws -> CGRect {
        let form = app.collectionViews.firstMatch
        let frame = form.frame.intersection(app.frame)
        let navigationBar = app.navigationBars.firstMatch
        let top = max(frame.minY, navigationBar.frame.maxY) + 12
        var bottom = frame.maxY - 12
        let keyboard = app.keyboards.firstMatch
        if keyboard.exists, keyboard.frame.intersects(frame) {
            bottom = min(bottom, keyboard.frame.minY - 12)
        }

        let safeFrame = CGRect(x: frame.minX + 12, y: top, width: frame.width - 24, height: bottom - top)
        guard !frame.isNull, safeFrame.width > 24, safeFrame.height > 80 else {
            XCTFail("フォームの操作領域を確保できない: フォーム \(frame)、操作領域 \(safeFrame)")
            throw FormInputFailure.unavailable
        }

        return safeFrame
    }

    @MainActor
    private func scrollForm(towardTop: Bool, in app: XCUIApplication) throws {
        let safeFrame = try formInteractionFrame(in: app)
        let distance = min(safeFrame.height * 0.35, 140)
        let offset = towardTop ? distance : -distance
        let origin = app.coordinate(withNormalizedOffset: .zero)
        // 文字列の選択を始めないよう、入力欄の右側の余白から短くドラッグする。
        let x = safeFrame.maxX - 4 - app.frame.minX
        let start = origin.withOffset(CGVector(dx: x, dy: safeFrame.midY - offset / 2 - app.frame.minY))
        let end = origin.withOffset(CGVector(dx: x, dy: safeFrame.midY + offset / 2 - app.frame.minY))
        start.press(forDuration: 0.01, thenDragTo: end)
    }

    @MainActor
    private func assertBlankOptionalField(_ identifier: String, in app: XCUIApplication) throws {
        let field = try formField(identifier, in: app)
        let value = try XCTUnwrap(field.value as? String)
        XCTAssertTrue(["", field.placeholderValue ?? ""].contains(value))
    }

    @MainActor
    private func registerAndOpenDetail(name: String, type: String, in app: XCUIApplication) throws {
        openRegistration(in: app)
        try enterProduct(name: name, type: type, in: app)
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
        var focusedField: XCUIElement?
        let keyboard = app.keyboards.firstMatch
        // タップ後に現れるキーボードで領域が変わるため、改めて欄全体を確認する。
        for _ in 0..<3 {
            let candidate = try formField(field, in: app)
            candidate.coordinate(withNormalizedOffset: CGVector(dx: 0.98, dy: 0.5)).tap()
            guard keyboard.waitForExistence(timeout: 5) else {
                XCTFail("キーボードが表示されない: \(field)")
                throw FormInputFailure.unavailable
            }

            let safeFrame = try formInteractionFrame(in: app)
            if safeFrame.contains(candidate.frame), candidate.isHittable {
                focusedField = candidate
                break
            }
        }

        let textField = try XCTUnwrap(focusedField, "キーボード表示後に入力欄全体を操作できない: \(field)")
        let current = try XCTUnwrap(textField.value as? String)
        let content = current == textField.placeholderValue ? "" : current
        if !content.isEmpty {
            textField.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: content.count))
        }
        try waitForFormValue("", field: textField)

        if value.isEmpty {
            return
        }

        textField.typeText(value)
        try waitForFormValue(value, field: textField)
    }

    @MainActor
    private func waitForFormValue(_ value: String, field: XCUIElement) throws {
        let expected = value.isEmpty ? ["", field.placeholderValue ?? ""] : [value]
        let expectation = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value IN %@", expected as NSArray), object: field
        )
        guard XCTWaiter.wait(for: [expectation], timeout: 5) == .completed else {
            XCTFail("入力値が反映されない: \(field.identifier)、期待: \(value)、実際: \(String(describing: field.value))")
            throw FormInputFailure.unavailable
        }
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
    private func enterProduct(name: String, type: String, in app: XCUIApplication) throws {
        try replaceFormValue(name, field: "product-form-name", in: app)
        try replaceFormValue(type, field: "product-form-type", in: app)
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
