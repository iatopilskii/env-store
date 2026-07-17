import Foundation
import Testing
@testable import EnvStoreCore

struct ProjectBindingResolverTests {
    @Test
    func choosesNearestAncestorBinding() {
        let rootSetID = UUID()
        let nestedSetID = UUID()
        let bindings = [
            ProjectBinding(path: "/workspace", setID: rootSetID),
            ProjectBinding(path: "/workspace/apps/api", setID: nestedSetID),
        ]

        let binding = ProjectBindingResolver().resolve(
            workingDirectory: "/workspace/apps/api/Sources",
            bindings: bindings
        )

        #expect(binding?.setID == nestedSetID)
    }

    @Test
    func rejectsTextualPrefixThatIsNotPathAncestor() {
        let binding = ProjectBinding(path: "/workspace/api", setID: UUID())

        let result = ProjectBindingResolver().resolve(
            workingDirectory: "/workspace/api-malicious",
            bindings: [binding]
        )

        #expect(result == nil)
    }

    @Test
    func standardizesDotSegmentsBeforeMatching() {
        let binding = ProjectBinding(path: "/workspace/apps/api", setID: UUID())

        let result = ProjectBindingResolver().resolve(
            workingDirectory: "/workspace/apps/web/../api/Sources/.",
            bindings: [binding]
        )

        #expect(result?.id == binding.id)
    }
}

