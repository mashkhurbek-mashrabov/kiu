import 'package:flutter/widgets.dart';
import 'package:webview_flutter_platform_interface/webview_flutter_platform_interface.dart';

/// Scripts the shell injected, newest last. Tests clear it in setUp.
final List<String> injectedScripts = <String>[];

/// URLs the shell asked the WebView to load, newest last. Tests clear it in
/// setUp.
final List<String> loadedUrls = <String>[];

/// Drives the shell's `onPageStarted` so a test can put the WebView on a page
/// the way a real navigation would, e.g. a link out to the exam platform.
PageEventCallback? navigateTo;

/// Drives the shell's `onPageFinished`, the hook that injects the page
/// scripts. Tests clear it in setUp.
PageEventCallback? finishPage;

/// Posts a message to the shell's `KiuBridge` channel, standing in for the
/// injected JavaScript. Tests clear it in setUp.
void Function(String message)? postToBridge;

/// Number of times the shell asked the WebView to reload. Tests clear it in
/// setUp.
int reloadCount = 0;

/// Whether the fake reports history behind the current page, which is what
/// enables the bar's back action. Tests clear it in setUp.
bool canGoBackResult = false;

/// Number of times the shell asked the WebView to go back. Tests clear it in
/// setUp.
int goBackCount = 0;

class FakeWebViewPlatform extends WebViewPlatform {
  @override
  PlatformWebViewController createPlatformWebViewController(
    PlatformWebViewControllerCreationParams params,
  ) => _FakeController(params);

  @override
  PlatformNavigationDelegate createPlatformNavigationDelegate(
    PlatformNavigationDelegateCreationParams params,
  ) => _FakeNavigationDelegate(params);

  @override
  PlatformWebViewWidget createPlatformWebViewWidget(
    PlatformWebViewWidgetCreationParams params,
  ) => _FakeWebViewWidget(params);
}

class _FakeController extends PlatformWebViewController {
  _FakeController(super.params) : super.implementation();

  @override
  Future<void> setJavaScriptMode(JavaScriptMode javaScriptMode) async {}

  @override
  Future<void> setBackgroundColor(Color color) async {}

  @override
  Future<void> addJavaScriptChannel(
    JavaScriptChannelParams javaScriptChannelParams,
  ) async => postToBridge = (message) => javaScriptChannelParams
      .onMessageReceived(JavaScriptMessage(message: message));

  @override
  Future<void> setPlatformNavigationDelegate(
    PlatformNavigationDelegate handler,
  ) async {}

  @override
  Future<void> loadRequest(LoadRequestParams params) async =>
      loadedUrls.add(params.uri.toString());

  @override
  Future<void> runJavaScript(String javaScript) async =>
      injectedScripts.add(javaScript);

  @override
  Future<void> reload() async => reloadCount++;

  @override
  Future<bool> canGoBack() async => canGoBackResult;

  @override
  Future<void> goBack() async => goBackCount++;

  @override
  Future<bool> canGoForward() async => false;

  // The base implementation throws UnimplementedError rather than returning
  // null, so any test that reaches a sync needs this stubbed.
  @override
  Future<String?> getUserAgent() async => 'FakeUserAgent';
}

class _FakeNavigationDelegate extends PlatformNavigationDelegate {
  _FakeNavigationDelegate(super.params) : super.implementation();

  @override
  Future<void> setOnNavigationRequest(
    NavigationRequestCallback onNavigationRequest,
  ) async {}

  @override
  Future<void> setOnPageStarted(PageEventCallback onPageStarted) async =>
      navigateTo = onPageStarted;

  @override
  Future<void> setOnPageFinished(PageEventCallback onPageFinished) async =>
      finishPage = onPageFinished;

  @override
  Future<void> setOnProgress(ProgressCallback onProgress) async {}

  @override
  Future<void> setOnWebResourceError(
    WebResourceErrorCallback onWebResourceError,
  ) async {}

  @override
  Future<void> setOnUrlChange(UrlChangeCallback onUrlChange) async {}
}

class _FakeWebViewWidget extends PlatformWebViewWidget {
  _FakeWebViewWidget(super.params) : super.implementation();

  @override
  Widget build(BuildContext context) => const SizedBox.expand();
}
