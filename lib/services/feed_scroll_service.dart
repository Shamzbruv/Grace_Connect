import 'dart:async';

class FeedScrollService {
  FeedScrollService._();

  static final StreamController<void> _controller =
      StreamController<void>.broadcast();

  static Stream<void> get scrollToTopRequests => _controller.stream;

  static void requestScrollToTop() {
    if (!_controller.isClosed) _controller.add(null);
  }
}
