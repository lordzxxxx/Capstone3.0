/// Cloud Functions Configuration
/// Update these URLs with your actual Firebase project ID if different
class CloudFunctionsConfig {
  static const String projectId = 'capstone-c98f9';
  static const String region = 'us-central1';
  
  static const String sendPasswordResetUrl =
    'https://us-central1-capstone-c98f9.cloudfunctions.net/sendPasswordResetEmail';
  
  static const String verifyResetCodeUrl = 
    'https://us-central1-capstone-c98f9.cloudfunctions.net/verifyResetCode';
  
  static const String completePasswordResetUrl = 
    'https://us-central1-capstone-c98f9.cloudfunctions.net/completePasswordReset';

  /// Get Cloud Function URL by name
  static String getUrl(String functionName) {
    switch (functionName) {
      case 'sendPasswordReset':
        return sendPasswordResetUrl;
      case 'verifyResetCode':
        return verifyResetCodeUrl;
      case 'completePasswordReset':
        return completePasswordResetUrl;
      default:
        throw Exception('Unknown function: $functionName');
    }
  }
}
