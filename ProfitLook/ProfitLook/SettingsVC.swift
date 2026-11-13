import UIKit

/// 自动刷新间隔选项（秒）；0 = 关闭。设置页与选择卡片共用，避免两处文案走散。
private let kIntervalOptions: [(secs: Int, label: String)] = [
    (0, "关闭"), (30, "每 30 秒"), (60, "每 1 分钟"),
    (300, "每 5 分钟"), (900, "每 15 分钟"), (1800, "每 30 分钟"),
]

final class SettingsVC: UITableViewController {
    private let schemeSeg = UISegmentedControl(items: ["红涨绿跌", "绿涨红跌"])
    private let holdSw = UISwitch()

    init() {
        super.init(style: .insetGrouped)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private var appVersion: String {
        let v = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let b = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        return "\(v) (\(b))"
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "设置"
        navigationController?.navigationBar.prefersLargeTitles = true
        navigationItem.largeTitleDisplayMode = .always

        schemeSeg.selectedSegmentIndex = FundStore.shared.scheme == "cn" ? 0 : 1
        schemeSeg.addTarget(self, action: #selector(schemeChanged), for: .valueChanged)
        schemeSeg.accessibilityLabel = "涨跌配色"
        holdSw.isOn = FundStore.shared.showHold
        holdSw.addTarget(self, action: #selector(holdChanged), for: .valueChanged)
        holdSw.accessibilityLabel = "显示持有金额"

        NotificationCenter.default.addObserver(self, selector: #selector(prefsChanged),
                                               name: .plPrefsChanged, object: nil)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        schemeSeg.selectedSegmentIndex = FundStore.shared.scheme == "cn" ? 0 : 1
        holdSw.isOn = FundStore.shared.showHold
        tableView.reloadData()
    }

    @objc private func schemeChanged() {
        FundStore.shared.setScheme(schemeSeg.selectedSegmentIndex == 0 ? "cn" : "us")
        Haptics.tap()
        NotificationCenter.default.post(name: .plPrefsChanged, object: nil)
        tableView.reloadData()
    }

    @objc private func holdChanged() {
        FundStore.shared.setShowHold(holdSw.isOn)
        Haptics.tap()
        NotificationCenter.default.post(name: .plPrefsChanged, object: nil)
    }

    @objc private func prefsChanged() {
        schemeSeg.selectedSegmentIndex = FundStore.shared.scheme == "cn" ? 0 : 1
        holdSw.isOn = FundStore.shared.showHold
    }

    // MARK: 数据源
    override func numberOfSections(in tableView: UITableView) -> Int { return 4 }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch section {
        case 0: return 2
        case 1: return 1
        case 2: return 1
        default: return 2
        }
    }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        switch section {
        case 0: return "显示"
        case 1: return "数据"
        case 2: return "自动刷新"
        default: return "关于"
        }
    }

    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        switch section {
        case 0:
            return "配色只影响涨跌文字与数字的颜色，不改变数值本身。"
        case 1:
            return "持有金额与市值保存在本机，不上传任何服务器。单位净值与重仓股为联网实时获取。"
        case 2:
            return "开启后，在「我的基金」页面且 App 处于前台时，按设定间隔自动获取最新净值。"
        default:
            return "盈亏一眼 · 单位净值与季报持仓来自天天基金 / 东方财富公开数据，仅供参考，不构成投资建议。"
        }
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
        cell.selectionStyle = .none
        cell.accessoryType = .none
        cell.accessoryView = nil
        cell.accessibilityTraits = .none

        switch (indexPath.section, indexPath.row) {
        case (0, 0):
            var cfg = UIListContentConfiguration.cell()
            cfg.text = "涨跌配色"
            cfg.textProperties.font = Typo.scaled(17, style: .body)
            cell.contentConfiguration = cfg
            schemeSeg.sizeToFit()
            cell.accessoryView = schemeSeg

        case (0, 1):
            var cfg = UIListContentConfiguration.cell()
            cfg.text = "显示持有金额"
            cfg.textProperties.font = Typo.scaled(17, style: .body)
            cell.contentConfiguration = cfg
            cell.accessoryView = holdSw

        case (1, 0):
            var cfg = UIListContentConfiguration.cell()
            cfg.text = "清空所有基金"
            cfg.textProperties.font = Typo.scaled(17, style: .body)
            cfg.textProperties.color = .systemRed
            cell.contentConfiguration = cfg
            cell.selectionStyle = .default
            cell.accessibilityTraits = .button

        case (2, 0):
            var cfg = UIListContentConfiguration.valueCell()
            cfg.text = "刷新间隔"
            cfg.textProperties.font = Typo.scaled(17, style: .body)
            cfg.secondaryText = intervalLabel(FundStore.shared.autoRefreshInterval)
            cfg.secondaryTextProperties.font = Typo.scaled(17, style: .body)
            cfg.secondaryTextProperties.color = TextTier.secondary.color
            cell.contentConfiguration = cfg
            cell.accessoryType = .disclosureIndicator
            cell.selectionStyle = .default
            cell.accessibilityTraits = .button

        case (3, 0):
            var cfg = UIListContentConfiguration.valueCell()
            cfg.text = "版本"
            cfg.textProperties.font = Typo.scaled(17, style: .body)
            cfg.secondaryText = appVersion
            cfg.secondaryTextProperties.font = Typo.scaled(17, style: .body, monoDigits: true)
            cfg.secondaryTextProperties.color = TextTier.secondary.color
            cell.contentConfiguration = cfg

        case (3, 1):
            var cfg = UIListContentConfiguration.subtitleCell()
            cfg.text = "数据来源"
            cfg.textProperties.font = Typo.scaled(17, style: .body)
            cfg.secondaryText = "天天基金（单位净值与日涨跌）· 天天基金 F10 / 东方财富（季报持仓与行情）"
            cfg.secondaryTextProperties.font = Typo.scaled(12, style: .caption1)
            cfg.secondaryTextProperties.color = TextTier.secondary.color
            cfg.secondaryTextProperties.numberOfLines = 0
            cell.contentConfiguration = cfg
        default:
            break
        }
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        if indexPath.section == 1 && indexPath.row == 0 {
            confirm(title: "清空所有基金？",
                    message: "共 \(FundStore.shared.funds.count) 条记录将被删除，此操作不可撤销。",
                    action: "清空") { [weak self] in
                FundStore.shared.funds = []
                FundStore.shared.saveFunds()
                NotificationCenter.default.post(name: .plFundsChanged, object: nil)
                self?.tableView.reloadData()
                Haptics.result(.warning)
            }
        } else if indexPath.section == 2 && indexPath.row == 0 {
            presentIntervalPicker()
        }
    }

    private func intervalLabel(_ secs: Int) -> String {
        return kIntervalOptions.first(where: { $0.secs == secs })?.label ?? "关闭"
    }

    /// 选择刷新间隔：底部 sheet 卡片（与添加/编辑基金同一套呈现机制），选中即保存并通知主页重新排程。
    private func presentIntervalPicker() {
        let picker = IntervalPickerVC(current: FundStore.shared.autoRefreshInterval)
        picker.onSelect = { [weak self] _ in
            self?.tableView.reloadRows(at: [IndexPath(row: 0, section: 2)], with: .automatic)
        }
        picker.modalPresentationStyle = .pageSheet
        if let sheet = picker.sheetPresentationController {
            // 先给一个占位档位；真正的贴合内容高度由 IntervalPickerVC 首次布局时接管。
            // 只留一个档位、绝不带 .large()，避免系统自动提升档位顶到状态栏。
            sheet.detents = [.medium()]
            sheet.prefersGrabberVisible = true
            sheet.prefersScrollingExpandsWhenScrolledToEdge = false
        }
        present(picker, animated: true)
    }

    /// 破坏性操作统一走系统确认表（HIG：不可撤销的操作必须二次确认）
    private func confirm(title: String, message: String, action: String, handler: @escaping () -> Void) {
        let ac = UIAlertController(title: title, message: message, preferredStyle: .actionSheet)
        ac.addAction(UIAlertAction(title: action, style: .destructive) { _ in handler() })
        ac.addAction(UIAlertAction(title: "取消", style: .cancel))
        if let pop = ac.popoverPresentationController {
            pop.sourceView = view
            pop.sourceRect = CGRect(x: view.bounds.midX, y: view.bounds.midY, width: 0, height: 0)
        }
        present(ac, animated: true)
    }
}

// MARK: - 刷新间隔选择：底部 sheet 卡片
/// 与 AddFundVC / EditFundVC 同一套呈现机制：系统 pageSheet + 单一 custom detent，
/// 高度贴合内容、不带 .large()，从底部升起，不顶状态栏、不留大片空白。
final class IntervalPickerVC: UIViewController {
    /// 选中后回调，供设置页刷新「刷新间隔」那一行的副标题。
    var onSelect: ((Int) -> Void)?

    private let current: Int
    private let stack = UIStackView()
    private var checks: [(secs: Int, label: UILabel)] = []
    private var didFit = false
    private var contentHeight: CGFloat = 0
    private let fitID = UISheetPresentationController.Detent.Identifier("intervalFit")

    init(current: Int) {
        self.current = current
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.glassBackground()

        let title = UILabel()
        title.text = "刷新间隔"
        title.style(Typo.scaled(17, .semibold, style: .headline), .label)
        title.textAlignment = .center

        let subtitle = UILabel()
        subtitle.text = "App 在前台时按此间隔自动获取最新净值"
        subtitle.style(Typo.scaled(13, style: .footnote), TextTier.secondary.color)
        subtitle.textAlignment = .center
        subtitle.numberOfLines = 0

        // 选项容器：insetGrouped 风格圆角卡片 + 发丝分隔线
        let card = UIView()
        card.cardStyle(AppCardRadius, color: .secondarySystemGroupedBackground)
        // 普通 UIView 没有 intrinsicContentSize，垂直 stack 会把它压成 0（上一版「卡片太短」的老毛病）。
        // 行数、行高、发丝线厚度都固定，直接给容器一个明确高度最稳。
        let lineH = 1 / UIScreen.main.scale
        let cardH = CGFloat(kIntervalOptions.count) * 54
            + CGFloat(kIntervalOptions.count - 1) * lineH
        let list = UIStackView()
        list.axis = .vertical
        list.spacing = 0
        list.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(list)
        NSLayoutConstraint.activate([
            list.topAnchor.constraint(equalTo: card.topAnchor),
            list.leadingAnchor.constraint(equalTo: card.leadingAnchor),
            list.trailingAnchor.constraint(equalTo: card.trailingAnchor),
            list.bottomAnchor.constraint(equalTo: card.bottomAnchor),
            card.heightAnchor.constraint(equalToConstant: cardH),
        ])
        for (i, opt) in kIntervalOptions.enumerated() {
            if i > 0 { list.addArrangedSubview(IntervalPickerVC.hairline()) }
            let row = OptionRow(title: opt.label, selected: opt.secs == current)
            row.tag = opt.secs
            row.addTarget(self, action: #selector(pick(_:)), for: .touchUpInside)
            checks.append((opt.secs, row.check))
            list.addArrangedSubview(row)
        }

        // 独立「取消」卡片
        let cancel = UIButton(type: .system)
        cancel.setTitle("取消", for: .normal)
        cancel.titleLabel?.font = Typo.scaled(17, .semibold, style: .body)
        cancel.setTitleColor(.label, for: .normal)
        cancel.backgroundColor = .secondarySystemGroupedBackground
        cancel.layer.cornerRadius = AppCardRadius
        cancel.layer.cornerCurve = .continuous
        cancel.heightAnchor.constraint(equalToConstant: 54).isActive = true
        cancel.addTarget(self, action: #selector(dismissSelf), for: .touchUpInside)

        stack.axis = .vertical
        stack.spacing = 16
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.addArrangedSubview(title)
        stack.addArrangedSubview(subtitle)
        stack.addArrangedSubview(card)
        stack.addArrangedSubview(cancel)
        stack.setCustomSpacing(6, after: title)
        stack.setCustomSpacing(20, after: subtitle)
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 20),
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
        ])
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        // 本 VC 直接被 present，sheet 属于自己；仍兼容将来被 nav 包装的情况。
        guard let sheet = navigationController?.sheetPresentationController ?? sheetPresentationController else { return }
        sheet.prefersGrabberVisible = true
        sheet.prefersScrollingExpandsWhenScrolledToEdge = false
        guard #available(iOS 16.0, *) else {
            sheet.detents = [.medium()]
            return
        }
        let h = stack.frame.maxY + 24 + view.safeAreaInsets.bottom
        if !didFit {
            didFit = true
            contentHeight = h
            // 只放一个自定义档位，绝不带 .large()：否则系统会自动把 sheet 提升到最大档。
            sheet.detents = [.custom(identifier: fitID) { [weak self] ctx in
                max(200, min(self?.contentHeight ?? 0, ctx.maximumDetentValue))
            }]
            sheet.selectedDetentIdentifier = fitID
        } else if abs(h - contentHeight) > 24 {
            contentHeight = h
            sheet.animateChanges { sheet.invalidateDetents() }
        }
    }

    @objc private func pick(_ sender: UIButton) {
        let secs = sender.tag
        FundStore.shared.autoRefreshInterval = secs
        Haptics.tap()
        for item in checks { item.label.isHidden = (item.secs != secs) }
        onSelect?(secs)
        NotificationCenter.default.post(name: .plPrefsChanged, object: nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            self?.dismiss(animated: true)
        }
    }

    @objc private func dismissSelf() { dismiss(animated: true) }

    /// 左侧缩进 16pt 的发丝分隔线（与设置页分组表格一致）
    private static func hairline() -> UIView {
        let holder = UIView()
        holder.translatesAutoresizingMaskIntoConstraints = false
        let line = UIView()
        line.backgroundColor = .separator
        line.alpha = 0.45
        line.translatesAutoresizingMaskIntoConstraints = false
        holder.addSubview(line)
        NSLayoutConstraint.activate([
            line.leadingAnchor.constraint(equalTo: holder.leadingAnchor, constant: 16),
            line.trailingAnchor.constraint(equalTo: holder.trailingAnchor),
            line.topAnchor.constraint(equalTo: holder.topAnchor),
            line.bottomAnchor.constraint(equalTo: holder.bottomAnchor),
            holder.heightAnchor.constraint(equalToConstant: 1 / UIScreen.main.scale),
        ])
        return holder
    }
}

/// 单个选项行：左标题、右蓝色 ✓，点按时整行淡灰高亮。
private final class OptionRow: UIButton {
    let check = UILabel()
    private let highlight = UIView()

    init(title: String, selected: Bool) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        heightAnchor.constraint(equalToConstant: 54).isActive = true
        // 用 target-action 接管高亮，不 override UIControl.isHighlighted，避免任何 Swift/UIKit 版本差异
        addTarget(self, action: #selector(highlightOn), for: [.touchDown, .touchDragEnter])
        addTarget(self, action: #selector(highlightOff),
                  for: [.touchUpInside, .touchUpOutside, .touchDragExit, .touchCancel])

        highlight.backgroundColor = UIColor.label.withAlphaComponent(0.07)
        highlight.alpha = 0
        highlight.isUserInteractionEnabled = false
        highlight.translatesAutoresizingMaskIntoConstraints = false
        addSubview(highlight)

        let lb = UILabel()
        lb.text = title
        lb.style(Typo.scaled(17, style: .body), .label)
        lb.translatesAutoresizingMaskIntoConstraints = false
        addSubview(lb)

        check.text = "✓"
        check.style(Typo.scaled(18, .semibold, style: .body), .systemBlue)
        check.isHidden = !selected
        check.translatesAutoresizingMaskIntoConstraints = false
        addSubview(check)

        NSLayoutConstraint.activate([
            highlight.topAnchor.constraint(equalTo: topAnchor),
            highlight.leadingAnchor.constraint(equalTo: leadingAnchor),
            highlight.trailingAnchor.constraint(equalTo: trailingAnchor),
            highlight.bottomAnchor.constraint(equalTo: bottomAnchor),
            lb.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            lb.centerYAnchor.constraint(equalTo: centerYAnchor),
            check.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            check.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    @objc private func highlightOn() { highlight.alpha = 1 }
    @objc private func highlightOff() { highlight.alpha = 0 }
}
