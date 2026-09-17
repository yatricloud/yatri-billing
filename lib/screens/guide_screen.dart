import 'package:flutter/material.dart';

// ─── Data model for each guide section/folder ────────────────────────────────

class _GuideStep {
  final String title;
  final String detail;
  const _GuideStep(this.title, this.detail);
}

class _GuideSection {
  final IconData icon;
  final String title;
  final String subtitle;
  
  final List<_GuideStep> steps;
  final String? redirectLabel;
  final int? redirectIndex;
  bool isExpanded = false;

  _GuideSection({
    required this.icon,
    required this.title,
    required this.subtitle,
    
    required this.steps,
    this.redirectLabel,
    this.redirectIndex,
  }) : isExpanded = false;
}

// ─── Screen ──────────────────────────────────────────────────────────────────

class GuideScreen extends StatefulWidget {
  final Future<void> Function(int index)? onNavigate;

  const GuideScreen({super.key, this.onNavigate});

  @override
  State<GuideScreen> createState() => _GuideScreenState();
}

class _GuideScreenState extends State<GuideScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _heroController;
  late Animation<double> _heroFade;

  final List<_GuideSection> _sections = [
    _GuideSection(
      icon: Icons.business,
      title: 'Getting Started',
      subtitle: 'Set up your business profile before anything else',
      
      redirectLabel: 'Open Settings',
      redirectIndex: 8,
      steps: const [
        _GuideStep(
          'Business Name & Logo',
          'Go to Settings → Business Details. Fill in your business name, address, phone, and email. Upload your logo — it appears on every invoice and PDF.',
        ),
        _GuideStep(
          'Business Type',
          'Choose whether you sell Products, Services, or Both. This controls what fields appear on your invoices.',
        ),
        _GuideStep(
          'Bank & UPI Details',
          'Add your bank account number, IFSC code, and UPI ID in Settings → Payment Details. Customers will see these on invoices so they can pay you directly.',
        ),
        _GuideStep(
          'Invoice Numbering',
          'Customize your invoice prefix (e.g. INV-, 2024-) and starting number in Settings → Invoice Settings. All new invoices will auto-number from there.',
        ),
        _GuideStep(
          'Tax Configuration',
          'Set up GST, VAT, or any custom tax rate in Settings → Tax Settings. These can also be applied per-product later.',
        ),
      ],
    ),
    _GuideSection(
      icon: Icons.people,
      title: 'Client Management',
      subtitle: 'Save customer details once, use them on every invoice',
      
      redirectLabel: 'Manage Customers',
      redirectIndex: 5,
      steps: const [
        _GuideStep(
          'Add a New Customer',
          'Click the + Add Customer button. Fill in the Name, Email, Phone, and both Billing and Shipping addresses.',
        ),
        _GuideStep(
          'Customer Profile',
          'Each customer gets their own profile page. You can view all their past invoices, outstanding balances, and contact history in one place.',
        ),
        _GuideStep(
          'Quick-Select on Invoice',
          'When creating an invoice, click the Customer field and start typing — your saved customers appear instantly. Select one and all their details auto-fill.',
        ),
        _GuideStep(
          'Edit or Delete',
          'Open any customer and click the Edit button to update their details. Changes apply to future invoices but do not alter past ones.',
        ),
      ],
    ),
    _GuideSection(
      icon: Icons.inventory_2,
      title: 'Products & Services',
      subtitle: 'Build your catalog so adding line items is instant',
      
      redirectLabel: 'Manage Products',
      redirectIndex: 6,
      steps: const [
        _GuideStep(
          'Add a Product or Service',
          'Click + Add Item. Enter the Name, Description, Unit (e.g. hrs, pcs, kg), and Unit Price. Enable Tax if applicable.',
        ),
        _GuideStep(
          'Stock Tracking',
          'For physical goods, enable Track Stock and enter the current quantity. The app will warn you when stock runs low.',
        ),
        _GuideStep(
          'Quick-Select on Invoice',
          'When creating an invoice, type in the Item Search box. All saved products and services appear — select one to auto-fill price and tax.',
        ),
        _GuideStep(
          'Bulk Pricing',
          'Set different prices per quantity range. For example: 100 each for 1-10 units, 90 each for 11+ units.',
        ),
      ],
    ),
    _GuideSection(
      icon: Icons.receipt_long,
      title: 'Creating Invoices',
      subtitle: 'Generate professional invoices in under a minute',
      
      redirectLabel: 'Create Invoice',
      redirectIndex: 1,
      steps: const [
        _GuideStep(
          'Start a New Invoice',
          'Click + New Invoice in the sidebar. Select your customer, then add one or more items from your catalog.',
        ),
        _GuideStep(
          'Add Line Items',
          'Click + Add Item for each product/service. You can adjust quantity and unit price per line. Taxes and totals calculate automatically.',
        ),
        _GuideStep(
          'Discounts & Shipping',
          'Scroll down to add a flat or percentage-based discount. Add shipping charges if needed — both affect the final total.',
        ),
        _GuideStep(
          'Due Date & Notes',
          'Set a payment due date for the invoice. Add any custom notes at the bottom (e.g. "Thank you for your business!").',
        ),
        _GuideStep(
          'Save & Share',
          'Click Save Invoice. You can then Download as PDF, Print, or Email it directly to your customer from the invoice detail screen.',
        ),
        _GuideStep(
          'Quotations',
          'Need to send an estimate? Use the same form but click Save as Quotation instead. Quotations can be converted to invoices later with one click.',
        ),
      ],
    ),
    _GuideSection(
      icon: Icons.assignment,
      title: 'Invoice Management',
      subtitle: 'View, search, filter, and take action on all invoices',
      
      redirectLabel: 'View Invoices',
      redirectIndex: 2,
      steps: const [
        _GuideStep(
          'Invoice List',
          'The Invoices screen shows all your invoices with their status (Draft, Sent, Paid, Overdue). Use the tabs at the top to switch between All, Unpaid, and Paid.',
        ),
        _GuideStep(
          'Search & Filter',
          'Use the Search bar to find invoices by customer name, invoice number, or amount. Use the Filter button to filter by date range or status.',
        ),
        _GuideStep(
          'Mark as Paid',
          'Open any invoice and click Mark as Paid. The invoice status changes instantly and it moves to your paid history.',
        ),
        _GuideStep(
          'Duplicate an Invoice',
          'Open an invoice and click More Options, then Duplicate. A copy is created which you can edit and send to another customer or period.',
        ),
        _GuideStep(
          'Send Reminder',
          'For overdue invoices, click Send Reminder. A payment reminder email is sent to the customer automatically.',
        ),
      ],
    ),
    _GuideSection(
      icon: Icons.bar_chart,
      title: 'Reports & Analytics',
      subtitle: 'Understand your revenue and business health at a glance',
      
      redirectLabel: 'View Reports',
      redirectIndex: 7,
      steps: const [
        _GuideStep(
          'Revenue Overview',
          'The Reports screen shows your total revenue, number of invoices, and average invoice value for any selected date range.',
        ),
        _GuideStep(
          'Revenue Chart',
          'A visual bar chart shows your revenue by month. Hover over any bar to see the exact figure. Switch between monthly, quarterly, and yearly views.',
        ),
        _GuideStep(
          'Top Customers',
          'See which customers have spent the most. This helps you focus attention on your most valuable clients.',
        ),
        _GuideStep(
          'Outstanding Amounts',
          'The Outstanding tab shows all unpaid and overdue invoices, their amounts, and how many days past due they are.',
        ),
      ],
    ),
    _GuideSection(
      icon: Icons.save,
      title: 'Backup & Data',
      subtitle: 'Export your data and keep it safe across devices',
      
      steps: const [
        _GuideStep(
          'Export to Excel',
          'Go to Settings → Backup. Click Export to Excel to download all your invoices, customers, and products as a spreadsheet (.xlsx).',
        ),
        _GuideStep(
          'Export to JSON',
          'Click Export to JSON to create a full backup file of all your data. Save this file somewhere safe (Google Drive, iCloud, etc.).',
        ),
        _GuideStep(
          'Import / Restore',
          'To restore your data on a new device, open the Backup screen and click Import. Select your previously exported JSON file and all data will be restored.',
        ),
        _GuideStep(
          'PDF Archive',
          'All generated PDFs are stored locally. You can share or re-download any invoice PDF from the Invoice detail screen at any time.',
        ),
      ],
    ),
    _GuideSection(
      icon: Icons.settings,
      title: 'Account & Settings',
      subtitle: 'Manage your profile, theme, and app preferences',
      
      redirectLabel: 'Open Settings',
      redirectIndex: 8,
      steps: const [
        _GuideStep(
          'Change Password',
          'Go to Settings → Account. Click Change Password, enter your current password, then set a new one.',
        ),
        _GuideStep(
          'Dark / Light Mode',
          'Click the moon or sun icon in the top bar (or in Settings → Appearance) to switch between dark and light themes.',
        ),
        _GuideStep(
          'PDF Appearance',
          'In Settings → PDF Settings, choose your invoice template, accent color, font, and whether to show/hide specific fields on the PDF.',
        ),
        _GuideStep(
          'Multi-User Access',
          'If you are on a team plan, go to Settings → Users to invite team members. Assign them roles (Admin or Viewer) to control what they can access.',
        ),
      ],
    ),
  ];

  @override
  void initState() {
    super.initState();
    _heroController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _heroFade = CurvedAnimation(parent: _heroController, curve: Curves.easeOut);
    _heroController.forward();
  }

  @override
  void dispose() {
    _heroController.dispose();
    super.dispose();
  }

  void _toggle(int index) {
    setState(() {
      _sections[index].isExpanded = !_sections[index].isExpanded;
    });
  }

  Future<void> _navigate(int index) async {
    if (widget.onNavigate != null) {
      await widget.onNavigate!(index);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      body: FadeTransition(
        opacity: _heroFade,
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: _HeroHeader(isDark: isDark, colorScheme: colorScheme),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 24, 16, 80),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) => _SectionCard(
                    section: _sections[index],
                    isDark: isDark,
                    colorScheme: colorScheme,
                    onToggle: () => _toggle(index),
                    onNavigate: _navigate,
                  ),
                  childCount: _sections.length,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Hero Header ─────────────────────────────────────────────────────────────

class _HeroHeader extends StatelessWidget {
  final bool isDark;
  final ColorScheme colorScheme;
  const _HeroHeader({required this.isDark, required this.colorScheme});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(24, 48, 24, 36),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : const Color(0xFF007CFF),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'User Guide',
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w800,
              color: Colors.white,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Everything you need to use the app — step by step',
            style: TextStyle(
              fontSize: 14,
              color: Colors.white.withValues(alpha: 0.8),
              height: 1.4,
            ),
          ),
          const SizedBox(height: 24),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
            ),
            child: Text(
              'Tap any section below to expand it. Use the highlighted buttons to jump directly to that part of the app.',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.9),
                fontSize: 13,
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}



// ─── Section Card ─────────────────────────────────────────────────────────────

class _SectionCard extends StatelessWidget {
  final _GuideSection section;
  final bool isDark;
  final ColorScheme colorScheme;
  final VoidCallback onToggle;
  final Future<void> Function(int) onNavigate;

  const _SectionCard({
    required this.section,
    required this.isDark,
    required this.colorScheme,
    required this.onToggle,
    required this.onNavigate,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
        decoration: BoxDecoration(
          color: isDark
              ? colorScheme.surfaceContainerLow
              : colorScheme.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: section.isExpanded
                ? const Color(0xFF007CFF).withValues(alpha: 0.5)
                : colorScheme.outlineVariant.withValues(alpha: 0.4),
            width: section.isExpanded ? 1.5 : 1,
          ),
          boxShadow: section.isExpanded
              ? [
                  BoxShadow(
                    color: const Color(0xFF007CFF).withValues(alpha: 0.12),
                    blurRadius: 16,
                    offset: const Offset(0, 4),
                  )
                ]
              : [],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            InkWell(
              onTap: onToggle,
              borderRadius: BorderRadius.circular(16),
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Row(
                  children: [
                    // Icon removed as requested
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            section.title,
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: colorScheme.onSurface,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            section.subtitle,
                            style: TextStyle(
                              fontSize: 12.5,
                              color: colorScheme.onSurfaceVariant,
                              height: 1.4,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    // Steps text removed as requested
                    AnimatedRotation(
                      turns: section.isExpanded ? 0.5 : 0,
                      duration: const Duration(milliseconds: 250),
                      child: Icon(
                        Icons.keyboard_arrow_down_rounded,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            AnimatedCrossFade(
              firstChild: const SizedBox(width: double.infinity, height: 0),
              secondChild: _SectionBody(
                section: section,
                isDark: isDark,
                colorScheme: colorScheme,
                onNavigate: onNavigate,
              ),
              crossFadeState: section.isExpanded
                  ? CrossFadeState.showSecond
                  : CrossFadeState.showFirst,
              duration: const Duration(milliseconds: 250),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Section Body ─────────────────────────────────────────────────────────────

class _SectionBody extends StatelessWidget {
  final _GuideSection section;
  final bool isDark;
  final ColorScheme colorScheme;
  final Future<void> Function(int) onNavigate;

  const _SectionBody({
    required this.section,
    required this.isDark,
    required this.colorScheme,
    required this.onNavigate,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18),
          child: Divider(color: const Color(0xFF007CFF).withValues(alpha: 0.25), height: 1),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 0),
          child: Column(
            children: List.generate(section.steps.length, (i) {
              final step = section.steps[i];
              final isLast = i == section.steps.length - 1;
              return _StepRow(
                stepNumber: i + 1,
                step: step,
                accentColor: const Color(0xFF007CFF),
                isDark: isDark,
                colorScheme: colorScheme,
                isLast: isLast,
              );
            }),
          ),
        ),
        if (section.redirectLabel != null && section.redirectIndex != null)
          _RedirectButton(
            label: section.redirectLabel!,
            isDark: isDark,
            onTap: () => onNavigate(section.redirectIndex!),
          ),
        const SizedBox(height: 8),
      ],
    );
  }
}

// ─── Step Row ─────────────────────────────────────────────────────────────────

class _StepRow extends StatelessWidget {
  final int stepNumber;
  final _GuideStep step;
  final Color accentColor;
  final bool isDark;
  final ColorScheme colorScheme;
  final bool isLast;

  const _StepRow({
    required this.stepNumber,
    required this.step,
    required this.accentColor,
    required this.isDark,
    required this.colorScheme,
    required this.isLast,
  });

  @override
  Widget build(BuildContext context) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 32,
            child: Column(
              children: [
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: accentColor,
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: Text(
                      '$stepNumber',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
                if (!isLast)
                  Expanded(
                    child: Container(
                      width: 2,
                      margin: const EdgeInsets.symmetric(vertical: 4),
                      color: accentColor.withValues(alpha: 0.2),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: isLast ? 8 : 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    step.title,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    step.detail,
                    style: TextStyle(
                      fontSize: 13.5,
                      height: 1.55,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Redirect Button ──────────────────────────────────────────────────────────

class _RedirectButton extends StatefulWidget {
  final String label;
  final bool isDark;
  final VoidCallback onTap;

  const _RedirectButton({
    required this.label,
    required this.isDark,
    required this.onTap,
  });

  @override
  State<_RedirectButton> createState() => _RedirectButtonState();
}

class _RedirectButtonState extends State<_RedirectButton> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    const Color brandColor = Color(0xFF007CFF);
    const Color hoverColor = Color(0xFF0066D6);

    // Ensure label never contains duplicate arrows
    final cleanLabel = widget.label.replaceAll('→', '').replaceAll('->', '').trim();

    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 8),
      child: MouseRegion(
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => setState(() => _isHovered = false),
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            decoration: BoxDecoration(
              color: _isHovered ? hoverColor : brandColor,
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: brandColor.withValues(alpha: _isHovered ? 0.45 : 0.3),
                  blurRadius: _isHovered ? 14 : 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  cleanLabel,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.2,
                  ),
                ),
                const SizedBox(width: 8),
                const Icon(
                  Icons.arrow_forward_rounded,
                  color: Colors.white,
                  size: 18,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
