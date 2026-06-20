import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';

class EmailService {
  static const String _fromEmail = String.fromEnvironment(
    'RESEND_FROM_EMAIL',
    defaultValue: 'Grace Connect <onboarding@resend.dev>',
  );
  static const String supportInbox = 'shamzbiz1@gmail.com';
  static const String _resendApiKey = 're_aKtyyYHD_6QCTGajCE5BC1RPmZbYUkodV';
  static const String _apiUrl = 'https://api.resend.com/emails';

  /// Core method to send an email via Resend API
  Future<void> sendEmail({
    required List<String> to,
    required String subject,
    required String htmlBody,
    String? from,
  }) async {
    try {
      final response = await http.post(
        Uri.parse(_apiUrl),
        headers: {
          'Authorization': 'Bearer $_resendApiKey',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'from': from ?? _fromEmail,
          'to': to,
          'subject': subject,
          'html': htmlBody,
        }),
      );

      if (response.statusCode >= 200 && response.statusCode < 300) {
        debugPrint('Email sent successfully: ${response.body}');
      } else {
        throw Exception(_formatResendError(response));
      }
    } catch (e) {
      debugPrint('Error sending email: $e');
      throw Exception(e.toString().replaceFirst('Exception: ', ''));
    }
  }

  String _formatResendError(http.Response response) {
    var message = response.body;
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is Map<String, dynamic>) {
        message = decoded['message']?.toString() ?? response.body;
      }
    } catch (_) {
      // Keep the raw body when Resend returns non-JSON output.
    }

    if (response.statusCode == 403 &&
        message.toLowerCase().contains('domain is not verified')) {
      return 'Resend rejected the sender domain. Verify the sender domain in Resend or build with --dart-define=RESEND_FROM_EMAIL using a verified sender.';
    }

    return 'Failed to send email. Status Code: ${response.statusCode}, Body: $message';
  }

  String _escape(String value) => const HtmlEscape().convert(value);

  /// Sends a report from the Help/Support screen
  Future<void> sendSupportReportEmail({
    required String reporterEmail,
    required String issueType,
    required String summary,
    required String description,
    required String ticketId,
  }) async {
    final htmlBody = '''
      <h2>New Support Ticket: ${_escape(ticketId)}</h2>
      <p><strong>Reporter:</strong> ${_escape(reporterEmail)}</p>
      <p><strong>Issue Type:</strong> ${_escape(issueType)}</p>
      <p><strong>Summary:</strong> ${_escape(summary)}</p>
      <p><strong>Description:</strong></p>
      <p>${_escape(description).replaceAll('\n', '<br>')}</p>
    ''';

    await sendEmail(
      to: [supportInbox],
      subject: 'New Support Ticket: $summary',
      htmlBody: htmlBody,
    );
  }

  Future<void> sendBetaFeedbackEmail({
    required String reporterEmail,
    required String type,
    required String message,
    required String contactEmail,
    required String churchId,
    required String userId,
  }) async {
    final htmlBody = '''
      <h2>New Grace Connect Beta Feedback</h2>
      <p><strong>Reporter:</strong> ${_escape(reporterEmail)}</p>
      <p><strong>Contact Email:</strong> ${_escape(contactEmail.isEmpty ? 'Not provided' : contactEmail)}</p>
      <p><strong>User ID:</strong> ${_escape(userId.isEmpty ? 'Unknown' : userId)}</p>
      <p><strong>Church ID:</strong> ${_escape(churchId.isEmpty ? 'Unknown' : churchId)}</p>
      <p><strong>Type:</strong> ${_escape(type)}</p>
      <p><strong>Message:</strong></p>
      <p>${_escape(message).replaceAll('\n', '<br>')}</p>
    ''';

    await sendEmail(
      to: [supportInbox],
      subject: 'Grace Connect Beta Feedback: $type',
      htmlBody: htmlBody,
    );
  }

  /// Sends a welcome email to new members
  Future<void> sendMemberWelcomeEmail({
    required String toEmail,
    required String name,
    required String churchName,
  }) async {
    final htmlBody = '''
      <h2>Welcome to Grace Connect, ${_escape(name)}!</h2>
      <p>We are excited to have you join <strong>${_escape(churchName)}</strong> on Grace Connect.</p>
      <p>You can now log in and start connecting with your church community.</p>
      <br>
      <p>Blessings,</p>
      <p>The Grace Connect Team</p>
    ''';

    await sendEmail(
      to: [toEmail],
      subject: 'Welcome to Grace Connect!',
      htmlBody: htmlBody,
    );
  }

  /// Sends a welcome email to new church admins
  Future<void> sendChurchWelcomeEmail({
    required String toEmail,
    required String adminName,
    required String churchName,
  }) async {
    final htmlBody = '''
      <h2>Welcome, ${_escape(adminName)}!</h2>
      <p>Thank you for registering <strong>${_escape(churchName)}</strong> on Grace Connect.</p>
      <p>Your church account is now ready to be set up. You can log in and start configuring your dashboard.</p>
      <br>
      <p>Blessings,</p>
      <p>The Grace Connect Team</p>
    ''';

    await sendEmail(
      to: [toEmail],
      subject: 'Welcome to Grace Connect!',
      htmlBody: htmlBody,
    );
  }

  /// Sends an on-demand update/blast to users
  Future<void> sendUpdateEmail({
    required List<String> toEmails,
    required String subject,
    required String htmlBody,
  }) async {
    final uniqueEmails = toEmails
        .map((email) => email.trim())
        .where((email) => email.isNotEmpty)
        .toSet()
        .toList();

    for (final email in uniqueEmails) {
      await sendEmail(
        to: [email],
        subject: subject,
        htmlBody: htmlBody,
      );
    }
  }

  /// Sends an invitation email to a new member
  Future<void> sendInviteEmail({
    required String toEmail,
    required String churchName,
    required String adminName,
  }) async {
    final htmlBody = '''
      <h2>You're invited to join ${_escape(churchName)} on GraceConnect!</h2>
      <p>${_escape(adminName)} has invited you to join your church's private community app.</p>
      <p><strong>Next Steps:</strong></p>
      <ol>
        <li>Download the GraceConnect app from the App Store or Google Play.</li>
        <li>Create an account using this email address (${_escape(toEmail)}).</li>
        <li>Select <strong>${_escape(churchName)}</strong> during registration.</li>
      </ol>
      <br>
      <p>We look forward to connecting with you!</p>
      <p>Blessings,</p>
      <p>The Grace Connect Team</p>
    ''';

    await sendEmail(
      to: [toEmail],
      subject: 'You are invited to join $churchName on GraceConnect!',
      htmlBody: htmlBody,
    );
  }

  /// Sends a custom email verification link using Resend
  Future<void> sendCustomVerificationEmail({
    required String toEmail,
    required String name,
    required String verificationLink,
  }) async {
    final htmlBody = '''
      <div style="font-family: Arial, sans-serif; max-width: 600px; margin: 0 auto; color: #333;">
        <h2>Verify your email for Grace Connect</h2>
        <p>Hi ${_escape(name)},</p>
        <p>Thank you for signing up for Grace Connect! We're excited to have you.</p>
        <p>Please verify your email address by clicking the button below:</p>
        <div style="text-align: center; margin: 30px 0;">
          <a href="${_escape(verificationLink)}" style="background-color: #4CAF50; color: white; padding: 14px 28px; text-decoration: none; border-radius: 6px; font-weight: bold; display: inline-block;">Verify Email</a>
        </div>
        <p style="color: #666; font-size: 14px;">If you didn't create an account with Grace Connect, you can safely ignore this email.</p>
        <br>
        <p>Blessings,</p>
        <p>The Grace Connect Team</p>
      </div>
    ''';

    await sendEmail(
      to: [toEmail],
      subject: 'Verify your email for Grace Connect',
      htmlBody: htmlBody,
    );
  }

  /// Sends a custom password reset link using Resend
  Future<void> sendCustomPasswordResetEmail({
    required String toEmail,
    required String resetLink,
  }) async {
    final htmlBody = '''
      <div style="font-family: Arial, sans-serif; max-width: 600px; margin: 0 auto; color: #333;">
        <h2>Reset your Grace Connect password</h2>
        <p>Hello,</p>
        <p>We received a request to reset the password for your Grace Connect account.</p>
        <p>You can reset your password by clicking the button below:</p>
        <div style="text-align: center; margin: 30px 0;">
          <a href="${_escape(resetLink)}" style="background-color: #2196F3; color: white; padding: 14px 28px; text-decoration: none; border-radius: 6px; font-weight: bold; display: inline-block;">Reset Password</a>
        </div>
        <p style="color: #666; font-size: 14px;">If you didn't request a password reset, you can safely ignore this email. Your current password will remain unchanged.</p>
        <br>
        <p>Blessings,</p>
        <p>The Grace Connect Team</p>
      </div>
    ''';

    await sendEmail(
      to: [toEmail],
      subject: 'Reset your Grace Connect password',
      htmlBody: htmlBody,
    );
  }
}
