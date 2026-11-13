import UIKit

final class FundListVC: UITableViewController {
    private let cellID = "FundCell"
    private let hero = HeroHeader()
    private let empty = EmptyStateView()
    private let compactBar = CompactSummaryBar()   // A：滚动收纳后的吸顶小计
    private var compactShown = false
    private var offsetObservation: NSKeyValueObservation?
    private var listMargin: CGFloat = 20          // 与基金列表容器实测边距共用
    private let compactHeight: CGFloat = 42
    private let compactTopGap: CGFloat = 8        // 与导航栏之间的呼吸，不贴死
    private var refreshToken = 0
    private var autoTimer: Timer?

    init() { super.init(style: .insetGrouped) }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "我的基金"
        navigationController?.navigationBar.prefersLargeTitles = true
        navigationItem.largeTitleDisplayMode = .always
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .add, target: self, action: #selector(addFund))
        navigationItem.rightBarButtonItem?.accessibilityLabel = "添加基金"

        tableView.register(FundCell.self, forCellReuseIdentifier: cellID)
        tableView.backgroundColor = .systemGroupedBackground
        // insetGrouped：整组基金装进一张系统圆角容器（与设置页完全同款），行间发丝线分隔
        tableView.separatorStyle = .singleLine
        // 发丝线对齐行文字起点：face 38 + 间距 12 + 内容边距 16；右侧同样留 16
        tableView.separatorInset = UIEdgeInsets(top: 0, left: 66, bottom: 0, right: 16)
        // 去掉固定行高，交给 Auto Layout 适配「文字大小」设置
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 64
        tableView.sectionHeaderHeight = 0
        tableView.sectionFooterHeight = 0
        tableView.tableHeaderView = hero
        tableView.backgroundView = empty

        // A：吸顶小计作为 tableView 子视图，frame 处于内容坐标系，随 contentOffset 钉在可视区顶部。
        // 不侵入 navigationController.view，生命周期随本页；抬高 zPosition 避免被 cell 盖住。
        tableView.addSubview(compactBar)
        compactBar.layer.zPosition = 10
        compactBar.alpha = 0
        compactBar.isHidden = true
        // KVO 跟随滚动：不依赖 UITableViewController 是否实现了 scrollViewDidScroll，
        // 也避开 override 可选协议方法的编译期不确定性。
        offsetObservation = tableView.observe(\.contentOffset, options: [.new]) { [weak self] _, _ in
            self?.syncCompactPosition()
        }

        let rc = UIRefreshControl()
        rc.tintColor = TextTier.secondary.color
        rc.addTarget(self, action: #selector(pullRefresh), for: .valueChanged)
        refreshControl = rc

        NotificationCenter.default.addObserver(self, selector: #selector(reload),
                                               name: .plFundsChanged, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(reload),
                                               name: .plPrefsChanged, object: nil)
        // 自动刷新：间隔变化或回到前台时重新排程
        NotificationCenter.default.addObserver(self, selector: #selector(scheduleAutoRefresh),
                                               name: .plPrefsChanged, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(appBecameActive),
                                               name: UIApplication.didBecomeActiveNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(appWillResign),
                                               name: UIApplication.willResignActiveNotification, object: nil)
        reload()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        syncHeroAlignment()
        sizeHeaderToFit()
        layoutCompactBar()
    }

    /// 头卡与基金容器对齐：边距取行 frame 实测值；圆角走全 App 统一的 `AppCardRadius`(14)，
    /// 与详情卡/设置卡/列表 box 一致。不复用系统列表圆角——液态玻璃下它返回 0 会让头卡变直角。
    private func syncHeroAlignment() {
        let margins = tableView.visibleCells.map(\.frame.minX).filter { $0 > 1 }
        let margin = margins.min() ?? 20
        listMargin = margin
        hero.alignToContainer(margin: margin, cornerRadius: AppCardRadius)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        scheduleAutoRefresh()
        // 从详情页返回时滚动位置保留，同步一次吸顶状态
        syncCompactPosition()
    }
    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        stopAutoRefresh()
    }

    /// 表头按内容自适应高度（Dynamic Type 放大后不会被裁切）
    private func sizeHeaderToFit() {
        guard hero.superview != nil else { return }
        let w = tableView.bounds.width
        guard w > 0 else { return }
        hero.frame = CGRect(x: 0, y: 0, width: w, height: hero.frame.height)
        let h = hero.systemLayoutSizeFitting(
            CGSize(width: w, height: UIView.layoutFittingCompressedSize.height),
            withHorizontalFittingPriority: .required,
            verticalFittingPriority: .fittingSizeLevel).height
        if abs(hero.frame.height - h) > 0.5 {
            hero.frame = CGRect(x: 0, y: 0, width: w, height: h)
            tableView.tableHeaderView = hero
        }
    }

    // MARK: A：滚动收纳为吸顶小计
    /// 小计条不再是横贯全宽的硬横条：与基金列表容器同边距、同圆角（AppCardRadius），
    /// 与导航栏之间留 8pt 呼吸，做成一个克制的悬浮小卡，和页面里所有卡片同一套语言。
    private func layoutCompactBar() {
        let w = tableView.bounds.width
        guard w > 0 else { return }
        let y = tableView.contentOffset.y + tableView.adjustedContentInset.top
        compactBar.frame = CGRect(x: listMargin,
                                  y: y + compactTopGap,
                                  width: max(0, w - listMargin * 2),
                                  height: compactHeight)
    }

    private func compactThreshold() -> CGFloat {
        return max(56, hero.frame.height - 18)
    }

    private func syncCompactPosition() {
        guard tableView.bounds.width > 0 else { return }
        layoutCompactBar()
        guard !FundStore.shared.funds.isEmpty else { setCompactShown(false); return }

        // 关键守卫：内容不够长时绝不收纳。否则头卡与全部基金行被一起推上可视区外，
        // 只剩一条小计条挂在整屏空白上（真机反馈的「回收窗口好丑」）。
        // 条件：头卡滚出后，下方仍至少有 ~0.8 屏的列表内容，且此刻真的有行可见。
        let visibleH = tableView.bounds.height
            - tableView.adjustedContentInset.top
            - tableView.adjustedContentInset.bottom
        let contentBelowHero = tableView.contentSize.height - hero.frame.height
        let hasRowsBelow = !(tableView.indexPathsForVisibleRows ?? []).isEmpty
        guard visibleH > 0,
              contentBelowHero >= visibleH * 0.8,
              hasRowsBelow else {
            setCompactShown(false)
            return
        }

        let y = tableView.contentOffset.y + tableView.adjustedContentInset.top
        // 滞回 ±28pt：临界区不来回闪；只在状态真正变化时触发一次显隐动画
        let t = compactThreshold()
        let show = compactShown ? (y > t - 28) : (y > t + 28)
        setCompactShown(show)
    }

    private func setCompactShown(_ show: Bool) {
        guard show != compactShown else { return }
        compactShown = show
        if show { compactBar.update() }
        if UIAccessibility.isReduceMotionEnabled {
            compactBar.isHidden = !show
            compactBar.alpha = show ? 1 : 0
        } else if show {
            compactBar.isHidden = false
            UIView.animate(withDuration: 0.18, delay: 0,
                           options: [.curveEaseOut, .allowUserInteraction]) {
                self.compactBar.alpha = 1
            }
        } else {
            UIView.animate(withDuration: 0.16, delay: 0,
                           options: [.curveEaseIn, .allowUserInteraction]) {
                self.compactBar.alpha = 0
            } completion: { _ in
                if !self.compactShown { self.compactBar.isHidden = true }
            }
        }
    }

    @objc private func reload() {
        let isEmpty = FundStore.shared.funds.isEmpty
        hero.update()
        compactBar.update()
        tableView.tableHeaderView = isEmpty ? nil : hero
        empty.isHidden = !isEmpty
        if isEmpty { setCompactShown(false) }
        tableView.reloadData()
        sizeHeaderToFit()
        // contentSize 变了，重新判定该不该收纳（否则删到只剩 1 只时小计条会挂在空白上）。
        // 先强制布局一次，确保 contentSize / visibleRows 是最新值再判。
        tableView.layoutIfNeeded()
        syncCompactPosition()
    }

    // MARK: 数据源
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return FundStore.shared.funds.count
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let c = tableView.dequeueReusableCell(withIdentifier: cellID, for: indexPath) as! FundCell
        c.configure(FundStore.shared.funds[indexPath.row], index: indexPath.row)
        return c
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard indexPath.row < FundStore.shared.funds.count else { return }
        Haptics.tap()
        let detail = FundDetailVC(index: indexPath.row)
        let nav = UINavigationController(rootViewController: detail)
        nav.modalPresentationStyle = .pageSheet
        if let sheet = nav.sheetPresentationController {
            sheet.detents = [.large()]
            sheet.prefersGrabberVisible = true
            sheet.prefersScrollingExpandsWhenScrolledToEdge = true
        }
        present(nav, animated: true)
    }

    // MARK: 侧滑编辑 / 删除（HIG：破坏性操作单独成色并带图标）
    // 删除钮背景与页面底色同色（缝隙隐形），破坏性语义靠红色垃圾桶图标。
    override func tableView(_ tableView: UITableView,
                            trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath) -> UISwipeActionsConfiguration? {
        guard indexPath.row < FundStore.shared.funds.count else { return nil }
        let delete = UIContextualAction(style: .destructive, title: "删除") { [weak self] _, _, done in
            self?.deleteFund(indexPath.row)
            done(true)
        }
        delete.image = UIImage(systemName: "trash")?
            .withTintColor(.systemRed, renderingMode: .alwaysOriginal)
        // iOS 26 挤压式侧滑下，action 的红色层与行背景间会露出 1pt 级缝隙（红线复发）。
        // 背景与页面底色同色：任何缝隙透出即隐形；破坏性语义由红色垃圾桶图标表达。
        delete.backgroundColor = .systemGroupedBackground

        let edit = UIContextualAction(style: .normal, title: "编辑") { [weak self] _, _, done in
            self?.openEdit(indexPath.row)
            done(true)
        }
        edit.image = UIImage(systemName: "pencil")

        let cfg = UISwipeActionsConfiguration(actions: [delete, edit])
        cfg.performsFirstActionWithFullSwipe = false
        return cfg
    }

    private func deleteFund(_ i: Int) {
        guard i < FundStore.shared.funds.count else { return }
        Haptics.tap(.medium)
        FundStore.shared.funds.remove(at: i)
        FundStore.shared.saveFunds()
        hero.update()
        if FundStore.shared.funds.isEmpty {
            tableView.reloadData()
            tableView.tableHeaderView = nil
            empty.isHidden = false
            setCompactShown(false)
        } else {
            tableView.deleteRows(at: [IndexPath(row: i, section: 0)], with: .automatic)
        }
    }

    private func openEdit(_ i: Int) {
        let vc = EditFundVC(index: i)
        let nav = UINavigationController(rootViewController: vc)
        nav.modalPresentationStyle = .pageSheet
        if let sheet = nav.sheetPresentationController {
            // 只给一个占位档位，绝不带 .large()：否则键盘弹出时系统会自动把 sheet
            // 提升到最大档，卡片顶到状态栏并留下大片空白。真正的高度由 VC 内自转。
            sheet.detents = [.medium()]
            sheet.prefersGrabberVisible = true
            sheet.prefersScrollingExpandsWhenScrolledToEdge = false
        }
        present(nav, animated: true)
    }

    @objc private func addFund() {
        Haptics.tap()
        let vc = AddFundVC()
        let nav = UINavigationController(rootViewController: vc)
        nav.modalPresentationStyle = .pageSheet
        if let sheet = nav.sheetPresentationController {
            // 只给一个占位档位，绝不带 .large()：否则键盘弹出时系统会自动把 sheet
            // 提升到最大档，卡片顶到状态栏并留下大片空白。真正的高度由 VC 内自转。
            sheet.detents = [.medium()]
            sheet.prefersGrabberVisible = true
            sheet.prefersScrollingExpandsWhenScrolledToEdge = false
        }
        present(nav, animated: true)
    }

    // MARK: 下拉刷新：拉取真实单位净值与日涨跌
    @objc private func pullRefresh() {
        runQuoteRefresh(silent: false)
    }

    /// 拉取净值；silent=true 时不弹提示、不触感（用于自动刷新）。
    private func runQuoteRefresh(silent: Bool) {
        let snapshot = FundStore.shared.funds
        guard !snapshot.isEmpty else {
            refreshControl?.endRefreshing()
            return
        }
        refreshToken += 1
        let token = refreshToken
        QuoteService.shared.refresh(snapshot) { [weak self] okCount, map in
            guard let self = self, token == self.refreshToken else { return }
            self.refreshControl?.endRefreshing()
            guard okCount > 0 else {
                if !silent {
                    Haptics.result(.error)
                    Toast.show("净值获取失败，请检查网络后重试", in: self.view)
                }
                return
            }
            for i in FundStore.shared.funds.indices {
                guard let q = map[FundStore.shared.funds[i].code] else { continue }
                FundStore.shared.funds[i].estNav = q.nav
                FundStore.shared.funds[i].estPct = q.pct
                if !q.time.isEmpty { FundStore.shared.funds[i].time = q.time }
                // 填了份额的基金：市值 = 份额 × 最新净值，自动重算永不陈旧；没填的维持手填
                _ = FundStore.shared.funds[i].recomputeMv()
            }
            FundStore.shared.saveFunds()
            if !silent { Haptics.result(.success) }
            self.reload()
        }
    }

    // MARK: 自动刷新（间隔可在设置页调整；仅在本页可见且 App 前台时运行）
    @objc private func scheduleAutoRefresh() {
        autoTimer?.invalidate()
        autoTimer = nil
        let secs = FundStore.shared.autoRefreshInterval
        guard secs > 0 else { return }
        autoTimer = Timer.scheduledTimer(withTimeInterval: TimeInterval(secs), repeats: true) { [weak self] _ in
            self?.autoRefreshTick()
        }
    }

    private func stopAutoRefresh() {
        autoTimer?.invalidate()
        autoTimer = nil
    }

    private func autoRefreshTick() {
        guard UIApplication.shared.applicationState == .active else { return }
        runQuoteRefresh(silent: true)
    }

    @objc private func appBecameActive() {
        if viewIfLoaded?.window != nil { scheduleAutoRefresh() }
    }
    @objc private func appWillResign() {
        stopAutoRefresh()
    }
}

// MARK: - 总市值头卡（T1 精密仪表 · B 洞察句 · C 一键隐藏金额）
final class HeroHeader: UIView {
    private let card = UIView()
    private let capLabel = UILabel()          // 头部小型标签
    private let insight = UILabel()           // B：一句话洞察（主角）
    private let sub = UILabel()               // 口径 / 净值日
    private let statusDot = UIView()          // 状态点：蓝色，不占涨跌语义
    private let statusLabel = UILabel()
    private let eyeButton = UIButton(type: .system)   // C：隐私开关
    private let divider = UIView()            // 1px 硬线分区
    private let totalCaption = UILabel()      // 「总市值 / CNY」
    private let total = UILabel()             // 大等宽数字（退为佐证）
    private let todayCaption = UILabel()
    private let todayValue = UILabel()
    private let leftCol = UIStackView()
    private let rightCol = UIStackView()
    private let metricsRow = UIStackView()
    private let segBox = UIView()
    private let segPill = UIView()
    private let segToday = UIButton(type: .system)
    private let segCum = UIButton(type: .system)
    private var pillLeading: NSLayoutConstraint!
    private var cardLeading: NSLayoutConstraint!
    private var cardTrailing: NSLayoutConstraint!

    // 数字滚动动画：CADisplayLink + ease-out cubic；隐私模式 / Reduce Motion 时直降为立即赋值
    private var displayLink: CADisplayLink?
    private var animStart: CFTimeInterval = 0
    private var fromTotal: Double = 0, toTotal: Double = 0
    private var fromProfit: Double = 0, toProfit: Double = 0
    private var fromPct: Double = 0, toPct: Double = 0
    private var shownTotal: Double = 0
    private var shownProfit: Double = 0
    private var shownPct: Double = 0
    private var firstUpdate = true

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear

        // 内容层统一系统平涂：不提亮、不套玻璃、不加边缘光（HIG《Materials》）
        card.cardStyle(AppCardRadius, color: .secondarySystemGroupedBackground)
        card.translatesAutoresizingMaskIntoConstraints = false
        addSubview(card)

        capLabel.text = "持仓概览"
        capLabel.style(Typo.scaled(12, .medium, style: .caption1), TextTier.secondary.color)

        // 状态点只用蓝色表达「口径」，不占用红涨 / 绿跌的价格语义
        statusDot.backgroundColor = .systemBlue
        statusDot.layer.cornerRadius = 2.5
        statusDot.translatesAutoresizingMaskIntoConstraints = false
        statusLabel.text = "估算值"
        statusLabel.style(Typo.scaled(12, style: .caption1), TextTier.secondary.color)

        eyeButton.tintColor = TextTier.secondary.color
        eyeButton.translatesAutoresizingMaskIntoConstraints = false
        eyeButton.addTarget(self, action: #selector(togglePrivacy), for: .touchUpInside)
        eyeButton.accessibilityTraits = .button

        // 迷你分段：今日 / 累计（iOS 原生分段的小号复刻）
        segBox.backgroundColor = .tertiarySystemFill
        segBox.layer.cornerRadius = 8
        segBox.layer.cornerCurve = .continuous
        segBox.clipsToBounds = true
        segBox.translatesAutoresizingMaskIntoConstraints = false

        segPill.backgroundColor = UIColor { tc in
            tc.userInterfaceStyle == .dark ? UIColor(hex: "636366") : .white
        }
        segPill.layer.cornerRadius = 6
        segPill.layer.cornerCurve = .continuous
        segPill.isUserInteractionEnabled = false
        segPill.translatesAutoresizingMaskIntoConstraints = false
        segBox.addSubview(segPill)

        for (i, b) in [segToday, segCum].enumerated() {
            b.setTitle(i == 0 ? "今日" : "累计", for: .normal)
            b.titleLabel?.font = Typo.scaled(12, .medium, style: .caption1)
            b.translatesAutoresizingMaskIntoConstraints = false
            b.addTarget(self, action: #selector(toggleMode), for: .touchUpInside)
            segBox.addSubview(b)
        }

        // B：一句话洞察是主角，大数字退为佐证；洞察句不靠颜色编码，色弱可读
        insight.style(Typo.scaled(19, .semibold, style: .headline), .label)
        insight.numberOfLines = 2
        insight.adjustsFontSizeToFitWidth = true
        insight.minimumScaleFactor = 0.8

        sub.style(Typo.scaled(12, style: .caption1), TextTier.secondary.color)
        sub.numberOfLines = 1
        sub.adjustsFontSizeToFitWidth = true
        // 12pt × 0.92 = 11.04pt：缩放后不低于 iOS 11pt 最小字号（原 0.85 会压到 10.2pt）
        sub.minimumScaleFactor = 0.92

        // T1：1px 硬线定义结构边界，不用阴影、不用留白猜边界
        divider.backgroundColor = .separator
        divider.alpha = 0.5
        divider.translatesAutoresizingMaskIntoConstraints = false

        totalCaption.text = "总市值 / CNY"
        totalCaption.style(Typo.scaled(12, .medium, style: .caption1), TextTier.secondary.color)
        total.style(Typo.scaled(22, .bold, style: .title2, monoDigits: true), .label)
        total.adjustsFontSizeToFitWidth = true
        total.minimumScaleFactor = 0.6
        total.numberOfLines = 1

        todayCaption.style(Typo.scaled(12, .medium, style: .caption1), TextTier.secondary.color)
        todayValue.style(Typo.scaled(15, .semibold, style: .subheadline, monoDigits: true), .label)
        todayValue.numberOfLines = 1
        todayValue.adjustsFontSizeToFitWidth = true
        todayValue.minimumScaleFactor = 0.75

        leftCol.axis = .vertical
        leftCol.spacing = 3
        leftCol.addArrangedSubview(totalCaption)
        leftCol.addArrangedSubview(total)
        rightCol.axis = .vertical
        rightCol.spacing = 3
        rightCol.addArrangedSubview(todayCaption)
        rightCol.addArrangedSubview(todayValue)
        metricsRow.axis = .horizontal
        metricsRow.distribution = .fillEqually
        metricsRow.alignment = .top
        metricsRow.spacing = 12
        metricsRow.addArrangedSubview(leftCol)
        metricsRow.addArrangedSubview(rightCol)

        let spacer = UIView()
        let headRow = UIStackView(arrangedSubviews: [capLabel, spacer, segBox, eyeButton])
        headRow.axis = .horizontal
        headRow.alignment = .center
        headRow.spacing = 8

        let statusStack = UIStackView(arrangedSubviews: [statusDot, statusLabel])
        statusStack.axis = .horizontal
        statusStack.alignment = .center
        statusStack.spacing = 4
        statusStack.setContentHuggingPriority(.required, for: .horizontal)
        statusStack.setContentCompressionResistancePriority(.required, for: .horizontal)

        let spacer2 = UIView()
        let contextRow = UIStackView(arrangedSubviews: [sub, spacer2, statusStack])
        contextRow.axis = .horizontal
        contextRow.alignment = .center
        contextRow.spacing = 8

        let stack = UIStackView(arrangedSubviews: [headRow, insight, contextRow, divider, metricsRow])
        stack.axis = .vertical
        stack.spacing = 0
        stack.setCustomSpacing(10, after: headRow)
        stack.setCustomSpacing(4, after: insight)
        stack.setCustomSpacing(12, after: contextRow)
        stack.setCustomSpacing(12, after: divider)
        stack.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(stack)

        pillLeading = segPill.leadingAnchor.constraint(equalTo: segBox.leadingAnchor, constant: 2)
        cardLeading = card.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20)
        cardTrailing = card.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -20)
        NSLayoutConstraint.activate([
            // 左右边距不硬编码：viewDidLayoutSubviews 里按系统容器实际 frame 动态对齐
            cardLeading,
            cardTrailing,
            card.topAnchor.constraint(equalTo: topAnchor, constant: 4),
            card.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -CardRole.summary.groupSpacing),

            stack.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: CardRole.summary.horizontalInset),
            stack.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -CardRole.summary.horizontalInset),
            stack.topAnchor.constraint(equalTo: card.topAnchor, constant: CardRole.summary.verticalInset),
            stack.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -CardRole.summary.verticalInset),

            divider.heightAnchor.constraint(equalToConstant: 1 / UIScreen.main.scale),
            statusDot.widthAnchor.constraint(equalToConstant: 5),
            statusDot.heightAnchor.constraint(equalToConstant: 5),
            eyeButton.widthAnchor.constraint(equalToConstant: 30),
            eyeButton.heightAnchor.constraint(equalToConstant: 30),

            segBox.widthAnchor.constraint(equalToConstant: 100),
            segBox.heightAnchor.constraint(equalToConstant: 26),
            segPill.topAnchor.constraint(equalTo: segBox.topAnchor, constant: 2),
            segPill.bottomAnchor.constraint(equalTo: segBox.bottomAnchor, constant: -2),
            segPill.widthAnchor.constraint(equalToConstant: 48),
            pillLeading,
            segToday.leadingAnchor.constraint(equalTo: segBox.leadingAnchor, constant: 2),
            segToday.widthAnchor.constraint(equalToConstant: 48),
            segToday.topAnchor.constraint(equalTo: segBox.topAnchor),
            segToday.bottomAnchor.constraint(equalTo: segBox.bottomAnchor),
            segCum.leadingAnchor.constraint(equalTo: segToday.trailingAnchor),
            segCum.widthAnchor.constraint(equalToConstant: 48),
            segCum.topAnchor.constraint(equalTo: segBox.topAnchor),
            segCum.bottomAnchor.constraint(equalTo: segBox.bottomAnchor),
        ])
        update()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    /// 与基金列表容器动态对齐：左右边距取实际行 frame，圆角统一走 AppCardRadius。
    /// 边距不硬编码——iOS 26 液态玻璃改了系统列表外观参数，动态读才不会过时。
    func alignToContainer(margin: CGFloat, cornerRadius: CGFloat) {
        if abs(cardLeading.constant - margin) > 0.25 {
            cardLeading.constant = margin
            cardTrailing.constant = -margin
        }
        if abs(card.layer.cornerRadius - cornerRadius) > 0.25 {
            card.layer.cornerRadius = cornerRadius
            card.layer.masksToBounds = true
        }
    }

    deinit { displayLink?.invalidate() }

    @objc private func toggleMode() {
        FundStore.shared.heroShowsCum.toggle()
        Haptics.tap()
        update()
    }

    /// C：一键隐藏 / 显示金额。偏好变更通知会让列表与吸顶小计同步重绘。
    @objc private func togglePrivacy() {
        FundStore.shared.hideAmounts = !FundStore.shared.hideAmounts
        Haptics.tap()
        update()
    }

    private func syncPrivacy() {
        let hidden = FundStore.shared.hideAmounts
        let cfg = UIImage.SymbolConfiguration(pointSize: 15, weight: .regular)
        let name = hidden ? "eye.slash" : "eye"
        eyeButton.setImage(UIImage(systemName: name, withConfiguration: cfg), for: .normal)
        eyeButton.accessibilityLabel = hidden ? "显示金额" : "隐藏金额"
    }

    private func syncSeg() {
        let cum = FundStore.shared.heroShowsCum
        pillLeading.constant = cum ? 50 : 2
        segToday.setTitleColor(cum ? TextTier.secondary.color : .label, for: .normal)
        segCum.setTitleColor(cum ? .label : TextTier.secondary.color, for: .normal)
        segToday.accessibilityTraits = cum ? [] : [.selected]
        segCum.accessibilityTraits = cum ? [.selected] : []
        segToday.accessibilityLabel = "切换到今日收益口径"
        segCum.accessibilityLabel = "切换到累计收益口径"
    }

    func update() {
        let isCum = FundStore.shared.heroShowsCum
        let hidden = FundStore.shared.hideAmounts
        syncSeg()
        syncPrivacy()
        // B：洞察句替代裸金额成为主角，无持仓时降级为诚实提示
        insight.text = FundStore.shared.insightLine() ?? "还没有持仓市值"
        todayCaption.text = isCum ? "累计收益" : dayLabel()
        sub.text = isCum ? "市值 − 持有成本 · \(FundStore.shared.funds.count) 只基金" : navCaption()
        let stats = isCum ? FundStore.shared.cumStats() : FundStore.shared.todayStats()
        rightCol.isHidden = (stats == nil)
        let newTotal = FundStore.shared.totalMv

        // 首次 / 减弱动效 / 隐私模式 / 无持仓 / 值没变：直接赋值，不做滚动
        if firstUpdate || UIAccessibility.isReduceMotionEnabled || hidden || stats == nil
            || abs(newTotal - shownTotal) < 0.005 {
            displayLink?.invalidate()
            displayLink = nil
            shownTotal = newTotal
            total.text = Fmt.money(newTotal)
            if let s = stats {
                shownProfit = s.profit
                shownPct = s.pct
                render(profit: s.profit, pct: s.pct)
            }
            firstUpdate = false
            return
        }
        fromTotal = shownTotal; toTotal = newTotal
        fromProfit = shownProfit; toProfit = stats!.profit
        fromPct = shownPct; toPct = stats!.pct
        startAnim()
    }

    private func render(profit: Double, pct: Double) {
        let p = Fmt.round2(profit)
        // 隐私模式：金额打码，涨跌幅百分比保留（不是金额，且是判断方向的关键信息）
        if FundStore.shared.hideAmounts {
            todayValue.text = "\(Fmt.masked) (\(Fmt.pct(pct)))"
        } else {
            todayValue.text = "\(p > 0 ? "+" : "")\(Fmt.money(p)) (\(Fmt.pct(pct)))"
        }
        todayValue.textColor = Theme.color(for: pct)
    }

    private func startAnim() {
        displayLink?.invalidate()
        animStart = 0
        let link = CADisplayLink(target: self, selector: #selector(step(_:)))
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    @objc private func step(_ link: CADisplayLink) {
        if animStart == 0 { animStart = link.timestamp; return }
        let p = min(1, (link.timestamp - animStart) / 0.55)
        let e = 1 - pow(1 - p, 3)   // ease-out cubic
        shownTotal = fromTotal + (toTotal - fromTotal) * e
        shownProfit = fromProfit + (toProfit - fromProfit) * e
        shownPct = fromPct + (toPct - fromPct) * e
        total.text = Fmt.money(Fmt.round2(shownTotal))
        render(profit: shownProfit, pct: shownPct)
        if p >= 1 {
            link.invalidate()
            if displayLink === link { displayLink = nil }
        }
    }

    // MARK: 诚实文案：time 字段是「净值日期」（MM-dd），不是刷新时刻
    private func latestStamp() -> String {
        let times = FundStore.shared.funds.map { $0.time }.filter { !$0.isEmpty && $0 != "--:--" }
        return times.first ?? "--:--"
    }
    private static func todayStr() -> String {
        let f = DateFormatter()
        f.dateFormat = "MM-dd"
        return f.string(from: Date())
    }
    /// 净值日 = 今天才叫「今日收益」，否则如实叫「净值日收益」
    private func dayLabel() -> String {
        return latestStamp() == Self.todayStr() ? "今日收益" : "净值日收益"
    }
    private func navCaption() -> String {
        let stamp = latestStamp()
        let n = FundStore.shared.funds.count
        if stamp.contains("-") { return "按 \(stamp) 净值估算 · \(n) 只基金" }
        return "\(n) 只基金 · 截至 \(stamp)"
    }
}

// MARK: - 空状态
final class EmptyStateView: UIView {
    private let icon = UIImageView()
    private let caption = UILabel()
    private let detail = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        icon.image = UIImage(systemName: "chart.line.uptrend.xyaxis",
                             withConfiguration: UIImage.SymbolConfiguration(pointSize: 44, weight: .regular))
        icon.tintColor = TextTier.secondary.color
        icon.contentMode = .scaleAspectFit

        caption.text = "还没有基金"
        caption.style(Typo.scaled(19, .semibold, style: .headline), .label)
        caption.textAlignment = .center

        detail.text = "点右上角 + 添加基金\n数据只保存在这台设备上"
        detail.style(Typo.scaled(14, style: .subheadline), TextTier.secondary.color)
        detail.textAlignment = .center
        detail.numberOfLines = 0

        let stack = UIStackView(arrangedSubviews: [icon, caption, detail])
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = 10
        stack.setCustomSpacing(14, after: icon)
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor, constant: -40),
            stack.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 32),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -32),
        ])
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}

// MARK: - 基金行（insetGrouped：整组由系统画成一张大卡，本行只负责内容）
final class FundCell: UITableViewCell {
    private let face = UILabel()
    private let name = UILabel()
    private let meta = UILabel()
    private let pctL = UILabel()
    private let navv = UILabel()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        // 行背景交给 backgroundConfiguration（insetGrouped 系统容器统一管理圆角与侧滑；
        // 直接设 cell.backgroundColor 会生成隐式实心背景层，侧滑时与系统圆角框错位）
        contentView.backgroundColor = .clear
        selectionStyle = .none

        face.textAlignment = .center
        face.style(Typo.scaled(16, .semibold, style: .headline), .white)
        face.cardStyle(10)
        face.translatesAutoresizingMaskIntoConstraints = false
        face.setContentHuggingPriority(.required, for: .horizontal)
        face.setContentCompressionResistancePriority(.required, for: .horizontal)

        name.style(Typo.scaled(16, .semibold, style: .subheadline), .label)
        name.numberOfLines = 1

        meta.style(Typo.scaled(12, style: .caption1, monoDigits: true), TextTier.secondary.color)
        meta.numberOfLines = 1

        let info = UIStackView(arrangedSubviews: [name, meta])
        info.axis = .vertical
        info.spacing = 3

        pctL.style(Typo.scaled(16, .semibold, style: .subheadline, monoDigits: true), .label)
        navv.style(Typo.scaled(12, style: .caption1, monoDigits: true), TextTier.secondary.color)

        let right = UIStackView(arrangedSubviews: [pctL, navv])
        right.axis = .vertical
        right.spacing = 3
        right.alignment = .trailing
        right.setContentHuggingPriority(.required, for: .horizontal)
        right.setContentCompressionResistancePriority(.required, for: .horizontal)

        let chev = UIImageView(image: UIImage(systemName: "chevron.right"))
        chev.preferredSymbolConfiguration = UIImage.SymbolConfiguration(textStyle: .caption1, scale: .small)
        chev.tintColor = TextTier.secondary.color
        chev.contentMode = .center

        let row = UIStackView(arrangedSubviews: [face, info, right, chev])
        row.axis = .horizontal
        row.spacing = 12
        row.alignment = .center
        row.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(row)

        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            row.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            row.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 11),
            row.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -11),

            face.widthAnchor.constraint(equalToConstant: 38),
            face.heightAnchor.constraint(equalToConstant: 38),
        ])
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(_ f: Fund, index i: Int) {
        face.text = String(f.name.prefix(1))
        face.backgroundColor = FundStore.shared.color(at: i)
        name.text = f.name

        let hasHold = f.amount > 0 || f.mv > 0 || f.shares > 0
        let detail = (FundStore.shared.showHold && hasHold)
            ? "持有 \(Fmt.money(f.amount)) · 市值 \(Fmt.money(f.mv))"
            : "轻点看持仓 · 左滑编辑"
        meta.text = "\(f.code) · \(detail)"
        pctL.text = Fmt.pct(f.estPct)
        pctL.textColor = Theme.color(for: f.estPct)
        navv.text = "单位净值 " + Fmt.nav(f.estNav)

        isAccessibilityElement = true
        accessibilityTraits = .button
        accessibilityLabel = "\(f.name)，代码 \(f.code)，单位净值 \(Fmt.nav(f.estNav))，涨跌 \(Fmt.pct(f.estPct))，\(detail)"
        accessibilityHint = "轻点查看重仓持股"
    }

    /// 背景统一走 backgroundConfiguration：系统据此画圆角容器，侧滑/按压/选中态同步管理
    override func updateConfiguration(using state: UICellConfigurationState) {
        super.updateConfiguration(using: state)
        var bg = UIBackgroundConfiguration.listGroupedCell()
        // 按压反馈：整行底色轻微加深（HIG：即时、可感知、不位移）
        bg.backgroundColor = (state.isHighlighted || state.isSelected)
            ? UIColor.tertiarySystemGroupedBackground
            : UIColor.secondarySystemGroupedBackground
        backgroundConfiguration = bg
    }
}

// MARK: - A：吸顶小计条
/// 头卡滚出视野后接管摘要。与基金列表卡片**同边距、同圆角（AppCardRadius）**，
/// 连续曲率 + 发丝描边做成一个克制的悬浮小卡，而不是横贯全宽、贴死导航栏的硬横条。
/// 不用玻璃、不用阴影（HIG《Materials》：内容层只用实色）；金额统一走 Fmt.money，隐私模式自动打码。
final class CompactSummaryBar: UIView {
    private let statusDot = UIView()
    private let caption = UILabel()
    private let amount = UILabel()
    private let profit = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .secondarySystemGroupedBackground
        layer.cornerRadius = AppCardRadius
        layer.cornerCurve = .continuous
        applyBorder()

        // 与头卡同一枚蓝色状态点：表达「估算值」口径，不占红涨绿跌语义
        statusDot.backgroundColor = .systemBlue
        statusDot.layer.cornerRadius = 2.5
        statusDot.translatesAutoresizingMaskIntoConstraints = false

        caption.text = "总市值"
        caption.style(Typo.scaled(12, .medium, style: .caption1), TextTier.secondary.color)
        caption.setContentHuggingPriority(.required, for: .horizontal)

        amount.style(Typo.scaled(16, .semibold, style: .subheadline, monoDigits: true), .label)
        amount.numberOfLines = 1
        amount.adjustsFontSizeToFitWidth = true
        amount.minimumScaleFactor = 0.75

        profit.style(Typo.scaled(12, .medium, style: .caption1, monoDigits: true), .label)
        profit.numberOfLines = 1
        profit.setContentCompressionResistancePriority(.required, for: .horizontal)

        let left = UIStackView(arrangedSubviews: [statusDot, caption, amount])
        left.axis = .horizontal
        left.alignment = .center
        left.spacing = 7
        left.setCustomSpacing(5, after: statusDot)
        left.translatesAutoresizingMaskIntoConstraints = false
        profit.translatesAutoresizingMaskIntoConstraints = false
        addSubview(left)
        addSubview(profit)
        NSLayoutConstraint.activate([
            statusDot.widthAnchor.constraint(equalToConstant: 5),
            statusDot.heightAnchor.constraint(equalToConstant: 5),
            left.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            left.centerYAnchor.constraint(equalTo: centerYAnchor),
            left.trailingAnchor.constraint(lessThanOrEqualTo: profit.leadingAnchor, constant: -10),
            profit.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            profit.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
        update()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    /// CGColor 不随深浅模式自动刷新，trait 变化时要重新解析一次动态色
    private func applyBorder() {
        layer.borderWidth = 1 / UIScreen.main.scale
        layer.borderColor = UIColor.separator.resolvedColor(with: traitCollection)
            .withAlphaComponent(0.45).cgColor
    }
    override func traitCollectionDidChange(_ previous: UITraitCollection?) {
        super.traitCollectionDidChange(previous)
        if previous?.userInterfaceStyle != traitCollection.userInterfaceStyle { applyBorder() }
    }

    func update() {
        let store = FundStore.shared
        amount.text = Fmt.money(store.totalMv)
        let stats = store.heroShowsCum ? store.cumStats() : store.todayStats()
        guard let s = stats else {
            profit.isHidden = true
            return
        }
        profit.isHidden = false
        profit.text = store.hideAmounts
            ? "\(Fmt.masked) (\(Fmt.pct(s.pct)))"
            : "\(Fmt.money(Fmt.round2(s.profit))) (\(Fmt.pct(s.pct)))"
        profit.textColor = Theme.color(for: s.pct)
    }
}
