import 'package:flutter/material.dart';
import 'package:invoiso/models/customer.dart';

/// Tapping the ⓘ icon shows a clean, minimal modal with the customer's full contact details.
class CustomerInfoButton extends StatelessWidget {
  final Customer customer;

  const CustomerInfoButton({super.key, required this.customer});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'View contact details',
      child: InkWell(
        onTap: () => _showDialog(context),
        borderRadius: BorderRadius.circular(4),
        child: const Padding(
          padding: EdgeInsets.symmetric(horizontal: 4, vertical: 2),
          child: Icon(Icons.info_outline, size: 14, color: Color(0xFF94A3B8)),
        ),
      ),
    );
  }

  void _showDialog(BuildContext context) {
    final c = customer;
    final hasAny = c.phone.isNotEmpty ||
        c.email.isNotEmpty ||
        c.address.isNotEmpty ||
        c.gstin.isNotEmpty;

    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: Color(0xFFE2E8F0)),
        ),
        child: SizedBox(
          width: 340,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Container(
                padding: const EdgeInsets.fromLTRB(20, 16, 12, 16),
                decoration: const BoxDecoration(
                  color: Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
                  border: Border(
                    bottom: BorderSide(color: Color(0xFFE2E8F0)),
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.person_outline,
                        color: Color(0xFF475569), size: 18),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        c.name,
                        style: const TextStyle(
                          color: Color(0xFF0F172A),
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close,
                          color: Color(0xFF64748B), size: 18),
                      onPressed: () => Navigator.pop(ctx),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                  ],
                ),
              ),

              // Contact details body
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (!hasAny)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 12),
                        child: Text(
                          'No contact details available.',
                          style: TextStyle(
                            color: Color(0xFF64748B),
                            fontSize: 13,
                          ),
                        ),
                      ),
                    if (c.phone.isNotEmpty)
                      _infoRow(Icons.phone_outlined, 'Phone', c.phone),
                    if (c.email.isNotEmpty)
                      _infoRow(Icons.email_outlined, 'Email', c.email),
                    if (c.address.isNotEmpty)
                      _infoRow(Icons.location_on_outlined, 'Address', c.address),
                    if (c.gstin.isNotEmpty)
                      _infoRow(Icons.badge_outlined, 'GSTIN', c.gstin),
                  ],
                ),
              ),

              // Close button
              Align(
                alignment: Alignment.centerRight,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(0, 4, 16, 14),
                  child: TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    style: TextButton.styleFrom(
                      foregroundColor: const Color(0xFF0F172A),
                      textStyle: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    child: const Text('Close'),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _infoRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: const Color(0xFFF1F5F9),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: Icon(icon, size: 14, color: const Color(0xFF475569)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 11,
                    color: Color(0xFF64748B),
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 13,
                    color: Color(0xFF0F172A),
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
