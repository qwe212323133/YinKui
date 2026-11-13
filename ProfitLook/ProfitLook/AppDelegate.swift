import UIKit

@main
class AppDelegate: UIResponder, UIApplicationDelegate {
    var window: UIWindow?

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        FundStore.shared.load()
        let win = UIWindow(frame: UIScreen.main.bounds)
        win.tintColor = .systemBlue
        win.rootViewController = MainTabController()
        win.makeKeyAndVisible()
        window = win
        return true
    }
}

/// 原生标签栏：主页 / 设置。全部原生 UIKit，无 WKWebView。
/// 外观全部交给系统（iOS 26 自动使用悬浮玻璃标签栏），这里不自定义背景。
final class MainTabController: UITabBarController {
    override func viewDidLoad() {
        super.viewDidLoad()
        let home = UINavigationController(rootViewController: FundListVC())
        home.tabBarItem = UITabBarItem(title: "主页",
                                       image: UIImage(systemName: "house"),
                                       selectedImage: UIImage(systemName: "house.fill"))
        home.tabBarItem.accessibilityLabel = "主页，我的基金"

        let settings = UINavigationController(rootViewController: SettingsVC())
        settings.tabBarItem = UITabBarItem(title: "设置",
                                           image: UIImage(systemName: "gearshape"),
                                           selectedImage: UIImage(systemName: "gearshape.fill"))
        settings.tabBarItem.accessibilityLabel = "设置"

        viewControllers = [home, settings]
        selectedIndex = 0
        styleNav(home)
        styleNav(settings)
    }

    /// 统一的导航栏外观：顶部大标题透明融入、下滑收起变实底，大标题加粗。
    private func styleNav(_ nav: UINavigationController) {
        nav.navigationBar.prefersLargeTitles = true

        let large = UIFont.preferredFont(forTextStyle: .largeTitle)
        let boldLarge = UIFont(descriptor: large.fontDescriptor
            .withSymbolicTraits(.traitBold) ?? large.fontDescriptor, size: 0)
        let inline = UIFont.preferredFont(forTextStyle: .headline)
        let boldInline = UIFont(descriptor: inline.fontDescriptor
            .withSymbolicTraits(.traitBold) ?? inline.fontDescriptor, size: 0)

        // 顶部（大标题态）：透明背景，标题融入内容
        let edge = UINavigationBarAppearance()
        edge.configureWithTransparentBackground()
        edge.largeTitleTextAttributes = [.font: boldLarge]
        edge.titleTextAttributes = [.font: boldInline]

        // 下滑收起（内联标题态）：系统默认实底，保证可读性
        let standard = UINavigationBarAppearance()
        standard.configureWithDefaultBackground()
        standard.largeTitleTextAttributes = [.font: boldLarge]
        standard.titleTextAttributes = [.font: boldInline]

        nav.navigationBar.standardAppearance = standard
        nav.navigationBar.scrollEdgeAppearance = edge
        nav.navigationBar.compactAppearance = standard
        nav.navigationBar.compactScrollEdgeAppearance = edge
    }
}
