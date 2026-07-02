package net.jonhanson.flutter_native_splash;

import androidx.annotation.NonNull;
import io.flutter.embedding.engine.plugins.FlutterPlugin;

/**
 * No-op runtime shim for flutter_native_splash.
 *
 * The package is used as a build-time splash asset generator, but its current
 * Android plugin metadata registers a class that is not shipped in the package.
 * Keeping this class lets Flutter's generated registrant compile cleanly.
 */
public final class FlutterNativeSplashPlugin implements FlutterPlugin {
    @Override
    public void onAttachedToEngine(@NonNull FlutterPluginBinding binding) {
        // Build-time package only; no runtime behavior is required.
    }

    @Override
    public void onDetachedFromEngine(@NonNull FlutterPluginBinding binding) {
        // Build-time package only; no runtime behavior is required.
    }
}
