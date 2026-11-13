import UIKit

final class EditFundVC: UIViewController, UITextFieldDelegate {
    private let index: Int
    private let amountCard: FieldCard
    private let mvCard: FieldCard
    private let sharesCard: FieldCard
    private lazy var amountTF = amountCard.textField
    private lazy var mvTF = mvCard.textField
    private lazy var sharesTF = sharesCard.textField
    private let stack = UIStackView()
    private var didFit = false
    private var contentHeight: CGFloat = 0
    private var keyboardLimit: CGFloat = .greatestFiniteMagnitude
    private let fitID = UISheetPresentationController.Detent.Identifier("fit")

    init(index: Int) {
        self.index = index
        let f = FundStore.shared.funds.indices.contains(index) ? FundStore.shared.funds[index] : Fund(code: "", name: "", estNav: 0, estPct: 0, amount: 0, mv: 0, time: "")
        amountCard = FieldCard(title: "持有金额（成本）", placeholder: "0.00",
                               keyboard: .decimalPad, text: f.amount == 0 ? "" : String(format: "%.2f", f.amount))
        // 填了份额的基金：市值由「份额 × 最新净值」自动算出，展示推导值而非陈旧的手填值
        let derivedMv = f.shares > 0 && f.estNav > 0 ? Fmt.round2(f.shares * f.estNav) : f.mv
        mvCard = FieldCard(title: "持有市值（当前）", placeholder: "0.00",
                           keyboard: .decimalPad, text: derivedMv == 0 ? "" : String(format: "%.2f", derivedMv))
        sharesCard = FieldCard(title: "持有份额", placeholder: "选填，填后市值自动算",
                               keyboard: .decimalPad, text: f.shares == 0 ? "" : String(format: "%.2f", f.shares))
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.glassBackground()
        sheetGlassNavBar()
        title = "编辑持仓"
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .cancel, target: self, action: #selector(cancel))
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .done, target: self, action: #selector(save))

        guard index < FundStore.shared.funds.count else { return }
        let f = FundStore.shared.funds[index]

        let head = UILabel()
        head.text = "\(f.name)  ·  \(f.code)"
        head.style(Typo.scaled(15, .medium, style: .subheadline), TextTier.secondary.color)

        amountTF.delegate = self
        mvTF.delegate = self
        sharesTF.delegate = self

        let tip = UILabel()
        tip.text = "填了份额后，每次刷新按「份额 × 最新净值」自动重算市值，无需手动维护"
        tip.style(Typo.scaled(12, style: .caption1), TextTier.secondary.color)
        tip.numberOfLines = 0

        stack.axis = .vertical
        stack.spacing = 18
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.addArrangedSubview(head)
        stack.addArrangedSubview(amountCard)
        stack.addArrangedSubview(mvCard)
        stack.addArrangedSubview(sharesCard)
        stack.addArrangedSubview(tip)
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 16),
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
        ])

        NotificationCenter.default.addObserver(self, selector: #selector(kbWillShow),
            name: UIResponder.keyboardWillShowNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(kbWillHide),
            name: UIResponder.keyboardWillHideNotification, object: nil)
    }

    deinit { NotificationCenter.default.removeObserver(self) }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        // sheet 属于外层 nav；必须成功拿到 sheet 才标记完成，否则下次布局重试
        guard let sheet = navigationController?.sheetPresentationController ?? sheetPresentationController else { return }
        sheet.prefersGrabberVisible = true
        sheet.prefersScrollingExpandsWhenScrolledToEdge = false
        guard #available(iOS 16.0, *) else {
            sheet.detents = [.medium()]
            return
        }
        let navH = navigationController?.navigationBar.frame.height ?? 44
        let h = navH + stack.frame.maxY + 20 + view.safeAreaInsets.bottom
        if !didFit {
            didFit = true
            contentHeight = h
            // detents 里永远只放「一个」自定义档位，绝不能带 .large()。
            // 只要存在更大的档位，iOS 在键盘出现时会自动把 sheet 提升到最大档，
            // 并覆盖 selectedDetentIdentifier —— 这就是卡片顶到状态栏、下方大片留白的原因。
            sheet.detents = [.custom(identifier: fitID) { [weak self] ctx in
                let want = self?.contentHeight ?? 0
                let limit = self?.keyboardLimit ?? .greatestFiniteMagnitude
                return max(240, min(want, limit, ctx.maximumDetentValue))
            }]
            sheet.selectedDetentIdentifier = fitID
        } else if abs(h - contentHeight) > 24 {
            // 内容高度明显变化（动态字体 / 旋转）时同步，忽略键盘造成的微小抖动
            contentHeight = h
            sheet.invalidateDetents()
        }
    }

    @objc private func kbWillShow(_ n: Notification) {
        guard let r = (n.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect)?.integral else { return }
        // 键盘顶部 Y（屏幕坐标）减去状态栏安全区，再留 12pt 呼吸空间
        let topSafe = view.window?.safeAreaInsets.top ?? view.safeAreaInsets.top
        keyboardLimit = max(240, r.minY - topSafe - 12)
        invalidate()
    }
    @objc private func kbWillHide(_ n: Notification) {
        keyboardLimit = .greatestFiniteMagnitude
        invalidate()
    }

    // 让系统用最新的 self 状态重新求解自定义档位高度（无需重建 detents 数组）
    private func invalidate() {
        guard #available(iOS 16.0, *) else { return }
        guard let sheet = navigationController?.sheetPresentationController ?? sheetPresentationController else { return }
        sheet.animateChanges { sheet.invalidateDetents() }
    }

    func textField(_ textField: UITextField, shouldChangeCharactersIn range: NSRange,
                   replacementString string: String) -> Bool {
        let cur = (textField.text ?? "") as NSString
        let next = cur.replacingCharacters(in: range, with: string)
        // 只允许一个小数点、最多两位小数
        let parts = next.split(separator: ".", omittingEmptySubsequences: false)
        if parts.count > 2 { return false }
        if parts.count == 2 && parts[1].count > 2 { return false }
        return true
    }

    @objc private func cancel() { dismiss(animated: true) }

    @objc private func save() {
        guard index < FundStore.shared.funds.count else { dismiss(animated: true); return }
        FundStore.shared.funds[index].amount = Double(amountTF.text ?? "") ?? 0
        FundStore.shared.funds[index].shares = Double(sharesTF.text ?? "") ?? 0
        // 填了份额且有最新净值：市值自动推导（覆盖输入框）；否则取手填市值
        if !FundStore.shared.funds[index].recomputeMv() {
            FundStore.shared.funds[index].mv = Double(mvTF.text ?? "") ?? 0
        }
        FundStore.shared.saveFunds()
        NotificationCenter.default.post(name: .plFundsChanged, object: nil)
        dismiss(animated: true)
    }
}
