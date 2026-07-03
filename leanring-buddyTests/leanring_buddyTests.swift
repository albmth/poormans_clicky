//
//  leanring_buddyTests.swift
//  leanring-buddyTests
//

import Testing
@testable import leanring_buddy

struct leanring_buddyTests {

    @Test func defaultBackendIsCodexCLI() {
        let backend = AssistantBackendCatalog.defaultDevelopmentBackend()

        #expect(backend.kind == .codexCLI)
    }
}
