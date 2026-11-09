import Testing
@testable import TrayCore

@Test func repeatedReordersCommitImmediately() {
    let first = ShelfOrder.moving(1, beside: 3, before: false, in: [1, 2, 3, 4])
    #expect(first == [2, 3, 1, 4])
    let second = ShelfOrder.moving(4, beside: 2, before: true, in: first)
    #expect(second == [4, 2, 3, 1])
    #expect(ShelfOrder.moving(3, beside: 1, before: true, in: second) == second)
}

@Test func invalidReordersLeaveTheOrderUnchanged() {
    let original = [1, 2, 3]
    #expect(ShelfOrder.moving(1, beside: 1, before: false, in: original) == original)
    #expect(ShelfOrder.moving(9, beside: 1, before: true, in: original) == original)
    #expect(ShelfOrder.moving(1, beside: 9, before: true, in: original) == original)
}

@Test func savedOrderSurvivesRefreshAndNewWindowIDs() {
    let saved = ["app-c", "app-a", "app-b"]
    let nativeKeys = ["app-a", "app-b", "app-c"]
    let freshWindowIDs = [101, 202, 303]
    #expect(ShelfOrder.indices(for: nativeKeys, saved: saved).map { freshWindowIDs[$0] } == [303, 101, 202])
    let refreshedKeys = ["app-b", "app-c", "app-a"]
    #expect(ShelfOrder.indices(for: refreshedKeys, saved: saved).map { refreshedKeys[$0] } == saved)
}

@Test func missingAndNewIconsDoNotResetSavedOrder() {
    let keys = ["new-1", "app-b", "new-2", "app-a"]
    #expect(ShelfOrder.indices(for: keys, saved: ["app-c", "app-a", "app-b", "app-a"]).map { keys[$0] }
            == ["app-a", "app-b", "new-1", "new-2"])
}

@Test func savedIdentitySeparatesAppsExtrasAndDelimiterCharacters() {
    #expect(ShelfOrder.identity(bundle: "a:b", title: "c", occurrence: 0)
            != ShelfOrder.identity(bundle: "a", title: "b:c", occurrence: 0))
    #expect(ShelfOrder.identity(bundle: "app", title: "Item", occurrence: 0)
            != ShelfOrder.identity(bundle: "app", title: "Item", occurrence: 1))
}
