
import Foundation
#if canImport(UIKit)
import UIKit
#else
#error("UIKit only framework")
#endif

/// Level where System view controller should appear. A view controller with the highest Level will be on top of all other view controllers.
public typealias SystemViewControllerLevel = Int
public let SystemViewControllerLevelTop = Int.max

/// Use to place a System view controller above everthing else in app, even status bar and notifications.
///
/// An example of such System view controller is `Update Required` screen.
@objc
public final class SystemWindowController: NSObject {
  public typealias ApplicationProvider = () -> UIApplication?

  /// Private init so that we can only have one `SystemWindowController`. Use SystemWindowController constant
  private let windowLevel: UIWindow.Level
  private let applicationProvider: ApplicationProvider
  
  public init(windowLevel: UIWindow.Level, application: @escaping ApplicationProvider) {
    self.applicationProvider = application
    self.windowLevel = windowLevel
  }
  
  /// Window which fly above all other windows in app.
  fileprivate lazy var window: UIWindow! = {
    let window = UIWindow()
    window.accessibilityIdentifier = "System Window Controller"
    window.windowLevel = self.windowLevel
    window.backgroundColor = UIColor.clear
    window.rootViewController = self.viewController
    return window
  }()

  public var isWindowHidden: Bool { return window.isHidden }
  
  /// Root view controller for `window`
  fileprivate lazy var viewController: SystemWindowViewController! = {
    let viewController = SystemWindowViewController()
    viewController.onEmptyViewControllers = { [weak self] in
      self?.hideSystemWindow()
    }
    return viewController
  }()
  
  /// A window which was a key before `window` became key
  weak var keyWindow: UIWindow? = nil
}

public extension SystemWindowController {
  /**
   Present System view controller
   
   - parameter viewController: a view controller to present
   */
  func show(_ viewController: UIViewController,
                   at level: SystemViewControllerLevel,
                   completion: (() -> Void)? = nil) {
    if !window.isKeyWindow { showSystemWindow() }
    
    self.viewController.show(viewController,
                             at: level,
                             statusBarState: keyWindowStatusBarState,
                             completion: completion)
  }
  
  /**
   Dismiss System view controller
   
   - parameter viewController: a view controller to dismiss
   */
  @available(*, deprecated, message: "Use `dismiss(_:completion:)`. This method will be removed soon.")
  func dismissSystemViewController(_ viewController: UIViewController, completion: (() -> Void)? = nil) {
    dismiss(viewController, completion: completion)
  }

  /**
   Dismiss System view controller
   
   - parameter viewController: a view controller to dismiss
   */
  func dismiss(_ viewController: UIViewController, completion: (() -> Void)? = nil) {
    self.viewController.dismissSystemViewController(viewController, completion: {[weak self] in
      guard let this = self else {
        completion?()
        return
      }
      
      if !this.viewController.hasShownSystemViewControllers {
        this.hideSystemWindow()
      }
      completion?()
    })
  }

  private var keyWindowStatusBarState: StatusBarState {
    return keyWindow?.currentStatusBarState ?? StatusBarState.defaultStatusBar
  }
}

fileprivate extension SystemWindowController {
  /// Make System window key and active
  func showSystemWindow() {
    if let application = applicationProvider() {
      keyWindow = application.keyWindow
      application.keyWindow?.endEditing(true)
    }
    window.frame = keyWindow?.bounds ?? UIScreen.main.bounds
    window.isHidden = false
  }
  
  /// Hide System window and show previously active window
  func hideSystemWindow() {
    window.isHidden = true
    keyWindow = nil
  }
}

/// Root container view controller for System view controllers
@objc(DSLSystemWindowViewController)
private final class SystemWindowViewController: UIViewController {
  typealias Hash = Int
  /// A map from viewController's view hash to it's level
  private var viewHashToLevelMap: [Hash: SystemViewControllerLevel] = [:]
  fileprivate var onEmptyViewControllers: (() -> ())!
  private var statusBarState: StatusBarState? {
    didSet {
      #if os(iOS)
      setNeedsStatusBarAppearanceUpdate()
      #endif
    }
  }
  
  /// Present `viewController` taking into account it's level
  func show(_ viewController: UIViewController,
            at level: SystemViewControllerLevel,
            statusBarState: StatusBarState,
            completion: (() -> Void)?) {
    self.statusBarState = statusBarState
    
    if viewController.modalPresentationStyle == .fullScreen {
      addChild(viewController)
      insertView(viewController.view, atLevel: level)
      viewController.didMove(toParent: self)
      completion?()
    }
    else {
      findViewControllerForPresentation().present(viewController, animated: true, completion: completion)
    }
  }
  
  /// Dismiss `viewController`
  func dismissSystemViewController(_ viewController: UIViewController, completion: (() -> Void)?) {
    if viewController.modalPresentationStyle == .fullScreen {
      viewController.willMove(toParent: nil)
      removeView(viewController.view)
      viewController.removeFromParent()
      completion?()
    }
    else {
      findViewControllerForPresentation().dismiss(animated: true, completion: completion)
    }
  }

  override fileprivate func dismiss(animated flag: Bool, completion: (() -> Void)?) {
    super.dismiss(animated: flag, completion: { [weak self] in
      completion?()
      
      guard let this = self else { return }

      if !this.hasShownSystemViewControllers {
        this.onEmptyViewControllers()
      }
    })
  }
  
  /**
   Inserts `viewToInsert` into appropriate location, taking into account `level`
   
   The view with the highest `level` will be top in the view hierarchy
   
   - parameter viewToInsert: a view to insert into view hierarchy
   - parameter level:        a view's level
   */
  private func insertView(_ viewToInsert: UIView, atLevel level: SystemViewControllerLevel) {
    viewHashToLevelMap[viewToInsert.hashValue] = level
    
    //Find the last view hash which is at the same or less level
    let placeAboveTheViewWithHash = viewHashToLevelMap
      .sorted { (level1, level2) -> Bool in
        return level1.1 < level2.1
      }
      .lastThat { $0.1 <= level }?.0
    
    if let placeAboveTheViewWithHash = placeAboveTheViewWithHash {
      let placeAboveTheView = view.subviews.firstThat { $0.hashValue == placeAboveTheViewWithHash}
      if let placeAboveTheView = placeAboveTheView {
        view.insertSubview(viewToInsert, aboveSubview: placeAboveTheView)
      }
      else {
        view.addSubview(viewToInsert)
      }
    }
    else {
      view.addSubview(viewToInsert)
    }
  }

  fileprivate override func viewWillLayoutSubviews() {
    super.viewWillLayoutSubviews()
    for subview in view.subviews {
      subview.frame = view.bounds
    }
  }
  
  /// Remove `viewToRemove` from view hierarchy
  private func removeView(_ viewToRemove: UIView) {
    viewHashToLevelMap.removeValue(forKey: viewToRemove.hashValue)
    viewToRemove.removeFromSuperview()
  }
  
  private func findViewControllerForPresentation() -> UIViewController {
    var viewControllerForPresentation: UIViewController = self
    while let c = viewControllerForPresentation.presentedViewController {
      viewControllerForPresentation = c
    }
    return viewControllerForPresentation
  }
  
  fileprivate var hasShownSystemViewControllers: Bool {
    return children.count > 0 || presentedViewController != nil
  }

  
  fileprivate override func viewDidLoad() {
    super.viewDidLoad()
    view.backgroundColor = UIColor.clear
  }

  #if os(iOS)
  fileprivate override var prefersStatusBarHidden: Bool {
    return statusBarState?.hidden ?? false
  }
  
  fileprivate override var preferredStatusBarStyle: UIStatusBarStyle {
    return statusBarState?.style ?? .lightContent
  }
  #endif
}

fileprivate extension Sequence {
  func lastThat(_ predicate: (Iterator.Element) -> Bool) -> Iterator.Element? {
    var last: Iterator.Element? = nil
    for element in self {
      if predicate(element) {
        last = element
      }
    }
    
    return last
  }
  
  func firstThat(_ predicate: (Iterator.Element) -> Bool) -> Iterator.Element? {
    for element in self {
      if predicate(element) {
        return element
      }
    }
    
    return nil
  }
}

#if os(tvOS)
private enum SWCStatusBarStyle {
  case lightContent
}
#endif

private struct StatusBarState {
  let hidden: Bool
  #if os(iOS)
  let style: UIStatusBarStyle
  #else
  let style: SWCStatusBarStyle
  #endif
  
  static var defaultStatusBar: StatusBarState {
    return StatusBarState(hidden: false, style: .lightContent)
  }
}

private extension UIWindow {
  var currentStatusBarState: StatusBarState {
    if let rootViewController = self.rootViewController {
      let topMostViewController = rootViewController.findTopMostController()
      #if os(iOS)
      let viewControllerForStatusBarHidden = topMostViewController.childForStatusBarHidden ?? topMostViewController
      let viewControllerForStatusBarStyle = topMostViewController.childForStatusBarStyle ?? topMostViewController
      return StatusBarState(hidden: viewControllerForStatusBarHidden.prefersStatusBarHidden,
                            style: viewControllerForStatusBarStyle.preferredStatusBarStyle)
      #else
      return StatusBarState(hidden: true,
                            style: .lightContent)
      #endif
    }
    else {
      return StatusBarState.defaultStatusBar
    }
  }
}

private extension UIViewController {
  func findTopMostController() -> UIViewController {
    var topController: UIViewController = self
    while let presentedViewController = topController.presentedViewController {
      topController = presentedViewController
    }
    return topController
  }
}
