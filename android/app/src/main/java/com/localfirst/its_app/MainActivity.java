package com.localfirst.its_app;

import android.content.Intent;
import androidx.annotation.NonNull;
import io.flutter.embedding.android.FlutterActivity;
import io.flutter.embedding.engine.FlutterEngine;
import io.flutter.plugin.common.MethodChannel;

public class MainActivity extends FlutterActivity {
  private static final String CHANNEL = "com.localfirst.its_app/share";
  private MethodChannel shareChannel;
  private String pendingSharedText;

  @Override
  public void configureFlutterEngine(@NonNull FlutterEngine flutterEngine) {
    super.configureFlutterEngine(flutterEngine);
    pendingSharedText = sharedText(getIntent());
    shareChannel = new MethodChannel(flutterEngine.getDartExecutor().getBinaryMessenger(), CHANNEL);
    shareChannel.setMethodCallHandler((call, result) -> {
      if (call.method.equals("getInitialSharedText")) {
        result.success(pendingSharedText);
        pendingSharedText = null;
      } else {
        result.notImplemented();
      }
    });
  }

  @Override
  protected void onNewIntent(@NonNull Intent intent) {
    super.onNewIntent(intent);
    setIntent(intent);
    String text = sharedText(intent);
    if (text != null && shareChannel != null) {
      shareChannel.invokeMethod("sharedText", text);
    }
  }

  private String sharedText(Intent intent) {
    if (intent == null || !Intent.ACTION_SEND.equals(intent.getAction())) return null;
    CharSequence value = intent.getCharSequenceExtra(Intent.EXTRA_TEXT);
    return value == null ? null : value.toString();
  }
}
