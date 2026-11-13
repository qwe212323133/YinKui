import UIKit

final class AddFundVC: UIViewController, UITextFieldDelegate {
    private let codeCard = FieldCard(title: "基金代码", placeholder: "如 161725", keyboard: .numberPad)
    private let nameCard = FieldCard(title: "基金名称", placeholder: "自动识别，也可手动填写")
    private let sharesCard = FieldCard(title: "持有份额", placeholder: "选填，填后市值自动算", keyboard: .decimalPad)
    private lazy var codeTF = codeCard.textField
    private lazy var nameTF = nameCard.textField
    private lazy var sharesTF = sharesCard.textField
    private let hint = UILabel()
    private let stack = UIStackView()
    private var nameTouched = false
    private var didFit = false
    private var contentHeight: CGFloat = 0
    private var keyboardLimit: CGFloat = .greatestFiniteMagnitude
    private let fitID = UISheetPresentationController.Detent.Identifier("fit")

    override func viewDidLoad() {
        super.viewDidLoad()
        view.glassBackground()
        sheetGlassNavBar()
        title = "添加基金"
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .cancel, target: self, action: #selector(cancel))
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .done, target: self, action: #selector(save))

        codeTF.delegate = self
        nameTF.delegate = self
        sharesTF.delegate = self

        hint.style(Typo.scaled(12, style: .caption1), TextTier.secondary.color)
        hint.text = "输入 6 位代码，自动识别基金名称"
        hint.numberOfLines = 0

        let note = UILabel()
        note.text = "添加后轻点卡片查看持仓，左滑可编辑金额"
        note.style(Typo.scaled(12, style: .caption1), TextTier.secondary.color)
        note.numberOfLines = 0

        stack.axis = .vertical
        stack.spacing = 16
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.addArrangedSubview(codeCard)
        stack.addArrangedSubview(nameCard)
        stack.addArrangedSubview(sharesCard)
        stack.addArrangedSubview(hint)
        stack.addArrangedSubview(note)
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
        if textField === codeTF {
            let cur = (codeTF.text ?? "") as NSString
            let raw = cur.replacingCharacters(in: range, with: string)
            let digits = raw.filter { $0.isNumber }
            if digits.count > 6 { return false }
            codeTF.text = String(digits)
            if digits.count == 6 {
                if let name = FundDB.shared.name(for: String(digits)) {
                    if !nameTouched { nameTF.text = name }
                    hint.text = "已识别：\(name)"
                    hint.textColor = .systemGreen
                } else {
                    hint.text = "未收录该代码，请手动填写名称"
                    hint.textColor = .systemRed
                }
            } else {
                hint.text = "输入 6 位代码，自动识别基金名称"
                hint.textColor = TextTier.secondary.color
            }
            return false
        } else if textField === nameTF {
            nameTouched = true
        } else if textField === sharesTF {
            // 份额：只允许一个小数点、最多两位小数
            let cur = (textField.text ?? "") as NSString
            let next = cur.replacingCharacters(in: range, with: string)
            let parts = next.split(separator: ".", omittingEmptySubsequences: false)
            if parts.count > 2 { return false }
            if parts.count == 2 && parts[1].count > 2 { return false }
        }
        return true
    }

    @objc private func cancel() { dismiss(animated: true) }

    @objc private func save() {
        let code = (codeTF.text ?? "").trimmingCharacters(in: .whitespaces)
        let name = (nameTF.text ?? "").trimmingCharacters(in: .whitespaces).isEmpty
            ? "未命名基金" : (nameTF.text ?? "").trimmingCharacters(in: .whitespaces)
        guard code.count == 6, code.allSatisfy({ $0.isNumber }) else { codeTF.becomeFirstResponder(); return }
        if let i = FundStore.shared.funds.firstIndex(where: { $0.code == code }) {
            let list = (presentingViewController as? UINavigationController)?.viewControllers.first as? FundListVC
            dismiss(animated: true) {
                guard let list = list else { return }
                let detail = FundDetailVC(index: i)
                let dnav = UINavigationController(rootViewController: detail)
                dnav.modalPresentationStyle = .pageSheet
                if let sheet = dnav.sheetPresentationController {
                    sheet.detents = [.large()]
                    sheet.prefersGrabberVisible = true
                }
                list.present(dnav, animated: true)
            }
            return
        }
        FundStore.shared.funds.append(Fund(code: code, name: name, estNav: 1.0, estPct: 0,
                                            amount: 0, mv: 0,
                                            shares: Double(sharesTF.text ?? "") ?? 0, time: "--:--"))
        FundStore.shared.saveFunds()
        NotificationCenter.default.post(name: .plFundsChanged, object: nil)
        dismiss(animated: true)
    }
}
