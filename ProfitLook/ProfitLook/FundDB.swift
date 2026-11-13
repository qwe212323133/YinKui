import Foundation

/// 基金代码 → 名称：内嵌全量库 funddb.txt（28330 条），本地查表、零网络。
final class FundDB {
    static let shared = FundDB()
    private var map: [String: String]? = nil

    private func ensureLoaded() {
        if map != nil { return }
        var m: [String: String] = [:]
        if let url = Bundle.main.url(forResource: "funddb", withExtension: "txt"),
           let text = try? String(contentsOf: url, encoding: .utf8) {
            for line in text.split(separator: "\n") {
                let i = line.firstIndex(of: "|")  // 用 Character 比较，避免 Unicode 下标偏移
                if let i = i {
                    let code = String(line[line.startIndex..<i])
                    let name = String(line[line.index(after: i)...])
                    if !code.isEmpty && !name.isEmpty { m[code] = name }
                }
            }
        }
        map = m
    }

    func name(for code: String) -> String? {
        ensureLoaded()
        return map?[code]
    }
}
