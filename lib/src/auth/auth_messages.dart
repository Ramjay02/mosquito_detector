String authMessage(String? code, {int? retryAfter}) {
  switch (code) {
    case 'invalid_credentials':
      return 'Invalid e-mail or password.';
    case 'email_taken':
      return 'An account with this e-mail already exists. Try signing in.';
    case 'invalid_code':
      return 'That code is not valid. Check it or request a new one.';
    case 'code_expired':
      return 'That code has expired. Request a new one.';
    case 'too_many_attempts':
      return 'Too many wrong codes. Request a new code.';
    case 'resend_too_soon':
    case 'rate_limited':
      return 'Please wait ${retryAfter ?? 60} seconds before trying again.';
    case 'mail_unavailable':
      return 'We could not send the e-mail right now. Please try again later.';
    case 'account_pending':
      return 'Your account is waiting for administrator approval.';
    case 'account_disabled':
      return 'Your account has been disabled. Please contact the administrator.';
    case 'network':
      return 'No internet connection.';
    default:
      return 'Something went wrong. Please try again.';
  }
}
