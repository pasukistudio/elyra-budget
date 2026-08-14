//
//  ElyraBudgetUITests.swift
//  ElyraBudgetUITests
//
//  Created by Pascal Smigielski on 04.08.26.
//

import XCTest

final class ElyraBudgetUITests: XCTestCase {

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
    private func launchTestApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-ui-testing-skip-onboarding"]
        app.launchEnvironment["ELYRA_BUDGET_USE_CLOUDKIT"] = "NO"
        app.launch()
        return app
    }

    @MainActor
    func testPrimaryNavigationAndBudgetEditorAreAvailable() throws {
        let app = launchTestApp()

        let budgetsTab = app.tabBars.buttons["Budgets"]
        XCTAssertTrue(budgetsTab.waitForExistence(timeout: 8))
        budgetsTab.tap()

        let actions = app.buttons["Budgetaktionen"]
        XCTAssertTrue(actions.waitForExistence(timeout: 5))
        actions.tap()

        let newBudget = app.buttons["Neues Budget"]
        XCTAssertTrue(newBudget.waitForExistence(timeout: 5))
        newBudget.tap()
        XCTAssertTrue(app.navigationBars["Neues Budget"].waitForExistence(timeout: 5))

        app.buttons["Abbrechen"].tap()
    }

    @MainActor
    func testTransactionActionsMenuIsAvailable() throws {
        let app = launchTestApp()

        let transactionsTab = app.tabBars.buttons["Buchungen"]
        XCTAssertTrue(transactionsTab.waitForExistence(timeout: 8))
        transactionsTab.tap()

        let actions = app.buttons["Buchungsaktionen"]
        XCTAssertTrue(actions.waitForExistence(timeout: 5))
        actions.tap()

        XCTAssertTrue(app.buttons["Neue Buchung"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["CSV exportieren"].exists)
    }

    @MainActor
    func testExample() throws {
        // Keep the template test as a lightweight launch smoke test.
        _ = launchTestApp()
    }

    @MainActor
    func testLaunchPerformance() throws {
        // This measures how long it takes to launch your application.
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            let app = XCUIApplication()
            app.launchEnvironment["ELYRA_BUDGET_USE_CLOUDKIT"] = "NO"
            app.launch()
        }
    }
}
