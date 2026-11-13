import Foundation

struct FundQuote {
    var nav: Double = 0
    var pct: Double = 0
    var time: String = ""
}

/// 真实单位净值与日涨跌：天天基金 pingzhongdata 接口。
/// 该接口返回 JS，内含 Data_netWorthTrend 数组（[{x:时间戳ms, y:单位净值, equityReturn:日涨跌%, unitMoney:""}, ...]）。
/// 取最后一条作为最新单位净值与当日涨跌幅。接口稳定、无需特殊 Header，替代已下线的 fundgz。
final class QuoteService {
    static let shared = QuoteService()
    private init() {}

    func refresh(_ funds: [Fund], completion: @escaping (Int, [String: FundQuote]) -> Void) {
        guard !funds.isEmpty else {
            DispatchQueue.main.async { completion(0, [:]) }
            return
        }
        let group = DispatchGroup()
        let lock = NSLock()
        var map: [String: FundQuote] = [:]
        var okCount = 0
        let ua = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 Version/17.0 Mobile/15E148 Safari/604.1"

        for f in funds {
            guard let url = URL(string: "https://fund.eastmoney.com/pingzhongdata/\(f.code).js") else { continue }
            var req = URLRequest(url: url, timeoutInterval: 15)
            req.setValue("https://fund.eastmoney.com/", forHTTPHeaderField: "Referer")
            req.setValue(ua, forHTTPHeaderField: "User-Agent")
            group.enter()
            URLSession.shared.dataTask(with: req) { data, _, _ in
                defer { group.leave() }
                guard let data = data,
                      let raw = String(data: data, encoding: .utf8),
                      let q = QuoteService.parse(raw) else { return }
                lock.lock()
                map[f.code] = q
                okCount += 1
                lock.unlock()
            }.resume()
        }
        group.notify(queue: .main) { completion(okCount, map) }
    }

    /// 从 pingzhongdata JS 文本提取 Data_netWorthTrend 的最新一条：
    /// {"x":<ms>,"y":<单位净值>,"equityReturn":<日涨跌%>,"unitMoney":""}
    /// 取最后一个匹配点（即最新净值）。
    private static func parse(_ raw: String) -> FundQuote? {
        let pattern = "\\{\"x\":(\\d+),\"y\":([0-9.]+),\"equityReturn\":(-?[0-9.]+)"
        guard let re = try? NSRegularExpression(pattern: pattern) else { return nil }
        let ns = raw as NSString
        let matches = re.matches(in: raw, range: NSRange(location: 0, length: ns.length))
        guard let last = matches.last, last.numberOfRanges >= 4 else { return nil }
        let ts = ns.substring(with: last.range(at: 1))
        let navStr = ns.substring(with: last.range(at: 2))
        let pctStr = ns.substring(with: last.range(at: 3))
        guard let nav = Double(navStr), nav > 0, let pct = Double(pctStr) else { return nil }
        var q = FundQuote()
        q.nav = nav
        q.pct = pct
        if let ms = Double(ts) {
            let d = Date(timeIntervalSince1970: ms / 1000)
            let fmt = DateFormatter()
            fmt.dateFormat = "MM-dd"
            q.time = fmt.string(from: d)
        }
        return q
    }
}

struct HoldingRow {
    let code: String
    let name: String
    let pct: Double
    var chg: Double? = nil
}
struct HoldingsResult {
    var ok = false
    var period = ""
    var deadline = ""
    var rows: [HoldingRow] = []
}

/// 真实重仓股：原生带 Referer 抓天天基金 F10 jjcc（网页 JSONP 会被 404），
/// 再抓 push2 批量行情合并当日涨跌幅。全程主线程回调。
final class HoldingsService {
    static let shared = HoldingsService()
    private init() {}

    func fetch(code: String, completion: @escaping (HoldingsResult) -> Void) {
        guard let url = URL(string:
            "https://fundf10.eastmoney.com/FundArchivesDatas.aspx?type=jjcc&code=\(code)&topline=10&year=&month=") else {
            DispatchQueue.main.async { completion(HoldingsResult()) }
            return
        }
        var req = URLRequest(url: url, timeoutInterval: 15)
        req.setValue("https://fundf10.eastmoney.com/ccmx_\(code).html", forHTTPHeaderField: "Referer")
        req.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 Version/17.0 Mobile/15E148 Safari/604.1",
                     forHTTPHeaderField: "User-Agent")
        URLSession.shared.dataTask(with: req) { [weak self] data, _, error in
            guard error == nil, let data = data,
                  let raw = String(data: data, encoding: .utf8),
                  let result = Self.parseHoldings(raw), !result.rows.isEmpty else {
                DispatchQueue.main.async { completion(HoldingsResult()) }
                return
            }
            var r = HoldingsResult()
            r.ok = true
            r.period = result.period
            r.deadline = result.deadline
            r.rows = result.rows
            self?.fetchQuotes(rows: r.rows) { merged in
                r.rows = merged
                DispatchQueue.main.async { completion(r) }
            }
        }.resume()
    }

    private func fetchQuotes(rows: [HoldingRow], completion: @escaping ([HoldingRow]) -> Void) {
        let secids = rows.map { row -> String in
            let prefix = (row.code.hasPrefix("6") || row.code.hasPrefix("9")) ? "1" : "0"
            return "\(prefix).\(row.code)"
        }.joined(separator: ",")
        guard !secids.isEmpty,
              let url = URL(string: "https://push2.eastmoney.com/api/qt/ulist.np/get?secids=\(secids)&fields=f12,f3") else {
            completion(rows)
            return
        }
        var req = URLRequest(url: url, timeoutInterval: 8)
        req.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 Version/17.0 Mobile/15E148 Safari/604.1",
                     forHTTPHeaderField: "User-Agent")
        URLSession.shared.dataTask(with: req) { data, _, _ in
            var merged = rows
            if let data = data,
               let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
               let diff = obj["data"] as? [String: Any],
               let list = diff["diff"] as? [[String: Any]] {
                var chgMap: [String: Double] = [:]
                for item in list {
                    guard let code = item["f12"] as? String else { continue }
                    if let n = item["f3"] as? NSNumber { chgMap[code] = n.doubleValue / 100.0 }
                }
                if !chgMap.isEmpty {
                    merged = rows.map { r in
                        var rr = r
                        rr.chg = chgMap[r.code]
                        return rr
                    }
                }
            }
            completion(merged)
        }.resume()
    }

    // MARK: 解析 jjcc content
    private static func parseHoldings(_ raw: String) -> (period: String, deadline: String, rows: [HoldingRow])? {
        guard let content = extractContent(raw) else { return nil }
        let period = firstCapture(content, #"(\d{4}年\d季度股票投资明细)"#) ?? ""
        let deadline = firstCapture(content, #"截止至：<font[^>]*>(\d{4}-\d{2}-\d{2})"#) ?? ""
        var rows: [HoldingRow] = []
        var seen = Set<String>()
        for tr in captures(content, #"<tr[^>]*>(.*?)</tr>"#) {
            let tds = captures(tr, #"<td[^>]*>(.*?)</td>"#)
            guard tds.count >= 5,
                  let code = firstCapture(tds[1], #">(\d{6})<"#) else { continue }
            let name = stripTags(tds[2]).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty,
                  let pctStr = firstCapture(tds[4], #"([\d.]+)%"#),
                  let pct = Double(pctStr) else { continue }
            if seen.contains(code) { continue }
            seen.insert(code)
            rows.append(HoldingRow(code: code, name: name, pct: pct))
            if rows.count >= 10 { break }
        }
        return (period, deadline, rows)
    }

    private static func extractContent(_ raw: String) -> String? {
        let key = "content:\""
        guard let r = raw.range(of: key) else { return nil }
        let start = raw.index(r.lowerBound, offsetBy: key.count)
        var i = start
        var escaped = false
        while i < raw.endIndex {
            let ch = raw[i]
            if escaped { escaped = false }
            else if ch == "\\" { escaped = true }
            else if ch == "\"" {
                let lit = String(raw[start..<i])
                let wrapped = "\"" + lit + "\""
                if let data = wrapped.data(using: .utf8),
                   let obj = try? JSONSerialization.jsonObject(with: data, options: []),
                   let str = obj as? String { return str }
                return lit
            }
            i = raw.index(after: i)
        }
        return nil
    }

    private static func firstCapture(_ text: String, _ pattern: String) -> String? {
        guard let re = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]),
              let m = re.firstMatch(in: text, options: [], range: NSRange(text.startIndex..., in: text)),
              m.numberOfRanges > 1,
              let r = Range(m.range(at: 1), in: text) else { return nil }
        return String(text[r])
    }

    private static func captures(_ text: String, _ pattern: String) -> [String] {
        guard let re = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]) else { return [] }
        return re.matches(in: text, options: [], range: NSRange(text.startIndex..., in: text)).compactMap { m in
            guard m.numberOfRanges > 1, let r = Range(m.range(at: 1), in: text) else { return nil }
            return String(text[r])
        }
    }

    private static func stripTags(_ html: String) -> String {
        var out = ""
        var inTag = false
        for ch in html {
            if ch == "<" { inTag = true; continue }
            if ch == ">" { inTag = false; continue }
            if !inTag { out.append(ch) }
        }
        return out.replacingOccurrences(of: "&nbsp;", with: " ")
                  .replacingOccurrences(of: "&amp;", with: "&")
    }
}
