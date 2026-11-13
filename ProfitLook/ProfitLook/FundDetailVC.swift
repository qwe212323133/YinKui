import UIKit

final class FundDetailVC: UITableViewController {
    private let index: Int
    private var result = HoldingsResult()
    private var loading = true
    private let cellID = "HoldingCell"
    private let statusID = "StatusCell"
    private var head: FundHeadView?

    init(index: Int) {
        self.index = index
        super.init(style: .insetGrouped)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private var fund: Fund? {
        index < FundStore.shared.funds.count ? FundStore.shared.funds[index] : nil
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "基金详情"
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .done, target: self, action: #selector(close))
        navigationItem.rightBarButtonItem?.accessibilityLabel = "关闭"

        tableView.register(HoldingCell.self, forCellReuseIdentifier: cellID)
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: statusID)
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 52

        if let f = fund {
            let h = FundHeadView(fund: f, index: index)
            head = h
            tableView.tableHeaderView = h
        }
        load()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        sizeHeaderToFit()
    }

    private func sizeHeaderToFit() {
        guard let head = head, head.superview != nil else { return }
        let w = tableView.bounds.width
        guard w > 0 else { return }
        head.frame = CGRect(x: 0, y: 0, width: w, height: head.frame.height)
        let h = head.systemLayoutSizeFitting(
            CGSize(width: w, height: UIView.layoutFittingCompressedSize.height),
            withHorizontalFittingPriority: .required,
            verticalFittingPriority: .fittingSizeLevel).height
        if abs(head.frame.height - h) > 0.5 {
            head.frame = CGRect(x: 0, y: 0, width: w, height: h)
            tableView.tableHeaderView = head
        }
    }

    @objc private func close() { dismiss(animated: true) }

    private func load() {
        guard let f = fund else { return }
        loading = true
        result = HoldingsResult()
        tableView.reloadData()
        HoldingsService.shared.fetch(code: f.code) { [weak self] r in
            guard let self = self else { return }
            self.result = r
            self.loading = false
            self.tableView.reloadData()
        }
    }

    @objc private func retry() { load() }

    // MARK: 数据源
    private var hasRows: Bool { !loading && result.ok && !result.rows.isEmpty }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return hasRows ? result.rows.count : 1
    }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        guard hasRows else { return "重仓持股" }
        let period = result.period.isEmpty ? "重仓持股" : result.period
        return result.deadline.isEmpty ? period : "\(period) · 截止 \(result.deadline)"
    }

    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        guard hasRows else { return nil }
        return "数据来源：天天基金 F10 季报持仓 · 东方财富当日行情，按季报披露更新，仅供参考。"
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard hasRows else { return statusCell() }
        let c = tableView.dequeueReusableCell(withIdentifier: cellID, for: indexPath) as! HoldingCell
        c.configure(result.rows[indexPath.row])
        return c
    }

    /// 加载中 / 失败：标准 subtitleCell + 右侧活动指示器或「重试」
    private func statusCell() -> UITableViewCell {
        let c = tableView.dequeueReusableCell(withIdentifier: statusID) ?? UITableViewCell(style: .subtitle, reuseIdentifier: statusID)
        c.selectionStyle = .none
        c.accessoryView = nil
        var cfg = UIListContentConfiguration.subtitleCell()
        cfg.textProperties.font = Typo.scaled(15, .medium, style: .subheadline)
        cfg.secondaryTextProperties.font = Typo.scaled(12, style: .caption1)
        cfg.secondaryTextProperties.color = TextTier.secondary.color
        cfg.secondaryTextProperties.numberOfLines = 0

        if loading {
            cfg.text = "正在获取持仓…"
            cfg.textProperties.color = TextTier.secondary.color
            cfg.secondaryText = "实时抓取该基金最新披露的十大重仓股"
            let sp = UIActivityIndicatorView(style: .medium)
            sp.startAnimating()
            c.accessoryView = sp
        } else {
            cfg.text = "暂无持仓数据"
            cfg.secondaryText = "该基金可能未披露股票持仓，或网络暂时不可用"
            let btn = UIButton(type: .system)
            btn.setTitle("重试", for: .normal)
            btn.titleLabel?.font = Typo.scaled(15, .medium, style: .subheadline)
            btn.addTarget(self, action: #selector(retry), for: .touchUpInside)
            c.accessoryView = btn
        }
        c.contentConfiguration = cfg
        return c
    }
}

// MARK: - 详情页头卡
final class FundHeadView: UIView {
    init(fund: Fund, index: Int) {
        super.init(frame: .zero)
        backgroundColor = .clear

        let card = UIView()
        card.cardStyle(AppCardRadius, color: .secondarySystemGroupedBackground)
        card.translatesAutoresizingMaskIntoConstraints = false
        addSubview(card)

        let face = UILabel()
        face.text = String(fund.name.prefix(1))
        face.textAlignment = .center
        face.style(Typo.scaled(19, .semibold, style: .headline), .white)
        face.backgroundColor = FundStore.shared.color(at: index)
        face.cardStyle(10)
        face.translatesAutoresizingMaskIntoConstraints = false
        face.setContentHuggingPriority(.required, for: .horizontal)
        face.setContentCompressionResistancePriority(.required, for: .horizontal)

        let nm = UILabel()
        nm.text = fund.name
        nm.style(Typo.scaled(18, .semibold, style: .headline), .label)
        nm.numberOfLines = 2

        let code = UILabel()
        code.text = fund.code
        code.style(Typo.scaled(12, style: .caption1, monoDigits: true), TextTier.secondary.color)

        let titleStack = UIStackView(arrangedSubviews: [nm, code])
        titleStack.axis = .vertical
        titleStack.spacing = 2

        let pct = UILabel()
        pct.text = Fmt.pct(fund.estPct)
        pct.style(Typo.scaled(22, .semibold, style: .title3, monoDigits: true), Theme.color(for: fund.estPct))
        pct.textAlignment = .right
        pct.setContentHuggingPriority(.required, for: .horizontal)
        pct.setContentCompressionResistancePriority(.required, for: .horizontal)

        let top = UIStackView(arrangedSubviews: [face, titleStack, pct])
        top.axis = .horizontal
        top.spacing = 12
        top.alignment = .center
        top.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(top)
        NSLayoutConstraint.activate([
            face.widthAnchor.constraint(equalToConstant: 44),
            face.heightAnchor.constraint(equalToConstant: 44),
        ])

        let timeText = fund.time.isEmpty ? "--:--" : fund.time
        let sub = UILabel()
        sub.text = "单位净值 " + Fmt.nav(fund.estNav) + " · 截至 " + timeText
        sub.style(Typo.scaled(12, style: .caption1, monoDigits: true), TextTier.secondary.color)
        sub.numberOfLines = 1
        sub.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(sub)

        NSLayoutConstraint.activate([
            card.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            card.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            card.topAnchor.constraint(equalTo: topAnchor, constant: 4),
            card.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -10),

            top.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 16),
            top.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -16),
            top.topAnchor.constraint(equalTo: card.topAnchor, constant: 14),

            sub.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 16),
            sub.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -16),
            sub.topAnchor.constraint(equalTo: top.bottomAnchor, constant: 10),
            sub.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -14),
        ])

        isAccessibilityElement = true
        accessibilityLabel = "\(fund.name)，代码 \(fund.code)，单位净值 \(Fmt.nav(fund.estNav))，涨跌 \(Fmt.pct(fund.estPct))"
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}

// MARK: - 重仓股行
final class HoldingCell: UITableViewCell {
    private let name = UILabel()
    private let code = UILabel()
    private let chg = UILabel()
    private let pct = UILabel()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        selectionStyle = .none

        name.style(Typo.scaled(15, .medium, style: .subheadline), .label)
        name.numberOfLines = 1
        code.style(Typo.scaled(12, style: .caption1, monoDigits: true), TextTier.secondary.color)

        chg.style(Typo.scaled(15, .medium, style: .subheadline, monoDigits: true), .label)
        chg.textAlignment = .right
        pct.style(Typo.scaled(12, style: .caption1, monoDigits: true), TextTier.secondary.color)
        pct.textAlignment = .right

        let left = UIStackView(arrangedSubviews: [name, code])
        left.axis = .vertical
        left.spacing = 1
        left.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let right = UIStackView(arrangedSubviews: [chg, pct])
        right.axis = .vertical
        right.spacing = 1
        right.alignment = .trailing
        right.setContentHuggingPriority(.required, for: .horizontal)
        right.setContentCompressionResistancePriority(.required, for: .horizontal)

        let row = UIStackView(arrangedSubviews: [left, right])
        row.axis = .horizontal
        row.spacing = 12
        row.alignment = .center
        row.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(row)
        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            row.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            row.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 9),
            row.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -9),
        ])
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(_ r: HoldingRow) {
        name.text = r.name
        code.text = r.code
        pct.text = "占净值 " + String(format: "%.2f", r.pct) + "%"
        if let c = r.chg {
            chg.text = Fmt.pct(c)
            chg.textColor = Theme.color(for: c)
            chg.isHidden = false
        } else {
            chg.text = nil
            chg.isHidden = true
        }
        isAccessibilityElement = true
        accessibilityLabel = r.name + "，代码 " + r.code
            + "，占净值 " + String(format: "%.2f", r.pct) + "%"
            + (r.chg.map { "，当日涨跌 \(Fmt.pct($0))" } ?? "")
    }
}
