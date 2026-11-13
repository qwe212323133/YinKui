import UIKit

// MARK: - 模型
struct Fund: Codable {
    var code: String
    var name: String
    var estNav: Double
    var estPct: Double
    var amount: Double
    var mv: Double
    /// 持有份额：>0 时市值 = 份额 × 最新净值，随刷新自动重算（0 = 维持手填市值）
    var shares: Double
    var time: String

    private enum CodingKeys: String, CodingKey {
        case code, name, estNav, estPct, amount, mv, shares, time
    }

    init(code: String, name: String, estNav: Double, estPct: Double,
         amount: Double, mv: Double, shares: Double = 0, time: String) {
        self.code = code; self.name = name
        self.estNav = estNav; self.estPct = estPct
        self.amount = amount; self.mv = mv
        self.shares = shares; self.time = time
    }

    /// 老版本持久化 JSON 里没有 shares 键，解码缺省为 0，完全向后兼容。
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        code = try c.decode(String.self, forKey: .code)
        name = try c.decode(String.self, forKey: .name)
        estNav = try c.decode(Double.self, forKey: .estNav)
        estPct = try c.decode(Double.self, forKey: .estPct)
        amount = try c.decode(Double.self, forKey: .amount)
        mv = try c.decode(Double.self, forKey: .mv)
        shares = try c.decodeIfPresent(Double.self, forKey: .shares) ?? 0
        time = try c.decode(String.self, forKey: .time)
    }

    /// 填了份额且有最新净值时，用「份额 × 净值」重算市值（保留两位）。
    /// 返回 false 表示份额未填或净值无效，维持手填市值。
    mutating func recomputeMv() -> Bool {
        guard shares > 0, estNav > 0 else { return false }
        mv = Fmt.round2(shares * estNav)
        return true
    }
}

// MARK: - 格式化 / 主题
enum Fmt {
    /// 金额统一出口。隐私模式在这里打码，所有展示点（头卡 / 吸顶小计 / 列表行）自动生效；
    /// 表单输入框走原始 Double，不会把掩码写回数据。
    static let masked = "••••••"
    static func money(_ n: Double) -> String {
        if FundStore.shared.hideAmounts { return masked }
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.minimumFractionDigits = 2
        f.maximumFractionDigits = 2
        f.locale = Locale(identifier: "zh_CN")
        return "¥" + (f.string(from: NSNumber(value: n)) ?? "0.00")
    }
    /// 涨跌幅：零值不带符号（HIG：正负号只在确有方向时出现）
    static func pct(_ p: Double) -> String {
        let v = abs(p) < 0.005 ? 0 : p
        return String(format: "%@%.2f%%", v > 0 ? "+" : "", v)
    }
    /// 单位净值：保留 4 位
    static func nav(_ v: Double) -> String { return String(format: "%.4f", v) }
    static func nowHM() -> String {
        let c = Calendar.current
        let d = Date()
        return String(format: "%02d:%02d", c.component(.hour, from: d), c.component(.minute, from: d))
    }
    static func round2(_ v: Double) -> Double { return (v * 100).rounded() / 100 }
}

extension UIColor {
    convenience init(hex: String) {
        var h = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if h.hasPrefix("#") { h.removeFirst() }
        var rgb: UInt64 = 0
        Scanner(string: h).scanHexInt64(&rgb)
        let r = CGFloat((rgb & 0xFF0000) >> 16) / 255.0
        let g = CGFloat((rgb & 0x00FF00) >> 8) / 255.0
        let b = CGFloat(rgb & 0x0000FF) / 255.0
        self.init(red: r, green: g, blue: b, alpha: 1)
    }
}

enum Theme {
    /// 涨色：cn=红涨绿跌，us=绿涨红跌。用系统语义色，深色模式自动切换。
    static func up() -> UIColor { FundStore.shared.scheme == "cn" ? .systemRed : .systemGreen }
    static func down() -> UIColor { FundStore.shared.scheme == "cn" ? .systemGreen : .systemRed }
    /// 涨跌色：涨用涨色、跌用跌色、持平用次级文字色（HIG：颜色只承载方向信息）。
    /// 涨 / 跌一律保持系统 systemRed / systemGreen 原色，不做明度派生（Boss 决策）；
    /// 只有「持平」属中性文字，走 TextTier 保证可读。
    static func color(for pct: Double) -> UIColor {
        if abs(pct) < 0.005 { return TextTier.secondary.color }
        return pct > 0 ? up() : down()
    }
}

// MARK: - 文字层级令牌
/// 系统语义色在浅色下不达 WCAG AA：secondaryLabel 3.44:1、tertiaryLabel 1.73:1，
/// 而小字（≤17pt）门槛是 4.5:1 —— 这就是「头卡文字太浅」的根因。深色模式反而达标（5.95:1）。
/// 故收敛成两档可读文字色，层级差异交给字号 / 字重 / 行高表达，不再靠「更浅的灰」制造层级。
/// 四上下文齐全：默认浅 / 增强对比浅 / 默认深 / 增强对比深；动态色由 UIKit 自动重解析。
/// primary 与系统 .label 等价（21:1），主文字直接用 .label 即可；令牌的治理重点是
/// 过去被 secondaryLabel / tertiaryLabel 拖到不达标的次级文字。
/// 涨跌色不在此列，见 Theme。
enum TextTier {
    case primary
    case secondary
    case placeholder

    var color: UIColor {
        switch self {
        case .primary:
            return .label   // 21:1 浅 / 17:1 深，系统自带增强对比变体
        case .secondary:
            return UIColor { tc in
                let dark = tc.userInterfaceStyle == .dark
                let high = tc.accessibilityContrast == .high
                if dark { return high ? UIColor(hex: "B0B0B5") : UIColor(hex: "98989F") }
                return high ? UIColor(hex: "5A5A5F") : UIColor(hex: "6E6E73")
            }
        case .placeholder:
            // 唯一允许低对比的例外：占位符不承载必须阅读的信息，输入后即消失。
            return .placeholderText
        }
    }
}

// MARK: - 设计令牌（Dynamic Type / 连续圆角 / 触感 / 提示）
enum Typo {
    /// 以系统字号为基准，随「设置 → 显示与亮度 → 文字大小」缩放。
    /// 金额与涨跌一律走 monospacedDigits，数字变化时不会左右抖动。
    static func scaled(_ size: CGFloat, _ weight: UIFont.Weight = .regular,
                       style: UIFont.TextStyle = .body, monoDigits: Bool = false) -> UIFont {
        let base = monoDigits
            ? UIFont.monospacedDigitSystemFont(ofSize: size, weight: weight)
            : UIFont.systemFont(ofSize: size, weight: weight)
        return UIFontMetrics(forTextStyle: style).scaledFont(for: base)
    }
}

enum Haptics {
    static func tap(_ style: UIImpactFeedbackGenerator.FeedbackStyle = .light) {
        let g = UIImpactFeedbackGenerator(style: style)
        g.prepare()
        g.impactOccurred()
    }
    static func result(_ type: UINotificationFeedbackGenerator.FeedbackType) {
        UINotificationFeedbackGenerator().notificationOccurred(type)
    }
}

/// 全 App 容器卡统一圆角（与设置页 FormSection、详情卡、列表 box 一致）。
/// 小控件（头像/分段/弹窗按钮）按尺寸用更小半径，不在此列。
let AppCardRadius: CGFloat = 14

/// 卡片语义角色：只保留「排版尺度 / 间距」令牌。
/// 形状统一由 AppCardRadius 派生；材质一律用系统 grouped 平涂，不做相对提亮、顶缘高光或伪玻璃——
/// HIG《Materials》禁止在内容层使用 Liquid Glass，列表 / 卡片 / cell 都属内容层。
/// 层级差异改由信息结构与行为承担：头卡用洞察句 + 1px 硬线分区，滚动时收纳为吸顶小计。
enum CardRole {
    case summary    // 头卡：聚合态总览，留白更大
    case content    // 列表 / 明细：系统 grouped 平涂（由 backgroundConfiguration 管理）

    /// 内容内边距：总览卡留白更大——Apple 用「更多空间」表达更高权重，零视觉噪音。
    /// content 分支是系统 grouped 列表的基准对照值，列表实际由 UIBackgroundConfiguration 管理。
    var horizontalInset: CGFloat {
        switch self {
        case .summary: return 20
        case .content: return 16
        }
    }
    var verticalInset: CGFloat {
        switch self {
        case .summary: return 18
        case .content: return 14
        }
    }

    /// 与相邻分组（下方列表）的呼吸间距
    var groupSpacing: CGFloat {
        switch self {
        case .summary: return 20
        case .content: return 12
        }
    }
}

extension UIView {
    /// 连续曲率圆角（Apple 系统控件的圆角曲线），卡片统一走这里。
    /// 全 App 容器卡统一 14（与设置页 FormSection 一致），小控件按尺寸用更小半径。
    func cardStyle(_ radius: CGFloat = AppCardRadius, color: UIColor? = nil) {
        if let c = color { backgroundColor = c }
        layer.cornerRadius = radius
        layer.cornerCurve = .continuous
        layer.masksToBounds = true
    }

    /// 弹窗玻璃底：毛玻璃材质铺满视图最底层，替代不透明底色，
    /// 让后面变暗的页面微微透出——系统弹窗的「玻璃质感」来源。
    /// 深浅色自动适配；内容卡保持不透明，对比更立体。
    func glassBackground() {
        backgroundColor = .clear
        let blur = UIVisualEffectView(effect: Self.sheetGlassEffect())
        blur.translatesAutoresizingMaskIntoConstraints = false
        blur.isUserInteractionEnabled = false
        insertSubview(blur, at: 0)
        NSLayoutConstraint.activate([
            blur.topAnchor.constraint(equalTo: topAnchor),
            blur.leadingAnchor.constraint(equalTo: leadingAnchor),
            blur.trailingAnchor.constraint(equalTo: trailingAnchor),
            blur.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    /// 弹窗玻璃材质：iOS 26+ 用系统液态玻璃（Liquid Glass，带折射与边缘高光），
    /// 更早系统回退 thinMaterial 毛玻璃。真机 iOS 27 始终走液态玻璃分支。
    static func sheetGlassEffect() -> UIVisualEffect {
        if #available(iOS 26.0, *) { return UIGlassEffect() }
        return UIBlurEffect(style: .systemThinMaterial)
    }
}

extension UIViewController {
    /// 弹窗导航栏透明化：系统默认 bar 有自己的底色（systemBackground 系），
    /// 与 sheet 的毛玻璃底上下两截颜色对不上——设成透明后玻璃透满整卡，浑然一体。
    func sheetGlassNavBar() {
        guard let nav = navigationController else { return }
        let app = UINavigationBarAppearance()
        app.configureWithTransparentBackground()
        nav.navigationBar.standardAppearance = app
        nav.navigationBar.scrollEdgeAppearance = app
    }
}

extension UILabel {
    /// 统一字体 + 语义色，并接管动态字体
    func style(_ font: UIFont, _ color: UIColor) {
        self.font = font
        self.textColor = color
        adjustsFontForContentSizeCategory = true
    }
}

/// 轻量提示条：浮在页面底部，1.8s 后自动淡出（刷新失败等反馈用）
enum Toast {
    static func show(_ text: String, in host: UIView) {
        let box = UIView()
        box.translatesAutoresizingMaskIntoConstraints = false
        box.cardStyle(AppCardRadius, color: .secondarySystemGroupedBackground)
        let lb = UILabel()
        lb.text = text
        lb.style(Typo.scaled(13, .medium, style: .footnote), .label)
        lb.textAlignment = .center
        lb.numberOfLines = 0
        lb.translatesAutoresizingMaskIntoConstraints = false
        box.addSubview(lb)
        host.addSubview(box)
        NSLayoutConstraint.activate([
            lb.leadingAnchor.constraint(equalTo: box.leadingAnchor, constant: 16),
            lb.trailingAnchor.constraint(equalTo: box.trailingAnchor, constant: -16),
            lb.topAnchor.constraint(equalTo: box.topAnchor, constant: 10),
            lb.bottomAnchor.constraint(equalTo: box.bottomAnchor, constant: -10),
            box.centerXAnchor.constraint(equalTo: host.centerXAnchor),
            box.bottomAnchor.constraint(equalTo: host.safeAreaLayoutGuide.bottomAnchor, constant: -24),
            box.widthAnchor.constraint(lessThanOrEqualTo: host.widthAnchor, constant: -48),
        ])
        box.alpha = 0
        UIView.animate(withDuration: 0.18, animations: {
            box.alpha = 1
        }, completion: { _ in
            UIView.animate(withDuration: 0.28, delay: 1.8, options: [.curveEaseIn], animations: {
                box.alpha = 0
            }, completion: { _ in
                box.removeFromSuperview()
            })
        })
    }
}

// MARK: - 分组表单（iOS 原生 Inset Grouped 风格）
/// 一个连续圆角容器，内部多行表单 + 发丝分隔线，观感与「设置」一致。
final class FormSection: UIView {
    private let stack = UIStackView()
    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .secondarySystemGroupedBackground
        layer.cornerRadius = AppCardRadius
        layer.cornerCurve = .continuous
        stack.axis = .vertical
        stack.spacing = 0
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }
    /// 追加一行；非首行自动加一道极淡的发丝分隔线。
    func addRow(_ row: FieldRow) {
        if !stack.arrangedSubviews.isEmpty {
            let sep = UIView()
            sep.backgroundColor = .separator
            sep.alpha = 0.4
            sep.translatesAutoresizingMaskIntoConstraints = false
            sep.heightAnchor.constraint(equalToConstant: 1 / UIScreen.main.scale).isActive = true
            stack.addArrangedSubview(sep)
        }
        stack.addArrangedSubview(row)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}

/// 单行表单：标题在左、输入框在右；聚焦时标题高亮为 tint，反馈清晰。
final class FieldRow: UIView {
    let textField: UITextField
    private let titleLabel = UILabel()

    init(title: String, placeholder: String, keyboard: UIKeyboardType = .default,
         text: String = "", titleWidth: CGFloat = 88, clearable: Bool = true) {
        let tf = UITextField()
        tf.placeholder = placeholder
        tf.font = Typo.scaled(17, style: .body)
        tf.adjustsFontForContentSizeCategory = true
        tf.borderStyle = .none
        tf.backgroundColor = .clear
        tf.keyboardType = keyboard
        tf.text = text
        tf.autocapitalizationType = .none
        tf.autocorrectionType = .no
        tf.clearButtonMode = clearable ? .whileEditing : .never
        textField = tf

        titleLabel.text = title
        titleLabel.style(Typo.scaled(16, style: .body), .label)
        titleLabel.setContentHuggingPriority(.required, for: .horizontal)
        titleLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        titleLabel.widthAnchor.constraint(equalToConstant: titleWidth).isActive = true

        let h = UIStackView(arrangedSubviews: [titleLabel, tf])
        h.axis = .horizontal
        h.spacing = 12
        h.alignment = .center
        h.translatesAutoresizingMaskIntoConstraints = false
        super.init(frame: .zero)
        addSubview(h)
        NSLayoutConstraint.activate([
            h.topAnchor.constraint(equalTo: topAnchor, constant: 13),
            h.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            h.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            h.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -13),
        ])
        tf.addTarget(self, action: #selector(focusOn), for: .editingDidBegin)
        tf.addTarget(self, action: #selector(focusOff), for: .editingDidEnd)
    }
    @objc private func focusOn() { UIView.animate(withDuration: 0.2) { self.titleLabel.textColor = .systemBlue } }
    @objc private func focusOff() { UIView.animate(withDuration: 0.2) { self.titleLabel.textColor = .label } }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}

// MARK: - 底部卡片 present（高度按内容，iOS 15/16 行为一致）
/// 自己实现的底部卡片，彻底摆脱系统 detent 的半屏限制：
/// 高度完全由 presentedVC.preferredContentSize 决定，短表单就是短卡片。
final class CardPresentationController: UIPresentationController {
    private let backdrop = UIView()
    private var keyboardH: CGFloat = 0
    private var obs: NSObjectProtocol?

    override var frameOfPresentedViewInContainerView: CGRect {
        guard let container = containerView, let pv = presentedView else { return .zero }
        let w = container.bounds.width
        let contentH = max(presentedViewController.preferredContentSize.height, 160)
        let topGap = max(container.safeAreaInsets.top + 28, 56)
        let maxH = container.bounds.height - topGap - keyboardH
        let h = min(contentH, maxH)
        return CGRect(x: 0, y: container.bounds.height - keyboardH - h, width: w, height: h)
    }

    override func presentationTransitionWillBegin() {
        guard let container = containerView else { return }
        backdrop.backgroundColor = .black
        backdrop.alpha = 0
        backdrop.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(backdrop)
        NSLayoutConstraint.activate([
            backdrop.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            backdrop.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            backdrop.topAnchor.constraint(equalTo: container.topAnchor),
            backdrop.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
        backdrop.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(onBackdrop)))

        if let coord = presentedViewController.transitionCoordinator {
            coord.animate { _ in self.backdrop.alpha = 0.45 }
        } else { backdrop.alpha = 0.45 }

        if let pv = presentedView {
            pv.layer.cornerRadius = 18
            pv.layer.cornerCurve = .continuous
            pv.layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
            pv.clipsToBounds = true
        }

        obs = NotificationCenter.default.addObserver(
            forName: UIResponder.keyboardWillChangeFrameNotification, object: nil, queue: .main) { [weak self] n in
            self?.onKeyboard(n)
        }
    }

    @objc private func onBackdrop() { presentedViewController.dismiss(animated: true) }

    private func onKeyboard(_ n: Notification) {
        guard let container = containerView, let pv = presentedView else { return }
        let dur = (n.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? NSNumber)?.doubleValue ?? 0.25
        let curve = (n.userInfo?[UIResponder.keyboardAnimationCurveUserInfoKey] as? NSNumber)?.uintValue ?? 0
        let opt = UIView.AnimationOptions(rawValue: curve << 16)
        if let r = (n.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue)?.cgRectValue {
            keyboardH = r.intersects(container.frame) ? r.height : 0
        }
        UIView.animate(withDuration: dur, delay: 0, options: [opt]) {
            pv.frame = self.frameOfPresentedViewInContainerView
        }
    }

    /// 内容高度变化（如提示文字换行）后重排卡片高度。
    func refresh() {
        guard presentedViewController.transitionCoordinator == nil else { return }
        guard let pv = presentedView, containerView != nil else { return }
        pv.frame = frameOfPresentedViewInContainerView
    }

    override func containerViewWillLayoutSubviews() {
        super.containerViewWillLayoutSubviews()
        if presentedViewController.transitionCoordinator != nil { return }
        guard let pv = presentedView else { return }
        pv.frame = frameOfPresentedViewInContainerView
    }

    override func dismissalTransitionWillBegin() {
        presentedViewController.transitionCoordinator?.animate { _ in self.backdrop.alpha = 0 }
    }
    override func dismissalTransitionDidEnd(_ completed: Bool) {
        if completed {
            backdrop.removeFromSuperview()
            if let o = obs { NotificationCenter.default.removeObserver(o); obs = nil }
        }
    }
    deinit { if let o = obs { NotificationCenter.default.removeObserver(o) } }
}

/// 上滑进场 / 下滑退场（用 transform，避免与 present 控制器抢 frame）。
final class CardAnimator: NSObject, UIViewControllerAnimatedTransitioning {
    let present: Bool
    init(present: Bool) { self.present = present }
    func transitionDuration(using ctx: UIViewControllerContextTransitioning?) -> TimeInterval { present ? 0.38 : 0.3 }
    func animateTransition(using ctx: UIViewControllerContextTransitioning) {
        if present {
            let toVC = ctx.viewController(forKey: .to)!
            let fv = toVC.view!
            let final = ctx.finalFrame(for: toVC)
            ctx.containerView.addSubview(fv)
            fv.frame = final
            fv.transform = CGAffineTransform(translationX: 0, y: final.height)
            UIView.animate(withDuration: 0.38, delay: 0, options: [.curveEaseOut]) {
                fv.transform = .identity
            } completion: { _ in ctx.completeTransition(!ctx.transitionWasCancelled) }
        } else {
            let fromVC = ctx.viewController(forKey: .from)!
            let fv = fromVC.view!
            let h = fv.frame.height
            UIView.animate(withDuration: 0.3, delay: 0, options: [.curveEaseIn]) {
                fv.transform = CGAffineTransform(translationX: 0, y: h)
            } completion: { _ in ctx.completeTransition(!ctx.transitionWasCancelled) }
        }
    }
}

final class CardTransition: NSObject, UIViewControllerTransitioningDelegate {
    static let shared = CardTransition()
    func presentationController(forPresented presented: UIViewController,
                                presenting: UIViewController?,
                                source: UIViewController) -> UIPresentationController? {
        CardPresentationController(presentedViewController: presented, presenting: presenting)
    }
    func animationController(forPresented presented: UIViewController,
                             presenting: UIViewController?,
                             source: UIViewController) -> UIViewControllerAnimatedTransitioning? {
        CardAnimator(present: true)
    }
    func animationController(forDismissed dismissed: UIViewController) -> UIViewControllerAnimatedTransitioning? {
        CardAnimator(present: false)
    }
}

// MARK: - 数据仓库（UserDefaults 持久化）
final class FieldCard: UIView {
    let textField: UITextField
    private let inner: UIStackView

    init(title: String, placeholder: String, keyboard: UIKeyboardType = .default,
         text: String = "", clearable: Bool = true) {
        let titleLabel = UILabel()
        titleLabel.text = title
        titleLabel.style(Typo.scaled(13, .medium, style: .footnote), TextTier.secondary.color)

        let tf = UITextField()
        tf.placeholder = placeholder
        tf.font = Typo.scaled(17, style: .body)
        tf.adjustsFontForContentSizeCategory = true
        tf.borderStyle = .none
        tf.backgroundColor = .clear
        tf.keyboardType = keyboard
        tf.text = text
        tf.autocapitalizationType = .none
        tf.autocorrectionType = .no
        tf.clearButtonMode = clearable ? .whileEditing : .never
        textField = tf

        let stack = UIStackView(arrangedSubviews: [titleLabel, tf])
        stack.axis = .vertical
        stack.spacing = 8
        stack.isLayoutMarginsRelativeArrangement = true
        stack.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 14, leading: 14, bottom: 14, trailing: 14)
        inner = stack

        super.init(frame: .zero)
        // 系统级观感：纯色块无边框（insetGrouped 行同款），聚焦反馈用底色微深表达
        backgroundColor = .secondarySystemGroupedBackground
        layer.cornerRadius = AppCardRadius
        layer.cornerCurve = .continuous

        tf.addTarget(self, action: #selector(focusOn), for: .editingDidBegin)
        tf.addTarget(self, action: #selector(focusOff), for: .editingDidEnd)

        inner.translatesAutoresizingMaskIntoConstraints = false
        addSubview(inner)
        NSLayoutConstraint.activate([
            inner.topAnchor.constraint(equalTo: topAnchor),
            inner.leadingAnchor.constraint(equalTo: leadingAnchor),
            inner.trailingAnchor.constraint(equalTo: trailingAnchor),
            inner.bottomAnchor.constraint(equalTo: bottomAnchor),
            tf.heightAnchor.constraint(greaterThanOrEqualToConstant: 22),
        ])
    }

    override var intrinsicContentSize: CGSize {
        let h = inner.systemLayoutSizeFitting(UIView.layoutFittingCompressedSize).height
        return CGSize(width: UIView.noIntrinsicMetric, height: h)
    }

    @objc private func focusOn() {
        UIView.animate(withDuration: 0.2) {
            self.backgroundColor = .tertiarySystemGroupedBackground
        }
    }
    @objc private func focusOff() {
        UIView.animate(withDuration: 0.2) {
            self.backgroundColor = .secondarySystemGroupedBackground
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}

final class FundStore {
    static let shared = FundStore()
    private init() {}

    private let fundsKey = "pl_funds"
    private let holdKey = "pl_hold"
    private let schemeKey = "pl_scheme"
    private let autoKey = "pl_autoRefresh"   // 自动刷新间隔（秒），0 = 关闭
    private let hideKey = "pl_hide_amounts"  // 隐私模式：隐藏所有金额

    let palette: [UIColor] = [
        UIColor(hex: "#0a84ff"), UIColor(hex: "#ff9f0a"), UIColor(hex: "#ff2d55"),
        UIColor(hex: "#30d158"), UIColor(hex: "#bf5af2"), UIColor(hex: "#64d2ff"),
        UIColor(hex: "#ff453a"),
    ]

    var funds: [Fund] = []
    var showHold: Bool = true
    var scheme: String = "cn"
    /// 自动刷新间隔（秒），0 = 关闭
    var autoRefreshInterval: Int {
        get { UserDefaults.standard.integer(forKey: autoKey) }
        set { UserDefaults.standard.set(max(0, newValue), forKey: autoKey) }
    }

    /// 隐私模式：一键隐藏所有金额（头卡 / 吸顶小计 / 列表行），跨启动记忆。
    /// 打码统一在 Fmt.money 完成；切换后发偏好变更通知，各页即时重绘。
    var hideAmounts: Bool {
        get { UserDefaults.standard.bool(forKey: hideKey) }
        set {
            UserDefaults.standard.set(newValue, forKey: hideKey)
            NotificationCenter.default.post(name: .plPrefsChanged, object: nil)
        }
    }

    func color(at i: Int) -> UIColor { palette[i % palette.count] }

    /// null=首次（用示例）；"[]"=已清空（必须尊重，不能回退示例）
    func load() {
        let ud = UserDefaults.standard
        if let raw = ud.string(forKey: fundsKey), let data = raw.data(using: .utf8),
           let arr = try? JSONDecoder().decode([Fund].self, from: data) {
            funds = arr
        } else if ud.value(forKey: fundsKey) == nil {
            funds = Self.seedClone()
        } else {
            funds = ud.string(forKey: fundsKey) == "[]" ? [] : Self.seedClone()
        }
        showHold = (ud.value(forKey: holdKey) as? String ?? "1") == "1"
        scheme = (ud.string(forKey: schemeKey) == "us") ? "us" : "cn"
        // autoRefreshInterval 有默认值 0，无需显式读取
    }

    func saveFunds() {
        if let data = try? JSONEncoder().encode(funds),
           let raw = String(data: data, encoding: .utf8) {
            UserDefaults.standard.set(raw, forKey: fundsKey)
        }
    }
    func setScheme(_ v: String) {
        scheme = (v == "us") ? "us" : "cn"
        UserDefaults.standard.set(scheme, forKey: schemeKey)
    }
    func setShowHold(_ v: Bool) {
        showHold = v
        UserDefaults.standard.set(v ? "1" : "0", forKey: holdKey)
    }

    static let seed: [Fund] = [
        Fund(code: "000001", name: "华夏成长混合", estNav: 1.2345, estPct: 1.50, amount: 0, mv: 0, time: "15:00"),
        Fund(code: "161725", name: "招商中证白酒", estNav: 0.9876, estPct: -2.00, amount: 0, mv: 0, time: "15:00"),
        Fund(code: "110011", name: "易方达中小盘", estNav: 3.4567, estPct: 0.33, amount: 0, mv: 0, time: "15:00"),
    ]
    static func seedClone() -> [Fund] { seed }   // struct 值语义，直接返回即副本

    var totalMv: Double { funds.reduce(0) { $0 + $1.mv } }

    /// 当日预估收益（元）与市值加权涨跌幅（%）——「最新公布净值」口径：
    /// 盘中 estPct 是上一交易日的涨跌，晚间净值公布后为当日。
    /// 只统计填了市值（mv > 0）的基金；没有任何可统计持仓时返回 nil。
    func todayStats() -> (profit: Double, pct: Double)? {
        let held = funds.filter { $0.mv > 0 }
        guard !held.isEmpty else { return nil }
        let base = held.reduce(0) { $0 + $1.mv }
        guard base > 0 else { return nil }
        let profit = held.reduce(0) { $0 + $1.mv * $1.estPct / 100 }
        return (profit, profit / base * 100)
    }

    /// 累计收益：市值 − 持有成本，涨跌幅基数为成本。
    /// 只统计同时填了市值和成本的基金；没有可统计持仓时返回 nil。
    func cumStats() -> (profit: Double, pct: Double)? {
        let held = funds.filter { $0.mv > 0 && $0.amount > 0 }
        guard !held.isEmpty else { return nil }
        let cost = held.reduce(0) { $0 + $1.amount }
        guard cost > 0 else { return nil }
        let profit = held.reduce(0) { $0 + $1.mv } - cost
        return (profit, profit / cost * 100)
    }

    /// 头卡洞察句：用真实持仓的涨跌分布给出参考点，替代孤立的裸金额。
    /// 只统计填了市值的持仓；不编造基准指数、不预测收益。无持仓时返回 nil 由头卡降级。
    func insightLine() -> String? {
        let held = funds.filter { $0.mv > 0 }
        guard !held.isEmpty else { return nil }
        let n = held.count
        let up = held.filter { $0.estPct > 0.005 }.count
        let down = held.filter { $0.estPct < -0.005 }.count
        if up == n { return "\(n) 只全部上涨" }
        if down == n { return "\(n) 只全部下跌" }
        if up > 0 { return "\(n) 只中 \(up) 只上涨" }
        if down > 0 { return "\(n) 只中 \(down) 只下跌" }
        return "\(n) 只持仓基本持平"
    }

    /// 头卡收益口径：false = 今日（最新净值），true = 累计。跨启动记忆。
    var heroShowsCum: Bool {
        get { UserDefaults.standard.bool(forKey: "pl_hero_cum") }
        set { UserDefaults.standard.set(newValue, forKey: "pl_hero_cum") }
    }
}

// 偏好变更通知（配色/开关改动后各页刷新）
extension Notification.Name {
    static let plPrefsChanged = Notification.Name("pl_prefs_changed")
    static let plFundsChanged = Notification.Name("pl_funds_changed")
}
