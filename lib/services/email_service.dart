import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class EmailService {
  static const String supportInbox = 'shamzbiz1@gmail.com';
  static const String _brandingMarker = 'data-grace-email="true"';

  /// Sends through the authenticated server mailer. Provider credentials must
  /// never be compiled into the Android or iOS application.
  Future<void> sendEmail({
    required List<String> to,
    required String subject,
    required String htmlBody,
  }) async {
    try {
      final emailHtml = htmlBody.contains(_brandingMarker)
          ? htmlBody
          : _brandHtmlBody(title: subject, htmlBody: htmlBody);
      final response = await Supabase.instance.client.functions.invoke(
        'grace-mailer',
        body: {
          'action': 'send-app-email',
          'to': to,
          'subject': subject,
          'htmlBody': emailHtml,
        },
      );
      final data = response.data;
      if (data is! Map || data['ok'] != true) {
        throw Exception(
          data is Map
              ? data['error']?.toString() ?? 'Email delivery was not confirmed.'
              : 'Email delivery was not confirmed.',
        );
      }
      debugPrint('Email delivered by the Grace Connect server mailer.');
    } catch (e) {
      debugPrint('Error sending email: $e');
      throw Exception(e.toString().replaceFirst('Exception: ', ''));
    }
  }

  String _escape(String value) => const HtmlEscape().convert(value);

  String _brandHtmlBody({
    required String title,
    required String htmlBody,
  }) {
    final safeTitle = _escape(title.trim().isEmpty ? 'Grace Connect' : title);
    return '''
      <!doctype html>
      <html>
        <body style="margin:0;padding:0;background:#f7f3ea;font-family:Arial,Helvetica,sans-serif;color:#263852;">
          <div $_brandingMarker style="display:none;max-height:0;overflow:hidden;opacity:0;">Grace Connect</div>
          <table role="presentation" width="100%" cellspacing="0" cellpadding="0" style="background:#f7f3ea;padding:32px 12px;">
            <tr>
              <td align="center">
                <table role="presentation" width="100%" cellspacing="0" cellpadding="0" style="max-width:640px;background:#ffffff;border-radius:20px;overflow:hidden;border:1px solid #eadcb6;box-shadow:0 14px 36px rgba(13,31,76,0.12);">
                  <tr>
                    <td style="background:#0d1f4c;padding:28px 32px;color:#ffffff;">
                      <div style="font-size:13px;font-weight:800;letter-spacing:.08em;text-transform:uppercase;color:#e5bd53;">Grace Connect</div>
                      <h1 style="margin:8px 0 0;font-size:28px;line-height:1.2;font-weight:800;">$safeTitle</h1>
                    </td>
                  </tr>
                  <tr>
                    <td style="padding:30px 32px;font-size:16px;line-height:1.65;color:#263852;">
                      $htmlBody
                    </td>
                  </tr>
                  <tr>
                    <td style="padding:20px 32px;background:#fbf8f0;border-top:1px solid #eadcb6;color:#69768b;font-size:13px;line-height:1.5;">
                      You are receiving this from Grace Connect because of activity in your church community.
                    </td>
                  </tr>
                </table>
              </td>
            </tr>
          </table>
        </body>
      </html>
    ''';
  }

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

    await sendEmail(
      to: uniqueEmails,
      subject: subject,
      htmlBody: htmlBody,
    );
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
