import 'package:flutter/foundation.dart';

class StudioSession {
  String statusMessage = 'Simulator Ready';
  bool isStatusError = false;
  bool disposed = false;
  VoidCallback requestFrame = () {};
  VoidCallback bindFrameStreamer = () {};

  void setStatus(String message, {bool isError = false}) {
    statusMessage = message;
    isStatusError = isError;
  }
}

abstract class StudioSubViewModel extends ChangeNotifier {
  final StudioSession session;
  bool _disposed = false;

  StudioSubViewModel(this.session);

  void notify({bool markCanvasDirty = true}) {
    if (_disposed || session.disposed) return;
    if (markCanvasDirty) session.requestFrame();
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
