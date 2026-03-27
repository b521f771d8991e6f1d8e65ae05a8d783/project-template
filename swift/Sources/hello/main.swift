import Foundation
import project_template

print("hello from project-template v\(ProjectTemplate.version)")

if let url = Bundle.module.url(forResource: "greeting", withExtension: "txt"),
   let content = try? String(contentsOf: url, encoding: .utf8) {
    print("Resource says: \(content)")
} else {
    print("ERROR: Could not load greeting.txt resource!")
}
