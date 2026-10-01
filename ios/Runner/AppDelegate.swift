import Flutter
import AVFoundation
import GoogleMaps
import UIKit
import UserNotifications
import native_geofence

@main
@objc class AppDelegate: FlutterAppDelegate {
  private let videoExporter = GraceVideoExporter()
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    UNUserNotificationCenter.current().delegate = self as? UNUserNotificationCenterDelegate
    // Region events can launch a headless Flutter engine while the app is
    // closed. Register its plugins before native_geofence is initialized.
    NativeGeofencePlugin.setPluginRegistrantCallback { registry in
      GeneratedPluginRegistrant.register(with: registry)
    }
    if let apiKey = Bundle.main.object(forInfoDictionaryKey: "GoogleMapsApiKey") as? String,
       !apiKey.isEmpty,
       !apiKey.hasPrefix("$(") {
      GMSServices.provideAPIKey(apiKey)
    }
    GeneratedPluginRegistrant.register(with: self)
    if let controller = window?.rootViewController as? FlutterViewController {
      FlutterMethodChannel(name: "love.graceconnect/media_export", binaryMessenger: controller.binaryMessenger)
        .setMethodCallHandler { [weak self] call, result in
          switch call.method {
          case "watermark":
            let input = (call.arguments as? [String: Any])?["input"] as? String
            self?.videoExporter.export(input: input, result: result)
          case "cancel": self?.videoExporter.cancel(); result(nil)
          default: result(FlutterMethodNotImplemented)
          }
        }
    }
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}

// AVFoundation renders the watermark into the exported MP4 itself. Signed
// source URLs never leave Flutter and no external video-processing service is used.
private final class GraceVideoExporter {
  private var session: AVAssetExportSession?
  private var pending: FlutterResult?
  private var output: URL?
  private var generation = UUID()

  func export(input: String?, result: @escaping FlutterResult) {
    guard pending == nil else {
      result(FlutterError(code: "busy", message: "A video is already being prepared.", details: nil)); return
    }
    guard let input = input else {
      result(FlutterError(code: "invalid_input", message: "Missing video.", details: nil)); return
    }
    let source = URL(fileURLWithPath: input).standardizedFileURL.resolvingSymlinksInPath()
    let cache = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
      .appendingPathComponent("grace_exports").standardizedFileURL.resolvingSymlinksInPath()
    guard source.deletingLastPathComponent() == cache, FileManager.default.fileExists(atPath: source.path) else {
      result(FlutterError(code: "invalid_input", message: "Invalid export input.", details: nil)); return
    }
    let asset = AVURLAsset(url: source)
    let requestID = UUID()
    generation = requestID
    pending = result
    asset.loadValuesAsynchronously(forKeys: ["tracks", "duration"]) { [weak self] in
      DispatchQueue.main.async {
        guard let self = self, self.pending != nil, self.generation == requestID else { return }
        var error: NSError?
        guard asset.statusOfValue(forKey: "tracks", error: &error) == .loaded,
              let track = asset.tracks(withMediaType: .video).first else {
          self.fail("This video could not be read."); return
        }
        let transform = track.preferredTransform
        let transformed = CGRect(origin: .zero, size: track.naturalSize).applying(transform)
        let size = CGSize(width: abs(transformed.width), height: abs(transformed.height))
        guard size.width > 0, size.height > 0 else { self.fail("Invalid video size."); return }
        let composition = AVMutableVideoComposition()
        composition.renderSize = size
        composition.frameDuration = CMTime(value: 1, timescale: CMTimeScale(min(60, max(24, Int(track.nominalFrameRate.rounded())))))
        let instruction = AVMutableVideoCompositionInstruction()
        instruction.timeRange = CMTimeRange(start: .zero, duration: asset.duration)
        let layerInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: track)
        layerInstruction.setTransform(transform.concatenating(CGAffineTransform(translationX: -transformed.minX, y: -transformed.minY)), at: .zero)
        instruction.layerInstructions = [layerInstruction]
        composition.instructions = [instruction]
        let videoLayer = CALayer()
        videoLayer.frame = CGRect(origin: .zero, size: size)
        let parent = CALayer()
        parent.frame = videoLayer.frame
        parent.addSublayer(videoLayer)
        let fontSize = max(14, min(size.width, size.height) * 0.032)
        let label = CATextLayer()
        label.string = NSAttributedString(string: " Grace Connect ", attributes: [
          .font: UIFont.boldSystemFont(ofSize: fontSize), .foregroundColor: UIColor.white])
        label.contentsScale = 2
        label.backgroundColor = UIColor.black.withAlphaComponent(0.6).cgColor
        label.cornerRadius = fontSize * 0.15
        label.frame = CGRect(x: size.width * 0.03, y: size.height * 0.03,
          width: fontSize * 8.8, height: fontSize * 1.5)
        parent.addSublayer(label)
        composition.animationTool = AVVideoCompositionCoreAnimationTool(postProcessingAsVideoLayer: videoLayer, in: parent)
        let target = source.deletingPathExtension().appendingPathExtension("watermarked.mp4")
        try? FileManager.default.removeItem(at: target)
        guard let exporter = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetHighestQuality) else {
          self.fail("Video export is unavailable."); return
        }
        self.output = target
        self.session = exporter
        exporter.outputURL = target
        exporter.outputFileType = .mp4
        exporter.shouldOptimizeForNetworkUse = true
        exporter.videoComposition = composition
        exporter.exportAsynchronously { [weak self] in
          DispatchQueue.main.async {
            guard let self = self, self.session === exporter else { return }
            if exporter.status == .completed {
              let reply = self.pending
              self.pending = nil; self.session = nil; self.output = nil
              reply?(target.path)
            } else { self.fail("This video could not be prepared. Please try again.") }
          }
        }
      }
    }
  }

  private func fail(_ message: String) {
    generation = UUID()
    let reply = pending
    pending = nil
    session?.cancelExport(); session = nil
    if let output = output { try? FileManager.default.removeItem(at: output) }
    output = nil
    reply?(FlutterError(code: "export_failed", message: message, details: nil))
  }
  func cancel() { fail("Video preparation cancelled.") }
}
