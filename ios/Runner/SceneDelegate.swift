import Flutter
import UIKit

/// Hides app content from the iOS app-switcher snapshot by covering the
/// window whenever the scene stops being active. (iOS offers no universal
/// screenshot-blocking API; this only protects the switcher preview.)
/// UNVERIFIED ON DEVICE — test on a Mac/iPhone (docs/IOS_MAC.md).
class SceneDelegate: FlutterSceneDelegate {
  private var privacyCover: UIView?

  override func sceneWillResignActive(_ scene: UIScene) {
    super.sceneWillResignActive(scene)
    guard privacyCover == nil, let window = (scene as? UIWindowScene)?.windows.first else { return }
    let cover = UIView(frame: window.bounds)
    cover.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    cover.backgroundColor = UIColor(red: 0x15 / 255, green: 0x65 / 255, blue: 0xC0 / 255, alpha: 1)
    let label = UILabel()
    label.text = "Daily Expense Tracker"
    label.textColor = .white
    label.font = .boldSystemFont(ofSize: 22)
    label.translatesAutoresizingMaskIntoConstraints = false
    cover.addSubview(label)
    NSLayoutConstraint.activate([
      label.centerXAnchor.constraint(equalTo: cover.centerXAnchor),
      label.centerYAnchor.constraint(equalTo: cover.centerYAnchor),
    ])
    window.addSubview(cover)
    privacyCover = cover
  }

  override func sceneDidBecomeActive(_ scene: UIScene) {
    super.sceneDidBecomeActive(scene)
    privacyCover?.removeFromSuperview()
    privacyCover = nil
  }
}
