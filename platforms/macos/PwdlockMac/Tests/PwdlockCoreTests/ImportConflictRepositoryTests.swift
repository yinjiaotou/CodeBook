import Foundation
import Testing
@testable import PwdlockCore

@Test("import merge summary exposes added identical and conflict counts")
func importMergeSummaryContract() {
    let summary = ImportMergeSummary(added: 2, identical: 3, conflicts: 1)

    #expect(summary == ImportMergeSummary(added: 2, identical: 3, conflicts: 1))
}

@Test("manual merge input contains only editable business fields")
func manualMergeInputContract() {
    let input = ManualLoginMerge(
        title: "GitHub",
        username: "yin",
        password: "secret",
        url: "https://github.com",
        category: "工作",
        note: "主账号"
    )

    #expect(input.title == "GitHub")
    #expect(input.note == "主账号")
}
