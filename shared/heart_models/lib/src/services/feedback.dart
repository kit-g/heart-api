import 'dart:typed_data';

abstract interface class FeedbackService {
  Future<bool> submitFeedback({String? feedback, required String mimeType, Uint8List? screenshot});
}
