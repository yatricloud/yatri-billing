import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:intl/intl.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:invoiso/constants.dart';
import 'package:invoiso/providers/app_config_provider.dart';
import 'package:invoiso/providers/repositories.dart';
import 'package:invoiso/services/update_service.dart';
import 'package:invoiso/widgets/update_dialog.dart';
import 'package:invoiso/domain/invoice_calculator.dart';
import 'package:invoiso/models/invoice.dart';
import 'package:invoiso/models/product.dart';
import 'package:invoiso/screens/settings_screen.dart';
import 'package:invoiso/common.dart';
import 'package:invoiso/services/invoice_pdf_services.dart';
import 'package:invoiso/services/pdf_service.dart';
import 'package:invoiso/widgets/apply_payment_dialog.dart';
import 'package:invoiso/utils/session_manager.dart';
import 'package:invoiso/theme/app_typography.dart';
import 'package:invoiso/theme/coinbase_tokens.dart';
import 'package:invoiso/services/export_service.dart';

import 'package:invoiso/models/user.dart';
import 'package:invoiso/screens/customer_management_screen.dart';
import 'package:invoiso/database/database_helper.dart';
import 'package:invoiso/screens/create_invoice_screen.dart';
import 'package:invoiso/screens/product_management_screen.dart';
import 'package:invoiso/screens/invoice_management_screen.dart';
import 'package:invoiso/screens/login_screen.dart';
import 'package:invoiso/screens/reports_screen.dart';

// Dashboard Screen
class DashboardScreen extends ConsumerStatefulWidget {
  final User loggedInUser;

  const DashboardScreen(this.loggedInUser, {super.key});

  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen> {
  int _selectedIndex = 0;
  bool _sidebarExpanded = true;
  late User _currentUser;

  Invoice? invoiceToEdit;
  Invoice? _invoiceToClone;
  String _cloneType = 'Invoice';
  bool _hasUpdate = false;
  final InvoiceFormGuard _invoiceFormGuard = InvoiceFormGuard();
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  int _getBottomNavIndex() {
    switch (_selectedIndex) {
      case 0:
        return 0; // Dashboard
      case 2:
        return 1; // Invoices
      case 1:
        return 2; // New Invoice
      case 7:
        return 3; // Reports
      default:
        return 4; // More
    }
  }

  int _mapBottomNavToTab(int bottomIndex) {
    switch (bottomIndex) {
      case 0:
        return 0; // Dashboard
      case 1:
        return 2; // Invoices
      case 2:
        return 1; // New Invoice
      case 3:
        return 7; // Reports
      default:
        return 0;
    }
  }

  @override
  void initState() {
    super.initState();
    _currentUser = widget.loggedInUser;
    SessionManager.initialize(_onSessionTimeout);
    if (ref.read(appEditionConfigProvider).enableUpdateCheck) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _checkForUpdates());
    }
  }

  Future<void> _checkForUpdates() async {
    final info = await UpdateService.checkForUpdate();
    if (info == null) return;
    if (info.hasUpdate && mounted) setState(() => _hasUpdate = true);
    if (!await UpdateService.shouldNotify(info)) return;
    if (!mounted) return;
    await UpdateDialog.show(context, info);
  }

  @override
  void dispose() {
    SessionManager.dispose();
    super.dispose();
  }

  void _logoutAndResetSession() async {
    await ref.read(authRepositoryProvider).logoutAndSessionReset();
    if (!mounted) return;
    Navigator.pushReplacement(
        context, MaterialPageRoute(builder: (_) => const LoginScreen()));
  }

  void _onSessionTimeout() {
    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (context) => const LoginScreen()),
    );
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Session expired due to inactivity.'),
        duration: Duration(seconds: 4),
      ),
    );
  }

  Future<void> _refreshUser() async {
    final cfg = ref.watch(appEditionConfigProvider);
    if (cfg.isCloud || !mounted) return;
    final fresh =
        await ref.read(authRepositoryProvider).getUserById(_currentUser.id);
    if (fresh != null && mounted) {
      setState(() => _currentUser = fresh);
    }
  }

  Widget buildScreen() {
    switch (_selectedIndex) {
      case 0:
        return DashboardHome(
            onEditInvoice: editInvoice,
            onCloneInvoice: cloneInvoice,
            user: _currentUser);
      case 1:
        return CreateInvoiceScreen(
          key: ValueKey(
              'create_invoice_${invoiceToEdit?.id ?? 'new'}_${_invoiceToClone?.id ?? ''}'),
          invoiceToEdit: invoiceToEdit,
          cloneFrom: _invoiceToClone,
          cloneType: _invoiceToClone != null ? _cloneType : null,
          guard: _invoiceFormGuard,
          onCreateNewInvoice: () {
            if (!mounted) return;
            setState(() {
              invoiceToEdit = null;
              _invoiceToClone = null;
            });
          },
        );
      case 2:
        return InvoiceManagementScreen(
          key: const ValueKey('invoice_list'),
          onEditInvoice: editInvoice,
          onCloneInvoice: cloneInvoice,
          user: _currentUser,
          filterType: 'Invoice',
        );
      case 3:
        return InvoiceManagementScreen(
          key: const ValueKey('quotation_list'),
          onEditInvoice: editInvoice,
          onCloneInvoice: cloneInvoice,
          user: _currentUser,
          filterType: 'Quotation',
        );
      case 4:
        return InvoiceManagementScreen(
          key: const ValueKey('receipt_list'),
          onEditInvoice: editInvoice,
          onCloneInvoice: cloneInvoice,
          user: _currentUser,
          filterType: 'Receipt',
        );
      case 5:
        return CustomerManagementScreen(user: _currentUser);
      case 6:
        return ProductManagementScreen(user: _currentUser);
      case 7:
        return const ReportsScreen();
      case 8:
        return SettingsScreen(currentUser: _currentUser);
      case 9:
        return const ReportsScreen(
          key: ValueKey('revenue_screen'),
          initialTabIndex: 0,
        );
      default:
        return const Center(child: Text('Unknown tab'));
    }
  }

  void editInvoice(Invoice invoice) {
    _openEditInvoice(invoice);
  }

  Future<void> _openEditInvoice(Invoice invoice) async {
    if (!await _canLeaveInvoiceForm()) return;
    if (!mounted) return;
    setState(() {
      _selectedIndex = 1;
      invoiceToEdit = invoice;
      _invoiceToClone = null;
    });
  }

  void cloneInvoice(Invoice invoice, String type) {
    _openCloneInvoice(invoice, type);
  }

  Future<void> _openCloneInvoice(Invoice invoice, String type) async {
    if (!await _canLeaveInvoiceForm()) return;
    if (!mounted) return;
    setState(() {
      _selectedIndex = 1;
      invoiceToEdit = null;
      _invoiceToClone = invoice;
      _cloneType = type;
    });
  }

  Future<bool> _canLeaveInvoiceForm() async {
    return await _invoiceFormGuard.canLeave?.call() ?? true;
  }

  Future<void> _selectTab(int index) async {
    if (_selectedIndex == index) return;
    if (_selectedIndex == 1 && !await _canLeaveInvoiceForm()) return;
    if (_selectedIndex == 7 && index != 7) await _refreshUser();
    if (!mounted) return;
    setState(() {
      _selectedIndex = index;
      if (index != 1) {
        invoiceToEdit = null;
        _invoiceToClone = null;
      }
    });
  }

  String _activeTabName() {
    switch (_selectedIndex) {
      case 0:
        return 'Dashboard';
      case 1:
        return 'New Invoice';
      case 2:
        return 'Invoices';
      case 3:
        return 'Quotations';
      case 4:
        return 'Receipts';
      case 5:
        return 'Customers';
      case 6:
        return 'Products';
      case 7:
        return 'Reports';
      case 8:
        return 'Settings';
      case 9:
        return 'Revenue';
      default:
        return 'Dashboard';
    }
  }

  Widget _buildTopHeader({bool isMobile = false}) {
    return Container(
      height: 64,
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(
          bottom: BorderSide(color: Color(0xFFE2E8F0), width: 1),
        ),
      ),
      padding: EdgeInsets.symmetric(horizontal: isMobile ? 12 : 24),
      child: Row(
        children: [
          if (isMobile) ...[
            IconButton(
              icon: const Icon(
                Icons.menu_rounded,
                color: Color(0xFF111827),
                size: 24,
              ),
              onPressed: () => _scaffoldKey.currentState?.openDrawer(),
              tooltip: 'Open navigation',
            ),
            Container(
              width: 1,
              height: 22,
              color: const Color(0xFFE2E8F0),
              margin: const EdgeInsets.symmetric(horizontal: 10),
            ),
          ] else ...[
            // Sidebar collapse/expand toggle
            Tooltip(
              message: _sidebarExpanded ? 'Collapse sidebar' : 'Expand sidebar',
              child: InkWell(
                onTap: () {
                  if (!mounted) return;
                  setState(() => _sidebarExpanded = !_sidebarExpanded);
                },
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    color: Colors.transparent,
                  ),
                  child: const Icon(
                    Icons.view_sidebar_outlined,
                    color: Color(0xFF6B7280),
                    size: 20,
                  ),
                ),
              ),
            ),
            Container(
              width: 1,
              height: 22,
              color: const Color(0xFFE2E8F0),
              margin: const EdgeInsets.symmetric(horizontal: 14),
            ),
          ],
          // Route-aware breadcrumbs: Admin > Revenue
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Admin',
                style: TextStyle(
                  fontSize: 14,
                  color: Color(0xFF6B7280),
                  fontWeight: FontWeight.w500,
                ),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 8),
                child: Icon(
                  Icons.chevron_right_rounded,
                  size: 16,
                  color: Color(0xFF9CA3AF),
                ),
              ),
              Text(
                _activeTabName(),
                style: const TextStyle(
                  fontSize: 15,
                  color: Color(0xFF111827),
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const Spacer(),
          // Support button
          OutlinedButton.icon(
            onPressed: () {
              showDialog(
                context: context,
                builder: (ctx) => AlertDialog(
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16)),
                  title: const Row(
                    children: [
                      Icon(Icons.headset_mic_outlined,
                          color: Color(0xFF007CFF)),
                      SizedBox(width: 10),
                      Text('Contact & Support',
                          style: TextStyle(
                              fontSize: 18, fontWeight: FontWeight.w700)),
                    ],
                  ),
                  content: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ListTile(
                        leading: const CircleAvatar(
                          backgroundColor: Color(0xFFEFF6FF),
                          child: Icon(Icons.email_outlined,
                              color: Color(0xFF007CFF), size: 20),
                        ),
                        title: const Text('Email Support',
                            style: TextStyle(
                                fontSize: 13, color: Color(0xFF64748B))),
                        subtitle: const Text('info@yatricloud.com',
                            style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF0F172A))),
                        onTap: () =>
                            launchUrl(Uri.parse('mailto:info@yatricloud.com')),
                      ),
                      const SizedBox(height: 8),
                      ListTile(
                        leading: const CircleAvatar(
                          backgroundColor: Color(0xFFF0FDF4),
                          child: Icon(Icons.phone_outlined,
                              color: Color(0xFF16A34A), size: 20),
                        ),
                        title: const Text('Phone / WhatsApp',
                            style: TextStyle(
                                fontSize: 13, color: Color(0xFF64748B))),
                        subtitle: const Text('+91 9724823602',
                            style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF0F172A))),
                        onTap: () => launchUrl(Uri.parse('tel:+919724823602')),
                      ),
                    ],
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: const Text('Close'),
                    ),
                  ],
                ),
              );
            },
            icon: const Icon(Icons.support_agent_outlined, size: 16),
            label: const Text(
              'Support',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
            ),
            style: OutlinedButton.styleFrom(
              foregroundColor: const Color(0xFF374151),
              side: const BorderSide(color: Color(0xFFE2E8F0)),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            ),
          ),
          const SizedBox(width: 14),
          // Profile chip (Admin / Superadmin + circle A)
          Container(
            padding: const EdgeInsets.fromLTRB(14, 4, 6, 4),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(9999),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _currentUser.username.isNotEmpty
                          ? _currentUser.username
                          : 'Admin',
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF111827),
                      ),
                    ),
                    const Text(
                      'Superadmin',
                      style: TextStyle(
                        fontSize: 10,
                        color: Color(0xFF9CA3AF),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
                const SizedBox(width: 10),
                CircleAvatar(
                  radius: 16,
                  backgroundColor: const Color(0xFF007CFF),
                  child: Text(
                    _currentUser.username.isNotEmpty
                        ? _currentUser.username[0].toUpperCase()
                        : 'A',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width < 768;

    return GestureDetector(
      onTap: SessionManager.onUserActivity,
      onPanDown: (_) => SessionManager.onUserActivity(),
      behavior: HitTestBehavior.translucent,
      child: Scaffold(
        key: _scaffoldKey,
        backgroundColor: const Color(0xFFF8FAFC), // slate-50 canvas
        drawer: isMobile
            ? Drawer(
                width: 280,
                child: SafeArea(
                  child: _buildSidebar(inDrawer: true),
                ),
              )
            : null,
        bottomNavigationBar: isMobile
            ? BottomNavigationBar(
                currentIndex: _getBottomNavIndex(),
                onTap: (index) {
                  if (index == 4) {
                    _scaffoldKey.currentState?.openDrawer();
                  } else {
                    final targetTab = _mapBottomNavToTab(index);
                    _selectTab(targetTab);
                  }
                },
                type: BottomNavigationBarType.fixed,
                backgroundColor: Colors.white,
                selectedItemColor: const Color(0xFF007CFF),
                unselectedItemColor: const Color(0xFF64748B),
                selectedFontSize: 11,
                unselectedFontSize: 11,
                items: const [
                  BottomNavigationBarItem(
                    icon: Icon(Icons.grid_view_outlined),
                    activeIcon: Icon(Icons.grid_view_rounded),
                    label: 'Dashboard',
                  ),
                  BottomNavigationBarItem(
                    icon: Icon(Icons.receipt_long_outlined),
                    activeIcon: Icon(Icons.receipt_long_rounded),
                    label: 'Invoices',
                  ),
                  BottomNavigationBarItem(
                    icon: Icon(Icons.add_circle_outline_rounded),
                    activeIcon: Icon(Icons.add_circle_rounded),
                    label: 'New',
                  ),
                  BottomNavigationBarItem(
                    icon: Icon(Icons.bar_chart_outlined),
                    activeIcon: Icon(Icons.bar_chart_rounded),
                    label: 'Reports',
                  ),
                  BottomNavigationBarItem(
                    icon: Icon(Icons.menu_rounded),
                    label: 'More',
                  ),
                ],
              )
            : null,
        body: Row(
          children: [
            if (!isMobile) _buildSidebar(),
            Expanded(
              child: Column(
                children: [
                  _buildTopHeader(isMobile: isMobile),
                  Expanded(child: buildScreen()),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSidebar({bool inDrawer = false}) {
    final expanded = inDrawer || _sidebarExpanded;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOutCubic,
      width: inDrawer ? double.infinity : (expanded ? 250.0 : 72.0),
      decoration: BoxDecoration(
        color: Colors.white,
        border: inDrawer
            ? null
            : const Border(
                right: BorderSide(color: Color(0xFFE2E8F0), width: 1),
              ),
      ),
      child: ClipRect(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── Logo Header ──────────────────────────
            Container(
              height: 64,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: const BoxDecoration(
                border: Border(
                    bottom: BorderSide(color: Color(0xFFE2E8F0), width: 1)),
              ),
              child: Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.asset(
                      'assets/images/yatricloud_logo.png',
                      width: 32,
                      height: 32,
                      fit: BoxFit.contain,
                    ),
                  ),
                  if (expanded) ...[
                    const SizedBox(width: 10),
                    Expanded(
                      child: RichText(
                        text: const TextSpan(
                          children: [
                            TextSpan(
                              text: 'Yatri ',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w800,
                                color: Color(0xFF111827),
                              ),
                            ),
                            TextSpan(
                              text: 'Admin',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w800,
                                color: Color(0xFF007CFF), // Yatri brand blue
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),

            const SizedBox(height: 12),

            // ── Nav Items ──────────────────────────────
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (expanded) ...[
                      const Padding(
                        padding: EdgeInsets.fromLTRB(16, 8, 16, 6),
                        child: Text(
                          'OVERVIEW',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.8,
                            color: Color(0xFF9CA3AF),
                          ),
                        ),
                      ),
                      _buildNavItem(0, Icons.grid_view_outlined,
                          Icons.grid_view_rounded, 'Dashboard',
                          inDrawer: inDrawer),

                      const SizedBox(height: 12),

                      const Padding(
                        padding: EdgeInsets.fromLTRB(16, 8, 16, 6),
                        child: Text(
                          'MANAGE',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.8,
                            color: Color(0xFF9CA3AF),
                          ),
                        ),
                      ),
                      // Accordion / Group: Invoicing
                      Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 2),
                        child: InkWell(
                          onTap: () {
                            if (inDrawer) Navigator.of(context).maybePop();
                            _selectTab(2);
                          },
                          borderRadius: BorderRadius.circular(8),
                          hoverColor: const Color(0xFFF1F5F9),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 9),
                            child: Row(
                              children: const [
                                Icon(Icons.receipt_long_outlined,
                                    size: 18, color: Color(0xFF475569)),
                                SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    'Invoicing',
                                    style: TextStyle(
                                      color: Color(0xFF1E293B),
                                      fontWeight: FontWeight.w600,
                                      fontSize: 13.5,
                                    ),
                                  ),
                                ),
                                Icon(Icons.keyboard_arrow_up_rounded,
                                    size: 18, color: Color(0xFF9CA3AF)),
                              ],
                            ),
                          ),
                        ),
                      ),
                      // Sub-items indented with left vertical hairline
                      Padding(
                        padding: const EdgeInsets.only(
                            left: 30, right: 10, bottom: 6),
                        child: Container(
                          decoration: const BoxDecoration(
                            border: Border(
                                left: BorderSide(
                                    color: Color(0xFFE5E7EB), width: 1.5)),
                          ),
                          padding: const EdgeInsets.only(left: 10),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              _buildSubNavItem(2, 'Invoices',
                                  inDrawer: inDrawer),
                              _buildSubNavItem(1, 'New Invoice',
                                  inDrawer: inDrawer),
                              _buildSubNavItem(3, 'Quotations',
                                  inDrawer: inDrawer),
                              _buildSubNavItem(4, 'Receipts',
                                  inDrawer: inDrawer),
                              _buildSubNavItem(9, 'Revenue',
                                  inDrawer: inDrawer),
                            ],
                          ),
                        ),
                      ),
                      _buildNavItem(5, Icons.people_outline_rounded,
                          Icons.people_rounded, 'Customers',
                          inDrawer: inDrawer),
                      _buildNavItem(6, Icons.inventory_2_outlined,
                          Icons.inventory_2_rounded, 'Products',
                          inDrawer: inDrawer),
                      _buildNavItem(7, Icons.bar_chart_outlined,
                          Icons.bar_chart_rounded, 'Reports',
                          inDrawer: inDrawer),
                      _buildNavItem(8, Icons.settings_outlined,
                          Icons.settings_rounded, 'Settings',
                          inDrawer: inDrawer),
                    ] else ...[
                      _buildNavItem(0, Icons.grid_view_outlined,
                          Icons.grid_view_rounded, 'Dashboard',
                          inDrawer: inDrawer),
                      const Divider(
                          height: 12,
                          indent: 12,
                          endIndent: 12,
                          color: Color(0xFFE5E7EB)),
                      _buildNavItem(2, Icons.receipt_long_outlined,
                          Icons.receipt_long_rounded, 'Invoices',
                          inDrawer: inDrawer),
                      _buildNavItem(1, Icons.add_circle_outline_rounded,
                          Icons.add_circle_rounded, 'New Invoice',
                          inDrawer: inDrawer),
                      _buildNavItem(3, Icons.request_quote_outlined,
                          Icons.request_quote_rounded, 'Quotations',
                          inDrawer: inDrawer),
                      _buildNavItem(4, Icons.point_of_sale_outlined,
                          Icons.point_of_sale_rounded, 'Receipts',
                          inDrawer: inDrawer),
                      _buildNavItem(9, Icons.payments_outlined,
                          Icons.payments_rounded, 'Revenue',
                          inDrawer: inDrawer),
                      _buildNavItem(5, Icons.people_outline_rounded,
                          Icons.people_rounded, 'Customers',
                          inDrawer: inDrawer),
                      _buildNavItem(6, Icons.inventory_2_outlined,
                          Icons.inventory_2_rounded, 'Products',
                          inDrawer: inDrawer),
                      _buildNavItem(7, Icons.bar_chart_outlined,
                          Icons.bar_chart_rounded, 'Reports',
                          inDrawer: inDrawer),
                      _buildNavItem(8, Icons.settings_outlined,
                          Icons.settings_rounded, 'Settings',
                          inDrawer: inDrawer),
                    ],
                  ],
                ),
              ),
            ),

            // ── Bottom Sign Out — matches Yatri Cloud reference ────────
            Container(
              padding: const EdgeInsets.all(12),
              decoration: const BoxDecoration(
                border:
                    Border(top: BorderSide(color: Color(0xFFE2E8F0), width: 1)),
              ),
              child: expanded
                  ? SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: () {
                          if (inDrawer) Navigator.of(context).maybePop();
                          _logoutAndResetSession();
                        },
                        icon: const Icon(
                          Icons.logout_rounded,
                          size: 16,
                          color: Color(0xFF64748B),
                        ),
                        label: const Text(
                          'Sign Out',
                          style: TextStyle(
                            color: Color(0xFF475569),
                            fontWeight: FontWeight.w500,
                            fontSize: 13,
                            letterSpacing: 0.1,
                          ),
                        ),
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(
                              color: Color(0xFFE2E8F0), width: 1),
                          backgroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 11,
                          ),
                        ),
                      ),
                    )
                  : Tooltip(
                      message: 'Sign Out',
                      child: InkWell(
                        onTap: () {
                          if (inDrawer) Navigator.of(context).maybePop();
                          _logoutAndResetSession();
                        },
                        borderRadius: BorderRadius.circular(8),
                        child: Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                                color: const Color(0xFFE2E8F0), width: 1),
                          ),
                          child: const Icon(Icons.logout_rounded,
                              color: Color(0xFF64748B), size: 18),
                        ),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  /*
  Widget _buildComingSoonNavItem(IconData icon, String label) {
    const disabledColor = Color(0xFFCBD5E1);

    return LayoutBuilder(
      builder: (context, constraints) {
        final useExpanded = constraints.maxWidth > 110;

        if (!useExpanded) {
          return Tooltip(
            message: '$label — Coming Soon',
            preferBelow: false,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              child: Container(
                padding: const EdgeInsets.all(12),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, color: disabledColor, size: 20),
              ),
            ),
          );
        }

        return Tooltip(
          message: 'Coming Soon',
          preferBelow: false,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(icon, color: disabledColor, size: 18),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      label,
                      style: const TextStyle(
                        color: disabledColor,
                        fontWeight: FontWeight.w400,
                        fontSize: 13.5,
                      ),
                    ),
                  ),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
                    ),
                    child: const Text(
                      'Soon',
                      style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.w600,
                          color: disabledColor),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
  */

  Widget _buildSubNavItem(int index, String label, {bool inDrawer = false}) {
    final selected = _selectedIndex == index;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2.5),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(6),
        child: InkWell(
          onTap: () {
            if (inDrawer) Navigator.of(context).maybePop();
            _selectTab(index);
          },
          borderRadius: BorderRadius.circular(6),
          hoverColor: const Color(0xFFF1F5F9),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9.5),
            decoration: BoxDecoration(
              color: selected ? const Color(0xFF007CFF) : Colors.transparent,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              label,
              style: TextStyle(
                color: selected ? Colors.white : const Color(0xFF64748B),
                fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                fontSize: 13.5,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildNavItem(
      int index, IconData outlinedIcon, IconData filledIcon, String label,
      {bool showDot = false, bool? isSelectedOverride, bool inDrawer = false}) {
    final selected = isSelectedOverride ?? (_selectedIndex == index);

    Future<void> onTap() async {
      if (inDrawer) Navigator.of(context).maybePop();
      await _selectTab(index);
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final useExpanded = constraints.maxWidth > 110;

        if (!useExpanded) {
          return Tooltip(
            message: label,
            preferBelow: false,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              child: InkWell(
                onTap: onTap,
                borderRadius: BorderRadius.circular(8),
                hoverColor: selected
                    ? const Color(0xFF007CFF)
                    : const Color(0xFFF1F5F9),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  padding: const EdgeInsets.all(12),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color:
                        selected ? const Color(0xFF007CFF) : Colors.transparent,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    selected ? filledIcon : outlinedIcon,
                    color: selected ? Colors.white : const Color(0xFF64748B),
                    size: 20,
                  ),
                ),
              ),
            ),
          );
        }

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
          child: Material(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            child: InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(8),
              hoverColor:
                  selected ? const Color(0xFF007CFF) : const Color(0xFFF1F5F9),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 10.5),
                decoration: BoxDecoration(
                  color:
                      selected ? const Color(0xFF007CFF) : Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(
                      selected ? filledIcon : outlinedIcon,
                      color: selected ? Colors.white : const Color(0xFF64748B),
                      size: 18,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        label,
                        style: TextStyle(
                          color:
                              selected ? Colors.white : const Color(0xFF334155),
                          fontWeight:
                              selected ? FontWeight.w600 : FontWeight.w500,
                          fontSize: 13.5,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class DashboardHome extends ConsumerStatefulWidget {
  final Function(Invoice) onEditInvoice;
  final Function(Invoice, String) onCloneInvoice;
  final User user;
  const DashboardHome({
    required this.onEditInvoice,
    required this.onCloneInvoice,
    required this.user,
    super.key,
  });

  @override
  ConsumerState<DashboardHome> createState() => _DashboardHomeState();
}

class _DashboardHomeState extends ConsumerState<DashboardHome> {
  final dbHelper = DatabaseHelper();
  int totalCustomers = 0;
  int totalProducts = 0;
  int totalInvoices = 0;
  double totalRevenue = 0.0;
  double totalOutstanding = 0.0;
  List<Invoice> recentInvoices = [];
  List<Invoice> dueSoonInvoices = [];
  List<Product> outOfStockProducts = [];
  List<Invoice> overdueInvoices = [];
  String _currencySymbol = '₹';
  bool isLoading = true;
  String _dashboardLayout = 'default';
  bool _showLayoutBanner = false;
  bool _showThemeBanner = false;
  bool _showSupportBanner = false;
  String _supportMilestone = '';
  List<Map<String, dynamic>> _monthlyRevenue = [];
  List<Map<String, dynamic>> _topCustomers = [];
  List<Map<String, dynamic>> _topProducts = [];
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  String _timeFilter = 'All time';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _loadDashboardData();
  }

  Future<void> _loadDashboardData() async {
    if (!mounted) return;
    setState(() => isLoading = true);

    final results = await Future.wait([
      ref.read(customerRepositoryProvider).getTotalCustomerCount(), // 0
      ref.read(productRepositoryProvider).getTotalProductCount(), // 1
      ref.read(invoiceRepositoryProvider).getDashboardFinancials(), // 2
      ref.read(invoiceRepositoryProvider).getRecentInvoices(limit: 50), // 3
      ref.read(invoiceRepositoryProvider).getDueSoonInvoices(), // 4
      ref.read(invoiceRepositoryProvider).getOverdueInvoices(limit: 10), // 5
      ref.read(settingsRepositoryProvider).getCurrency(), // 6
      ref.read(invoiceRepositoryProvider).getMonthlyRevenue(), // 7
      ref
          .read(settingsRepositoryProvider)
          .getSetting(SettingKey.dashboardLayout), // 8
      ref.read(invoiceRepositoryProvider).getTopCustomers(), // 9
      ref.read(invoiceRepositoryProvider).getTopProducts(), // 10
      ref
          .read(settingsRepositoryProvider)
          .getSetting(SettingKey.layoutBannerDismissed), // 11
      ref
          .read(settingsRepositoryProvider)
          .getSetting(SettingKey.supportBannerDismissed), // 12
      ref.read(productRepositoryProvider).getOutOfStockProducts(), // 13
      ref
          .read(settingsRepositoryProvider)
          .getSetting(SettingKey.themeBannerDismissed), // 14
    ]);

    final customerCount = results[0] as int;
    final productCount = results[1] as int;
    final financials =
        results[2] as ({int count, double revenue, double outstanding});
    final recent = results[3] as List<Invoice>;
    final dueSoon = results[4] as List<Invoice>;
    final overdue = results[5] as List<Invoice>;
    final currency = results[6] as CurrencyOption;
    final monthly = results[7] as List<Map<String, dynamic>>;
    final layout = results[8] as String?;
    final topCust = results[9] as List<Map<String, dynamic>>;
    final topProd = results[10] as List<Map<String, dynamic>>;
    final bannerDismissed = results[11] as String?;
    final supportDismissed = results[12] as String?;
    final outOfStock = results[13] as List<Product>;
    final themeBannerDismissed = results[14] as String?;
    final String milestone = financials.count >= 100
        ? '100'
        : financials.count >= 50
            ? '50'
            : financials.count > 10
                ? '10'
                : '';
    if (!mounted) return;
    setState(() {
      totalCustomers = customerCount;
      totalProducts = productCount;
      outOfStockProducts = outOfStock;
      totalInvoices = financials.count;
      totalRevenue = financials.revenue;
      totalOutstanding = financials.outstanding;
      recentInvoices = recent;
      dueSoonInvoices = dueSoon;
      overdueInvoices = overdue;
      _currencySymbol = currency.symbol;
      _monthlyRevenue = monthly;
      _dashboardLayout = layout ?? 'default';
      _topCustomers = topCust;
      _topProducts = topProd;
      _showLayoutBanner = bannerDismissed != '1';
      _showThemeBanner = themeBannerDismissed != '1';
      _supportMilestone = milestone;
      _showSupportBanner =
          milestone.isNotEmpty && supportDismissed != milestone;
      isLoading = false;
    });
  }

  Future<void> _dismissSupportBanner() async {
    await ref
        .read(settingsRepositoryProvider)
        .setSetting(SettingKey.supportBannerDismissed, _supportMilestone);
    if (mounted) setState(() => _showSupportBanner = false);
  }

  Future<void> _dismissLayoutBanner() async {
    await ref
        .read(settingsRepositoryProvider)
        .setSetting(SettingKey.layoutBannerDismissed, '1');
    if (mounted) setState(() => _showLayoutBanner = false);
  }

  Future<void> _dismissThemeBanner() async {
    await ref
        .read(settingsRepositoryProvider)
        .setSetting(SettingKey.themeBannerDismissed, '1');
    if (mounted) setState(() => _showThemeBanner = false);
  }

  Widget _buildLayoutDiscoveryBanner() {
    return AnimatedSize(
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
      child: _showLayoutBanner
          ? Container(
              margin: const EdgeInsets.only(bottom: 20),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: const Color(0xFFEFF6FF),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFBFDBFE)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.dashboard_customize_outlined,
                      color: Color(0xFF2563EB), size: 20),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'New: Multiple dashboard layouts',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                            color: Color(0xFF1E40AF),
                          ),
                        ),
                        SizedBox(height: 2),
                        Text(
                          'Switch between Default, Classic, Bento, and Simple Feed using the grid icon in the top-right.',
                          style:
                              TextStyle(fontSize: 12, color: Color(0xFF3B82F6)),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  TextButton(
                    onPressed: _dismissLayoutBanner,
                    style: TextButton.styleFrom(
                      foregroundColor: const Color(0xFF2563EB),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 6),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: const Text('Got it',
                        style: TextStyle(fontWeight: FontWeight.w600)),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 16),
                    color: const Color(0xFF93C5FD),
                    onPressed: _dismissLayoutBanner,
                    tooltip: 'Dismiss',
                    padding: EdgeInsets.zero,
                    constraints:
                        const BoxConstraints(minWidth: 28, minHeight: 28),
                  ),
                ],
              ),
            )
          : const SizedBox.shrink(),
    );
  }

  Widget _buildThemeDiscoveryBanner() {
    return AnimatedSize(
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
      child: _showThemeBanner
          ? Container(
              margin: const EdgeInsets.only(bottom: 20),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: const Color(0xFFF5F3FF),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFDDD6FE)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.dark_mode_outlined,
                      color: Color(0xFF7C3AED), size: 20),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              'New: Dark mode',
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 13,
                                color: Color(0xFF5B21B6),
                              ),
                            ),
                            SizedBox(width: 6),
                            _BetaTag(),
                          ],
                        ),
                        SizedBox(height: 2),
                        Text(
                          'We\'re still polishing it — switch it on from Settings > Company Info and let us know what looks off.',
                          style:
                              TextStyle(fontSize: 12, color: Color(0xFF7C3AED)),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  TextButton(
                    onPressed: _dismissThemeBanner,
                    style: TextButton.styleFrom(
                      foregroundColor: const Color(0xFF7C3AED),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 6),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: const Text('Got it',
                        style: TextStyle(fontWeight: FontWeight.w600)),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 16),
                    color: const Color(0xFFC4B5FD),
                    onPressed: _dismissThemeBanner,
                    tooltip: 'Dismiss',
                    padding: EdgeInsets.zero,
                    constraints:
                        const BoxConstraints(minWidth: 28, minHeight: 28),
                  ),
                ],
              ),
            )
          : const SizedBox.shrink(),
    );
  }

  Widget _buildSupportBanner() {
    final bool isReviewMilestone = _supportMilestone == '10';
    return AnimatedSize(
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
      child: _showSupportBanner
          ? Container(
              margin: const EdgeInsets.only(bottom: 16),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: const Color(0xFFFFFBEB),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFFDE68A)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                      isReviewMilestone
                          ? Icons.star_outline
                          : Icons.celebration_outlined,
                      color: const Color(0xFFD97706),
                      size: 22),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'You\'ve created $_supportMilestone invoices!',
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                            color: Color(0xFF92400E),
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          isReviewMilestone
                              ? 'Enjoying Yatri Billing? A quick review helps a lot.'
                              : 'Looks like Yatri Billing is part of your workflow. If it\'s been helpful, consider supporting the project — whenever it feels right.',
                          style: const TextStyle(
                              fontSize: 12, color: Color(0xFFB45309)),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  TextButton(
                    onPressed: () async {
                      final uri = Uri.parse('mailto:info@yatricloud.com');
                      if (await canLaunchUrl(uri)) await launchUrl(uri);
                    },
                    style: TextButton.styleFrom(
                      foregroundColor: const Color(0xFF92400E),
                      backgroundColor: const Color(0xFFFDE68A),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 6),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: Text(isReviewMilestone ? 'Feedback' : 'Support',
                        style: const TextStyle(fontWeight: FontWeight.w600)),
                  ),
                  const SizedBox(width: 4),
                  IconButton(
                    icon: const Icon(Icons.close, size: 16),
                    color: const Color(0xFFD97706),
                    onPressed: _dismissSupportBanner,
                    tooltip: 'Dismiss',
                    padding: EdgeInsets.zero,
                    constraints:
                        const BoxConstraints(minWidth: 28, minHeight: 28),
                  ),
                ],
              ),
            )
          : const SizedBox.shrink(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC), // slate-50
      appBar: null,
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : _buildContent(),
    );
  }

  Widget _buildContent() {
    switch (_dashboardLayout) {
      case 'classic':
        return _buildClassicLayout();
      case 'simple':
        return _buildSimpleFeedLayout();
      case 'bento':
        return _buildBentoLayout();
      case 'default':
      default:
        return _buildDefaultLayout();
    }
  }

  Future<void> _exportReceiptsCsv() async {
    try {
      if (recentInvoices.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No receipts to export.')),
        );
        return;
      }
      final path = await ExportService.exportInvoicesToCsv(recentInvoices,
          type: 'Receipt');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(
                'Exported ${recentInvoices.length} receipts to CSV: $path')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Export failed: $e')),
      );
    }
  }

  Widget _buildYatriStatCard({
    required String title,
    required String value,
    required Color accentColor,
    required IconData icon,
  }) {
    return Container(
      height: 136,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE5E7EB)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.02),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      clipBehavior: Clip.hardEdge,
      child: Stack(
        children: [
          Positioned(
            right: -10,
            top: -10,
            child: Icon(
              icon,
              size: 92,
              color: accentColor.withOpacity(0.06),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(22),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  title.toUpperCase(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.8,
                    color: Color(0xFF6B7280),
                  ),
                ),
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.5,
                    color: Color(0xFF111827),
                  ),
                ),
                Container(
                  width: 48,
                  height: 4,
                  decoration: BoxDecoration(
                    color: accentColor,
                    borderRadius: BorderRadius.circular(9999),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCategoryRow(String name, String count) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          name,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: Color(0xFF111827),
          ),
        ),
        Text(
          count,
          style: const TextStyle(
            fontSize: 13,
            color: Color(0xFF6B7280),
          ),
        ),
      ],
    );
  }

  Widget _buildCurrencyRow(String currency, String amount) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          currency,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: Color(0xFF111827),
          ),
        ),
        Text(
          amount,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: Color(0xFF111827),
          ),
        ),
      ],
    );
  }

  Widget _buildDefaultLayout() {
    final filtered = recentInvoices.where((inv) {
      if (_searchQuery.isEmpty) return true;
      final q = _searchQuery.toLowerCase();
      final num = (inv.invoiceNumber ?? inv.id).toLowerCase();
      final name = inv.customer.name.toLowerCase();
      final email = inv.customer.email.toLowerCase();
      final itemMatch =
          inv.items.any((it) => it.product.name.toLowerCase().contains(q));
      return num.contains(q) ||
          name.contains(q) ||
          email.contains(q) ||
          itemMatch;
    }).toList();

    final isNarrow = MediaQuery.of(context).size.width < 768;

    return SingleChildScrollView(
      padding: EdgeInsets.symmetric(
          horizontal: isNarrow ? 16 : 36, vertical: isNarrow ? 20 : 32),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1280),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Page Header: Title + All Time ─────────────────
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Payments and revenue',
                    style: TextStyle(
                      fontSize: 30,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -0.5,
                      color: Color(0xFF111827),
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _buildLayoutToggle(),
                          const SizedBox(width: 12),
                          PopupMenuButton<String>(
                            tooltip: 'Filter by time',
                            offset: const Offset(0, 40),
                            onSelected: (val) {
                              if (!mounted) return;
                              setState(() => _timeFilter = val);
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                    content: Text('Showing data for $val')),
                              );
                            },
                            itemBuilder: (ctx) => const [
                              PopupMenuItem(
                                  value: 'All time', child: Text('All time')),
                              PopupMenuItem(
                                  value: 'This year', child: Text('This year')),
                              PopupMenuItem(
                                  value: 'This month',
                                  child: Text('This month')),
                              PopupMenuItem(
                                  value: 'This week', child: Text('This week')),
                            ],
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 14, vertical: 8),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(10),
                                border:
                                    Border.all(color: const Color(0xFFE5E7EB)),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    _timeFilter,
                                    style: const TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w500,
                                      color: Color(0xFF111827),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  const Icon(Icons.keyboard_arrow_down_rounded,
                                      size: 16, color: Color(0xFF6B7280)),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '$totalInvoices ${totalInvoices == 1 ? "receipt" : "receipts"}',
                        style: const TextStyle(
                          fontSize: 12,
                          color: Color(0xFF6B7280),
                          fontWeight: FontWeight.w400,
                        ),
                      ),
                    ],
                  ),
                ],
              ),

              const SizedBox(height: 28),

              // ── 4 Stats Cards ────────────────────────────────
              LayoutBuilder(
                builder: (context, constraints) {
                  final card1 = _buildYatriStatCard(
                    title: 'Total receipts',
                    value: totalInvoices.toString(),
                    accentColor: const Color(0xFF007CFF), // Yatri brand blue
                    icon: Icons.receipt_long_outlined,
                  );
                  final card2 = _buildYatriStatCard(
                    title: 'Revenue in INR',
                    value: '$_currencySymbol${totalRevenue.toStringAsFixed(0)}',
                    accentColor: const Color(0xFF10B981),
                    icon: Icons.currency_rupee_rounded,
                  );
                  final card3 = _buildYatriStatCard(
                    title: 'Paid in other currencies',
                    value: '0',
                    accentColor: const Color(0xFF3B82F6),
                    icon: Icons.public_rounded,
                  );
                  final card4 = _buildYatriStatCard(
                    title: 'Categories',
                    value: totalProducts > 0 ? totalProducts.toString() : '3',
                    accentColor: const Color(0xFFF59E0B),
                    icon: Icons.layers_outlined,
                  );

                  if (constraints.maxWidth < 900) {
                    return Column(
                      children: [
                        Row(
                          children: [
                            Expanded(child: card1),
                            const SizedBox(width: 12),
                            Expanded(child: card2),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(child: card3),
                            const SizedBox(width: 12),
                            Expanded(child: card4),
                          ],
                        ),
                      ],
                    );
                  }
                  return Row(
                    children: [
                      Expanded(child: card1),
                      const SizedBox(width: 16),
                      Expanded(child: card2),
                      const SizedBox(width: 16),
                      Expanded(child: card3),
                      const SizedBox(width: 16),
                      Expanded(child: card4),
                    ],
                  );
                },
              ),

              const SizedBox(height: 24),

              // ── 2 Secondary Summary Cards (50% / 50%) ─────────
              LayoutBuilder(
                builder: (context, constraints) {
                  final summaryCat = Container(
                    padding: const EdgeInsets.all(22),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: const Color(0xFFE5E7EB)),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.02),
                          blurRadius: 6,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Revenue by category',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF111827),
                          ),
                        ),
                        const SizedBox(height: 18),
                        _buildCategoryRow('Store',
                            '$totalInvoices ${totalInvoices == 1 ? "receipt" : "receipts"}'),
                        const SizedBox(height: 12),
                        _buildCategoryRow('Events', '0 receipts'),
                        const SizedBox(height: 12),
                        _buildCategoryRow('Training', '0 receipts'),
                      ],
                    ),
                  );

                  final summaryCurr = Container(
                    padding: const EdgeInsets.all(22),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: const Color(0xFFE5E7EB)),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.02),
                          blurRadius: 6,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Revenue by currency',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF111827),
                          ),
                        ),
                        const SizedBox(height: 18),
                        _buildCurrencyRow('Indian Rupee',
                            '$_currencySymbol${totalRevenue.toStringAsFixed(0)}'),
                        const SizedBox(height: 12),
                        _buildCurrencyRow('USD', '\$0.00'),
                        const SizedBox(height: 12),
                        _buildCurrencyRow('EUR', '€0.00'),
                      ],
                    ),
                  );

                  if (constraints.maxWidth < 768) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        summaryCat,
                        const SizedBox(height: 16),
                        summaryCurr,
                      ],
                    );
                  }

                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: summaryCat),
                      const SizedBox(width: 20),
                      Expanded(child: summaryCurr),
                    ],
                  );
                },
              ),

              const SizedBox(height: 24),

              // ── All Receipts Table Card ──────────────────────
              Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFFE5E7EB)),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.02),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Card Header with Title, Search and Export CSV
                    Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 24, vertical: 18),
                      child: LayoutBuilder(
                        builder: (context, box) {
                          if (box.maxWidth < 650) {
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    const Text(
                                      'All receipts',
                                      style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w700,
                                        color: Color(0xFF111827),
                                      ),
                                    ),
                                    OutlinedButton.icon(
                                      onPressed: _exportReceiptsCsv,
                                      icon: const Icon(Icons.download_rounded,
                                          size: 16, color: Color(0xFF374151)),
                                      label: const Text(
                                        'Export CSV',
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w500,
                                          color: Color(0xFF374151),
                                        ),
                                      ),
                                      style: OutlinedButton.styleFrom(
                                        side: const BorderSide(
                                            color: Color(0xFFE5E7EB)),
                                        shape: RoundedRectangleBorder(
                                            borderRadius:
                                                BorderRadius.circular(8)),
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 10, vertical: 8),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 12),
                                SizedBox(
                                  height: 38,
                                  child: TextField(
                                    controller: _searchController,
                                    onChanged: (v) => setState(() =>
                                        _searchQuery = v.trim().toLowerCase()),
                                    style: const TextStyle(fontSize: 13),
                                    decoration: InputDecoration(
                                      prefixIcon: const Icon(Icons.search,
                                          size: 18, color: Color(0xFF9CA3AF)),
                                      hintText:
                                          'Search buyer, item or receipt number',
                                      hintStyle: const TextStyle(
                                          fontSize: 12.5,
                                          color: Color(0xFF9CA3AF)),
                                      contentPadding:
                                          const EdgeInsets.symmetric(
                                              vertical: 8, horizontal: 12),
                                      filled: true,
                                      fillColor: Colors.white,
                                      enabledBorder: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(8),
                                        borderSide: const BorderSide(
                                            color: Color(0xFFE5E7EB)),
                                      ),
                                      focusedBorder: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(8),
                                        borderSide: const BorderSide(
                                            color: Color(0xFF007CFF)),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            );
                          }
                          return Row(
                            children: [
                              const Text(
                                'All receipts',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                  color: Color(0xFF111827),
                                ),
                              ),
                              const Spacer(),
                              // Search
                              SizedBox(
                                width: 280,
                                height: 38,
                                child: TextField(
                                  controller: _searchController,
                                  onChanged: (v) => setState(() =>
                                      _searchQuery = v.trim().toLowerCase()),
                                  style: const TextStyle(fontSize: 13),
                                  decoration: InputDecoration(
                                    prefixIcon: const Icon(Icons.search,
                                        size: 18, color: Color(0xFF9CA3AF)),
                                    hintText:
                                        'Search buyer, item or receipt number',
                                    hintStyle: const TextStyle(
                                        fontSize: 12.5,
                                        color: Color(0xFF9CA3AF)),
                                    contentPadding: const EdgeInsets.symmetric(
                                        vertical: 8, horizontal: 12),
                                    filled: true,
                                    fillColor: Colors.white,
                                    enabledBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(8),
                                      borderSide: const BorderSide(
                                          color: Color(0xFFE5E7EB)),
                                    ),
                                    focusedBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(8),
                                      borderSide: const BorderSide(
                                          color: Color(0xFF007CFF)),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              // Export CSV Button
                              OutlinedButton.icon(
                                onPressed: _exportReceiptsCsv,
                                icon: const Icon(Icons.download_rounded,
                                    size: 16, color: Color(0xFF374151)),
                                label: const Text(
                                  'Export CSV',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w500,
                                    color: Color(0xFF374151),
                                  ),
                                ),
                                style: OutlinedButton.styleFrom(
                                  side: const BorderSide(
                                      color: Color(0xFFE5E7EB)),
                                  shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(8)),
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 14, vertical: 10),
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                    ),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: SizedBox(
                        width: 860,
                        child: Column(
                          children: [
                            // Table Column Headers — solid brand blue per Yatri Cloud reference
                            Container(
                              decoration: const BoxDecoration(
                                color: Color(0xFF007CFF),
                              ),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 24, vertical: 14),
                              child: Row(
                                children: const [
                                  SizedBox(
                                    width: 120,
                                    child: Text('Date',
                                        style: TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w600,
                                            color: Colors.white,
                                            letterSpacing: 0.4)),
                                  ),
                                  SizedBox(
                                    width: 120,
                                    child: Text('Receipt',
                                        style: TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w600,
                                            color: Colors.white,
                                            letterSpacing: 0.4)),
                                  ),
                                  Expanded(
                                    flex: 3,
                                    child: Text('Buyer',
                                        style: TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w600,
                                            color: Colors.white,
                                            letterSpacing: 0.4)),
                                  ),
                                  SizedBox(
                                    width: 110,
                                    child: Text('Category',
                                        style: TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w600,
                                            color: Colors.white,
                                            letterSpacing: 0.4)),
                                  ),
                                  Expanded(
                                    flex: 3,
                                    child: Text('Item',
                                        style: TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w600,
                                            color: Colors.white,
                                            letterSpacing: 0.4)),
                                  ),
                                  SizedBox(
                                    width: 130,
                                    child: Text('Amount',
                                        textAlign: TextAlign.right,
                                        style: TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w600,
                                            color: Colors.white,
                                            letterSpacing: 0.4)),
                                  ),
                                ],
                              ),
                            ),
                            // Table Rows
                            if (filtered.isEmpty)
                              Padding(
                                padding: const EdgeInsets.all(40),
                                child: Center(
                                  child: Text(
                                    recentInvoices.isEmpty
                                        ? 'No receipts have been generated yet.'
                                        : 'No receipts match your search.',
                                    style: const TextStyle(
                                        fontSize: 13, color: Color(0xFF6B7280)),
                                  ),
                                ),
                              )
                            else
                              ListView.separated(
                                shrinkWrap: true,
                                physics: const NeverScrollableScrollPhysics(),
                                itemCount: filtered.length,
                                separatorBuilder: (_, __) => const Divider(
                                    height: 1, color: Color(0xFFF3F4F6)),
                                itemBuilder: (context, index) {
                                  final inv = filtered[index];
                                  final dateStr = DateFormat('dd MMM yyyy')
                                      .format(inv.date);
                                  final itemsSummary = inv.items.isEmpty
                                      ? 'Store'
                                      : (inv.items.length == 1
                                          ? inv.items.first.product.name
                                          : '${inv.items.first.product.name} and ${inv.items.length - 1} more');

                                  return InkWell(
                                    onTap: () => widget.onEditInvoice(inv),
                                    hoverColor: const Color(0xFFF9FAFB),
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 24, vertical: 14),
                                      child: Row(
                                        children: [
                                          SizedBox(
                                            width: 120,
                                            child: Text(
                                              dateStr,
                                              style: const TextStyle(
                                                  fontSize: 13,
                                                  color: Color(0xFF6B7280)),
                                            ),
                                          ),
                                          SizedBox(
                                            width: 120,
                                            child: Text(
                                              formatDisplayInvoiceNumber(inv
                                                          .invoiceNumber
                                                          ?.isNotEmpty ==
                                                      true
                                                  ? inv.invoiceNumber
                                                  : inv.id),
                                              style: const TextStyle(
                                                fontSize: 12.5,
                                                fontFamily: 'monospace',
                                                color: Color(0xFF111827),
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                          ),
                                          Expanded(
                                            flex: 3,
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  inv.customer.name.isNotEmpty
                                                      ? inv.customer.name
                                                      : 'Yatri',
                                                  style: const TextStyle(
                                                      fontSize: 13.5,
                                                      fontWeight:
                                                          FontWeight.w600,
                                                      color: Color(0xFF111827)),
                                                ),
                                                if (inv
                                                    .customer.email.isNotEmpty)
                                                  Text(
                                                    inv.customer.email,
                                                    style: const TextStyle(
                                                        fontSize: 11.5,
                                                        color:
                                                            Color(0xFF6B7280)),
                                                  ),
                                              ],
                                            ),
                                          ),
                                          SizedBox(
                                            width: 110,
                                            child: Align(
                                              alignment: Alignment.centerLeft,
                                              child: Container(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                        horizontal: 8,
                                                        vertical: 3),
                                                decoration: BoxDecoration(
                                                  color:
                                                      const Color(0xFFEFF6FF),
                                                  borderRadius:
                                                      BorderRadius.circular(6),
                                                  border: Border.all(
                                                      color: const Color(
                                                          0xFFBFDBFE)),
                                                ),
                                                child: const Text(
                                                  'Store',
                                                  style: TextStyle(
                                                      fontSize: 11,
                                                      fontWeight:
                                                          FontWeight.w600,
                                                      color: Color(0xFF007CFF)),
                                                ),
                                              ),
                                            ),
                                          ),
                                          Expanded(
                                            flex: 3,
                                            child: Text(
                                              itemsSummary,
                                              style: const TextStyle(
                                                  fontSize: 13,
                                                  color: Color(0xFF374151)),
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                          SizedBox(
                                            width: 130,
                                            child: Text(
                                              '$_currencySymbol${inv.total.toStringAsFixed(2)}',
                                              textAlign: TextAlign.right,
                                              style: const TextStyle(
                                                fontSize: 14,
                                                fontWeight: FontWeight.w700,
                                                color: Color(0xFF111827),
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  );
                                },
                              ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildGreetingBanner() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 22),
      decoration: BoxDecoration(
        color: CbTokens.surface,
        borderRadius: BorderRadius.circular(CbTokens.radiusLg),
        border: Border.all(color: CbTokens.hairline),
        boxShadow: const [CbTokens.cardShadow],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Welcome back, ${widget.user.username}',
                style: AppTypography.titleLg(CbTokens.ink),
              ),
              const SizedBox(height: 4),
              Text(
                'Here\'s your consolidated billing & finance overview.',
                style: AppTypography.bodySm(CbTokens.muted),
              ),
            ],
          ),
          const Spacer(),
          _buildLayoutToggle(),
          const SizedBox(width: 16),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                DateFormat('EEEE').format(DateTime.now()).toUpperCase(),
                style: AppTypography.captionStrong(CbTokens.muted).copyWith(
                  letterSpacing: 1.0,
                  fontSize: 10,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                DateFormat('MMM d, yyyy').format(DateTime.now()),
                style: AppTypography.titleMd(CbTokens.ink).copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDueSoonSection() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header
        Row(
          children: [
            Container(
              width: 4,
              height: 20,
              decoration: BoxDecoration(
                color: const Color(0xFFD97706),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: 10),
            const Text(
              'Due Soon',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: Color(0xFF0F172A),
              ),
            ),
            const SizedBox(width: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: const Color(0xFFFEF3C7),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: const Color(0xFFFCD34D)),
              ),
              child: Text(
                '${dueSoonInvoices.length} invoice${dueSoonInvoices.length == 1 ? '' : 's'}',
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFFB45309),
                ),
              ),
            ),
            const Spacer(),
            Text(
              'Today & Tomorrow',
              style: TextStyle(
                  fontSize: 13,
                  color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
          ],
        ),
        const SizedBox(height: 14),
        // Cards
        ...dueSoonInvoices.map((invoice) {
          final due = DateTime(invoice.dueDate!.year, invoice.dueDate!.month,
              invoice.dueDate!.day);
          final isToday = due == today;
          final badgeBg =
              isToday ? const Color(0xFFFEE2E2) : const Color(0xFFFEF3C7);
          final badgeBorder =
              isToday ? const Color(0xFFFCA5A5) : const Color(0xFFFCD34D);
          final badgeTextColor =
              isToday ? const Color(0xFFB91C1C) : const Color(0xFFB45309);
          final badgeLabel = isToday ? 'Due Today' : 'Due Tomorrow';

          return Container(
            margin: const EdgeInsets.only(bottom: 10),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                // Due badge
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                  decoration: BoxDecoration(
                    color: badgeBg,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: badgeBorder),
                  ),
                  child: Text(
                    badgeLabel,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: badgeTextColor,
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                // Invoice ID
                Text(
                  '#${invoice.invoiceNumber ?? invoice.id}',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF0F172A),
                  ),
                ),
                const SizedBox(width: 14),
                // Customer
                Expanded(
                  child: Text(
                    invoice.customer.name,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF334155),
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 14),
                // Outstanding amount
                Text(
                  '$_currencySymbol ${invoice.outstandingBalance.toStringAsFixed(2)}',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF0F172A),
                  ),
                ),
                const SizedBox(width: 12),
                // Actions
                FilledButton(
                  onPressed: () =>
                      InvoicePdfServices.showInvoiceDetails(context, invoice),
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF007CFF),
                    foregroundColor: Colors.white,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(6)),
                    textStyle: const TextStyle(
                        fontSize: 12, fontWeight: FontWeight.w600),
                  ),
                  child: const Text('View'),
                ),
                const SizedBox(width: 8),
                OutlinedButton(
                  onPressed: () =>
                      InvoicePdfServices.previewPDF(context, invoice),
                  style: OutlinedButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: const Color(0xFF0F172A),
                    side: const BorderSide(color: Color(0xFFCBD5E1)),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(6)),
                    textStyle: const TextStyle(
                        fontSize: 12, fontWeight: FontWeight.w600),
                  ),
                  child: const Text('Preview'),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: () => showDialog(
                    context: context,
                    barrierDismissible: false,
                    builder: (_) => ApplyPaymentDialog(
                      invoice: invoice,
                      onPaymentRecorded: _loadDashboardData,
                    ),
                  ),
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF16A34A),
                    foregroundColor: Colors.white,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(6)),
                    textStyle: const TextStyle(
                        fontSize: 12, fontWeight: FontWeight.w600),
                  ),
                  child: const Text('Record Payment'),
                ),
              ],
            ),
          );
        }),
      ],
    );
  }

  Widget _buildOverdueSection() {
    final today = InvoiceCalculator.dateOnly(DateTime.now());

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header
        Row(
          children: [
            Container(
              width: 4,
              height: 20,
              decoration: BoxDecoration(
                color: const Color(0xFFDC2626),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: 10),
            const Text(
              'Overdue Invoices',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: Color(0xFF0F172A),
              ),
            ),
            const SizedBox(width: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: const Color(0xFFFEE2E2),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: const Color(0xFFFCA5A5)),
              ),
              child: Text(
                '${overdueInvoices.length} invoice${overdueInvoices.length == 1 ? '' : 's'}',
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFFB91C1C),
                ),
              ),
            ),
            const Spacer(),
            Text(
              'Oldest first',
              style: TextStyle(
                  fontSize: 13,
                  color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
          ],
        ),
        const SizedBox(height: 14),
        ...overdueInvoices.map((invoice) {
          final daysOverdue = InvoiceCalculator.daysOverdue(
            dueDate: invoice.dueDate,
            asOf: today,
          );

          return Container(
            margin: const EdgeInsets.only(bottom: 10),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFFFCA5A5)),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                // Days overdue badge
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFEE2E2),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: const Color(0xFFFCA5A5)),
                  ),
                  child: Text(
                    '$daysOverdue day${daysOverdue == 1 ? '' : 's'} overdue',
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFFB91C1C),
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                // Invoice ID
                Text(
                  '#${invoice.invoiceNumber ?? invoice.id}',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF0F172A),
                  ),
                ),
                const SizedBox(width: 14),
                // Customer
                Expanded(
                  child: Text(
                    invoice.customer.name,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF334155),
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 14),
                // Outstanding amount
                Text(
                  '$_currencySymbol ${invoice.outstandingBalance.toStringAsFixed(2)}',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFFB91C1C),
                  ),
                ),
                const SizedBox(width: 12),
                // Actions
                FilledButton(
                  onPressed: () =>
                      InvoicePdfServices.showInvoiceDetails(context, invoice),
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF007CFF),
                    foregroundColor: Colors.white,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(6)),
                    textStyle: const TextStyle(
                        fontSize: 12, fontWeight: FontWeight.w600),
                  ),
                  child: const Text('View'),
                ),
                const SizedBox(width: 8),
                OutlinedButton(
                  onPressed: () =>
                      InvoicePdfServices.previewPDF(context, invoice),
                  style: OutlinedButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: const Color(0xFF0F172A),
                    side: const BorderSide(color: Color(0xFFCBD5E1)),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(6)),
                    textStyle: const TextStyle(
                        fontSize: 12, fontWeight: FontWeight.w600),
                  ),
                  child: const Text('Preview'),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: () => showDialog(
                    context: context,
                    barrierDismissible: false,
                    builder: (_) => ApplyPaymentDialog(
                      invoice: invoice,
                      onPaymentRecorded: _loadDashboardData,
                    ),
                  ),
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFFDC2626),
                    foregroundColor: Colors.white,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(6)),
                    textStyle: const TextStyle(
                        fontSize: 12, fontWeight: FontWeight.w600),
                  ),
                  child: const Text('Record Payment'),
                ),
              ],
            ),
          );
        }),
      ],
    );
  }

  Future<void> _showUpdateStockDialog(Product product) async {
    final controller = TextEditingController(text: product.stock.toString());
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.inventory_2, color: Colors.red[600], size: 20),
            const SizedBox(width: 8),
            Flexible(
                child: Text(product.name, overflow: TextOverflow.ellipsis)),
          ],
        ),
        content: SizedBox(
          width: 300,
          child: TextField(
            controller: controller,
            keyboardType: TextInputType.number,
            autofocus: true,
            decoration: InputDecoration(
              labelText: 'New Stock Quantity',
              border:
                  OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              prefixIcon: const Icon(Icons.add_box_outlined),
            ),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: () async {
              final qty = int.tryParse(controller.text.trim());
              if (qty == null || qty < 0) return;
              await ref
                  .read(productRepositoryProvider)
                  .updateProductStock(product.id, qty);
              if (ctx.mounted) Navigator.pop(ctx);
              _loadDashboardData();
            },
            child: const Text('Update'),
          ),
        ],
      ),
    );
    controller.dispose();
  }

  Widget _buildOutOfStockSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header
        Row(
          children: [
            Container(
              width: 4,
              height: 24,
              decoration: BoxDecoration(
                color: const Color(0xFFDC2626),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: 12),
            const Text(
              'Out of Stock',
              style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  letterSpacing: -0.3),
            ),
            const SizedBox(width: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: const Color(0xFFFEE2E2),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: const Color(0xFFFCA5A5)),
              ),
              child: Text(
                '${outOfStockProducts.length} item${outOfStockProducts.length == 1 ? '' : 's'}',
                style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFFB91C1C)),
              ),
            ),
            const Spacer(),
            Text(
              'Tap to restock',
              style: TextStyle(
                  fontSize: 13,
                  color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
          ],
        ),
        const SizedBox(height: 16),
        ...outOfStockProducts.map((product) => Container(
              margin: const EdgeInsets.only(bottom: 10),
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFFFCA5A5)),
                ),
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                child: Row(
                  children: [
                    // Name & type
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            product.name,
                            style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF0F172A)),
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            product.type == 'service' ? 'Service' : 'Product',
                            style: const TextStyle(
                                fontSize: 12, color: Color(0xFF64748B)),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 16),
                    // Price
                    Text(
                      '$_currencySymbol${product.price.toStringAsFixed(2)}',
                      style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF0F172A)),
                    ),
                    const SizedBox(width: 16),
                    // Stock badge
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFEE2E2),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: const Color(0xFFFCA5A5)),
                      ),
                      child: Text(
                        'Stock: ${product.stock}',
                        style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFFB91C1C)),
                      ),
                    ),
                    const SizedBox(width: 12),
                    // Update stock button
                    FilledButton(
                      onPressed: () => _showUpdateStockDialog(product),
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF007CFF),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 6),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(6)),
                        textStyle: const TextStyle(
                            fontSize: 12, fontWeight: FontWeight.w600),
                      ),
                      child: const Text('Update Stock'),
                    ),
                  ],
                ),
              ),
            )),
      ],
    );
  }

  Widget _buildStatCard(String title, String value, Color color, IconData icon,
      {String? subtitle, Color? subtitleColor}) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
        decoration: BoxDecoration(
          color: CbTokens.surface,
          borderRadius: BorderRadius.circular(CbTokens.radiusLg),
          border: Border.all(color: CbTokens.hairline),
          boxShadow: const [CbTokens.cardShadow],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              title.toUpperCase(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTypography.captionStrong(CbTokens.muted).copyWith(
                fontSize: 11,
                letterSpacing: 0.9,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTypography.displaySm(CbTokens.ink).copyWith(
                fontSize: 23,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.5,
              ),
            ),
            if (subtitle?.isNotEmpty ?? false) ...[
              const SizedBox(height: 6),
              Text(
                subtitle!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTypography.captionStrong(
                    subtitleColor ?? const Color(0xFFDC2626)),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildPaymentStatusChip(PaymentStatus status) {
    final Color bgColor;
    final Color borderColor;
    final Color textColor;
    final String label;
    switch (status) {
      case PaymentStatus.paid:
        bgColor = const Color(0xFFDCFCE7);
        borderColor = const Color(0xFF86EFAC);
        textColor = const Color(0xFF15803D);
        label = 'Paid';
        break;
      case PaymentStatus.partial:
        bgColor = const Color(0xFFFEF3C7);
        borderColor = const Color(0xFFFCD34D);
        textColor = const Color(0xFFB45309);
        label = 'Partial';
        break;
      case PaymentStatus.unpaid:
        bgColor = const Color(0xFFFEE2E2);
        borderColor = const Color(0xFFFCA5A5);
        textColor = const Color(0xFFB91C1C);
        label = 'Unpaid';
        break;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(5),
        border: Border.all(color: borderColor),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: textColor,
        ),
      ),
    );
  }

  Future<void> _showCloneDialog(Invoice invoice) async {
    final type = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.copy_all, color: Colors.teal),
            SizedBox(width: 12),
            Text('Duplicate Invoice'),
          ],
        ),
        content: Text(
          'Create a copy of Invoice #${invoice.invoiceNumber ?? invoice.id}\n(${invoice.customer.name}) as:',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          OutlinedButton.icon(
            onPressed: () => Navigator.pop(ctx, 'Quotation'),
            icon: const Icon(Icons.request_quote_outlined),
            label: const Text('Quotation'),
          ),
          ElevatedButton.icon(
            onPressed: () => Navigator.pop(ctx, 'Invoice'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Theme.of(context).primaryColor,
              foregroundColor: Colors.white,
            ),
            icon: const Icon(Icons.receipt),
            label: const Text('Invoice'),
          ),
        ],
      ),
    );
    if (type != null) {
      widget.onCloneInvoice(invoice, type);
    }
  }

  void _showDeleteDialog(Invoice invoice) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                  color: Colors.red.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8)),
              child: const Icon(Icons.warning_amber_rounded, color: Colors.red),
            ),
            const SizedBox(width: 12),
            const Text('Delete Invoice'),
          ],
        ),
        content: Text(
          'Are you sure you want to delete Invoice #${invoice.invoiceNumber ?? invoice.id}? This action cannot be undone.',
          style: const TextStyle(fontSize: 15),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel',
                style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant)),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              InvoicePdfServices.deleteInvoice(context, invoice);
              _loadDashboardData();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  // ── Layout Toggle ───────────────────────────────────────────────────────────

  Widget _buildLayoutToggle() {
    return PopupMenuButton<String>(
      icon: Stack(
        clipBehavior: Clip.none,
        children: [
          const Icon(Icons.dashboard_customize_outlined, size: 20),
          if (_showLayoutBanner)
            Positioned(
              top: -3,
              right: -3,
              child: Container(
                width: 8,
                height: 8,
                decoration: const BoxDecoration(
                  color: Colors.red,
                  shape: BoxShape.circle,
                ),
              ),
            ),
        ],
      ),
      tooltip: 'Dashboard Layout',
      offset: const Offset(0, 40),
      onSelected: (value) async {
        if (!mounted) return;
        await ref
            .read(settingsRepositoryProvider)
            .setSetting(SettingKey.dashboardLayout, value);
        setState(() => _dashboardLayout = value);
        if (_showLayoutBanner) _dismissLayoutBanner();
      },
      itemBuilder: (ctx) => [
        _layoutMenuItem('default', Icons.view_agenda_outlined, 'Default',
            'Original layout'),
        _layoutMenuItem('classic', Icons.grid_view_outlined, 'Classic',
            'Charts + KPI grid'),
        _layoutMenuItem('bento', Icons.auto_awesome_mosaic_outlined, 'Bento',
            'Hero chart + card grid'),
        _layoutMenuItem('simple', Icons.view_list_outlined, 'Simple Feed',
            'Clean list view'),
      ],
    );
  }

  PopupMenuItem<String> _layoutMenuItem(
      String value, IconData icon, String title, String sub) {
    final active = _dashboardLayout == value;
    final primary = Theme.of(context).primaryColor;
    return PopupMenuItem(
      value: value,
      child: Row(
        children: [
          Icon(icon,
              size: 18,
              color: active
                  ? primary
                  : Theme.of(context).colorScheme.onSurfaceVariant),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(title,
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight:
                            active ? FontWeight.w700 : FontWeight.normal,
                        color: active
                            ? primary
                            : Theme.of(context).colorScheme.onSurface)),
                Text(sub,
                    style: TextStyle(
                        fontSize: 11,
                        color: Theme.of(context).colorScheme.onSurfaceVariant)),
              ],
            ),
          ),
          if (active) Icon(Icons.check_rounded, size: 16, color: primary),
        ],
      ),
    );
  }

  // ── Layout: Classic ─────────────────────────────────────────────────────────

  Widget _buildClassicLayout() {
    final primary = Theme.of(context).primaryColor;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: AppLayout.maxWidthNormal),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildLayoutDiscoveryBanner(),
              _buildThemeDiscoveryBanner(),
              _buildSupportBanner(),
              _buildGreetingBanner(),
              const SizedBox(height: 20),
              // KPI row
              Row(
                children: [
                  _buildKpiCard(
                      'Revenue Collected',
                      '$_currencySymbol ${_fmtAmt(totalRevenue)}',
                      Icons.account_balance_wallet_outlined,
                      const Color(0xFF6A1B9A)),
                  const SizedBox(width: 10),
                  _buildKpiCard(
                      'Outstanding',
                      '$_currencySymbol ${_fmtAmt(totalOutstanding)}',
                      Icons.hourglass_top_outlined,
                      const Color(0xFFC62828)),
                  const SizedBox(width: 10),
                  _buildKpiCard('Total Invoices', totalInvoices.toString(),
                      Icons.receipt_long_outlined, const Color(0xFFE65100)),
                  const SizedBox(width: 10),
                  _buildKpiCard('Customers', totalCustomers.toString(),
                      Icons.people_outline, const Color(0xFF1565C0)),
                  const SizedBox(width: 10),
                  _buildKpiCard('Products', totalProducts.toString(),
                      Icons.inventory_2_outlined, const Color(0xFF2E7D32)),
                ],
              ),
              const SizedBox(height: 20),
              // Charts row
              IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(flex: 3, child: _buildRevenueBarChart(primary)),
                    const SizedBox(width: 16),
                    Expanded(flex: 2, child: _buildRevenueDonut()),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              // Bottom row
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                      flex: 3, child: _buildCompactRecentInvoices(limit: 7)),
                  const SizedBox(width: 16),
                  Expanded(
                    flex: 2,
                    child: Column(
                      children: [
                        if (dueSoonInvoices.isNotEmpty) ...[
                          _buildDueSoonCard(),
                          const SizedBox(height: 14),
                        ],
                        if (overdueInvoices.isNotEmpty) ...[
                          _buildOverdueCompactCard(),
                          const SizedBox(height: 14),
                        ],
                        if (outOfStockProducts.isNotEmpty) ...[
                          _buildOutOfStockCard(),
                          const SizedBox(height: 14),
                        ],
                        _buildQuickActionsCard(),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  // ── Layout: Simple Feed ─────────────────────────────────────────────────────

  Widget _buildSimpleFeedLayout() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: AppLayout.maxWidthNormal),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildLayoutDiscoveryBanner(),
              _buildThemeDiscoveryBanner(),
              _buildSupportBanner(),
              _buildGreetingBanner(),
              const SizedBox(height: 20),
              // Mini KPI strip
              Row(
                children: [
                  _buildKpiCard(
                      'Revenue',
                      '$_currencySymbol ${_fmtAmt(totalRevenue)}',
                      Icons.account_balance_wallet_outlined,
                      const Color(0xFF6A1B9A)),
                  const SizedBox(width: 12),
                  _buildKpiCard(
                      'Outstanding',
                      '$_currencySymbol ${_fmtAmt(totalOutstanding)}',
                      Icons.hourglass_top_outlined,
                      const Color(0xFFC62828)),
                  const SizedBox(width: 12),
                  _buildKpiCard('Invoices', totalInvoices.toString(),
                      Icons.receipt_long_outlined, const Color(0xFFE65100)),
                  const SizedBox(width: 12),
                  _buildKpiCard('Customers', totalCustomers.toString(),
                      Icons.people_outline, const Color(0xFF1565C0)),
                  const SizedBox(width: 12),
                  _buildKpiCard(
                    'Products',
                    totalProducts.toString(),
                    Icons.inventory_2_outlined,
                    const Color(0xFF2E7D32),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              // Two-column body
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Left: recent invoices + top customers + top products
                  Expanded(
                    flex: 3,
                    child: Column(
                      children: [
                        _buildCompactRecentInvoices(limit: 10),
                        if (_topCustomers.isNotEmpty) ...[
                          const SizedBox(height: 14),
                          _buildTopCustomersCard(),
                        ],
                        if (_topProducts.isNotEmpty) ...[
                          const SizedBox(height: 14),
                          _buildTopProductsCard(),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: 20),
                  // Right sidebar
                  Expanded(
                    flex: 2,
                    child: Column(
                      children: [
                        _buildQuickActionsCard(),
                        const SizedBox(height: 14),
                        if (overdueInvoices.isNotEmpty) ...[
                          _buildOverdueCompactCard(),
                          const SizedBox(height: 14),
                        ],
                        if (dueSoonInvoices.isNotEmpty) ...[
                          _buildDueSoonCard(),
                          const SizedBox(height: 14),
                        ],
                        if (outOfStockProducts.isNotEmpty)
                          _buildOutOfStockCard(),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  // ── Shared: KPI Card ────────────────────────────────────────────────────────

  Widget _buildKpiCard(String title, String value, IconData icon, Color color,
      {bool alert = false}) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainer,
          borderRadius: BorderRadius.circular(14),
          border: alert
              ? Border.all(color: color.withValues(alpha: 0.35), width: 1.5)
              : null,
          boxShadow: [
            BoxShadow(
                color: Colors.black.withValues(alpha: 0.06),
                blurRadius: 12,
                offset: const Offset(0, 3)),
          ],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(9),
              decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10)),
              child: Icon(icon, color: color, size: 19),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(title,
                      style: TextStyle(
                          fontSize: 11,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                          fontWeight: FontWeight.w500),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 3),
                  Text(value,
                      style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Theme.of(context).colorScheme.onSurface),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Shared: Revenue Bar Chart ────────────────────────────────────────────────

  Widget _buildRevenueBarChart(Color primary) {
    final hasData = _monthlyRevenue.isNotEmpty;
    final maxY = hasData
        ? _monthlyRevenue
                .map((e) => (e['revenue'] as num).toDouble())
                .reduce((a, b) => a > b ? a : b) *
            1.25
        : 1000.0;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainer,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 12,
              offset: const Offset(0, 3))
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('Revenue — Last 6 Months',
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: Theme.of(context).colorScheme.onSurface)),
          const SizedBox(height: 16),
          SizedBox(
            height: 190,
            child: hasData
                ? BarChart(
                    BarChartData(
                      alignment: BarChartAlignment.spaceAround,
                      maxY: maxY,
                      barGroups: _monthlyRevenue.asMap().entries.map((entry) {
                        final rev = (entry.value['revenue'] as num).toDouble();
                        return BarChartGroupData(
                          x: entry.key,
                          barRods: [
                            BarChartRodData(
                              toY: rev,
                              gradient: LinearGradient(
                                colors: [
                                  primary,
                                  primary.withValues(alpha: 0.55)
                                ],
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                              ),
                              width: 28,
                              borderRadius: const BorderRadius.vertical(
                                  top: Radius.circular(6)),
                            ),
                          ],
                        );
                      }).toList(),
                      titlesData: FlTitlesData(
                        leftTitles: const AxisTitles(
                            sideTitles: SideTitles(showTitles: false)),
                        rightTitles: const AxisTitles(
                            sideTitles: SideTitles(showTitles: false)),
                        topTitles: const AxisTitles(
                            sideTitles: SideTitles(showTitles: false)),
                        bottomTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            getTitlesWidget: (value, meta) {
                              final idx = value.toInt();
                              if (idx < 0 || idx >= _monthlyRevenue.length) {
                                return const SizedBox.shrink();
                              }
                              final monthStr =
                                  _monthlyRevenue[idx]['month'] as String;
                              try {
                                final date =
                                    DateFormat('yyyy-MM').parse(monthStr);
                                return Padding(
                                  padding: const EdgeInsets.only(top: 5),
                                  child: Text(DateFormat('MMM').format(date),
                                      style: TextStyle(
                                          fontSize: 11,
                                          color: Theme.of(context)
                                              .colorScheme
                                              .onSurfaceVariant)),
                                );
                              } catch (_) {
                                return const SizedBox.shrink();
                              }
                            },
                          ),
                        ),
                      ),
                      gridData: FlGridData(
                        show: true,
                        drawVerticalLine: false,
                        getDrawingHorizontalLine: (_) => FlLine(
                            color: Colors.grey.withValues(alpha: 0.12),
                            strokeWidth: 1),
                      ),
                      borderData: FlBorderData(show: false),
                      barTouchData: BarTouchData(
                        touchTooltipData: BarTouchTooltipData(
                          getTooltipItem: (group, _, rod, __) => BarTooltipItem(
                            '$_currencySymbol ${_fmtAmt(rod.toY)}',
                            const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 13),
                          ),
                        ),
                      ),
                    ),
                  )
                : Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.bar_chart_outlined,
                            size: 48,
                            color:
                                Theme.of(context).colorScheme.outlineVariant),
                        const SizedBox(height: 8),
                        Text('No payment data yet',
                            style: TextStyle(
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant,
                                fontSize: 13)),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  // ── Shared: Revenue Donut ────────────────────────────────────────────────────

  Widget _buildRevenueDonut() {
    final total = totalRevenue + totalOutstanding;
    final hasData = total > 0.01;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainer,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 12,
              offset: const Offset(0, 3))
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('Financial Overview',
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: Theme.of(context).colorScheme.onSurface)),
          const SizedBox(height: 12),
          SizedBox(
            height: 160,
            child: hasData
                ? PieChart(
                    PieChartData(
                      centerSpaceRadius: 46,
                      sectionsSpace: 3,
                      sections: [
                        PieChartSectionData(
                          value: totalRevenue,
                          color: const Color(0xFF2E7D32),
                          title: '',
                          radius: 38,
                        ),
                        PieChartSectionData(
                          value: totalOutstanding,
                          color: const Color(0xFFC62828),
                          title: '',
                          radius: 38,
                        ),
                      ],
                    ),
                  )
                : Center(
                    child: Text('No invoices yet',
                        style: TextStyle(
                            color:
                                Theme.of(context).colorScheme.onSurfaceVariant,
                            fontSize: 13))),
          ),
          const SizedBox(height: 14),
          _buildDonutLegend('Collected', const Color(0xFF2E7D32),
              '$_currencySymbol ${_fmtAmt(totalRevenue)}'),
          const SizedBox(height: 6),
          _buildDonutLegend('Outstanding', const Color(0xFFC62828),
              '$_currencySymbol ${_fmtAmt(totalOutstanding)}'),
          if (overdueInvoices.isNotEmpty) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: const Color(0xFFB71C1C).withValues(alpha: 0.07),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  const Icon(Icons.warning_amber_rounded,
                      size: 13, color: Color(0xFFB71C1C)),
                  const SizedBox(width: 6),
                  Text(
                      '${overdueInvoices.length} invoice${overdueInvoices.length == 1 ? '' : 's'} overdue',
                      style: const TextStyle(
                          fontSize: 12,
                          color: Color(0xFFB71C1C),
                          fontWeight: FontWeight.w600)),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildDonutLegend(String label, Color color, String amount) {
    return Row(
      children: [
        Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 8),
        Expanded(
            child: Text(label,
                style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.onSurfaceVariant))),
        Text(amount,
            style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: Theme.of(context).colorScheme.onSurface)),
      ],
    );
  }

  // ── Shared: Compact Recent Invoices ─────────────────────────────────────────

  Widget _buildCompactRecentInvoices({int limit = 7}) {
    final invoices = recentInvoices.take(limit).toList();
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainer,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 12,
              offset: const Offset(0, 3))
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Text('Recent Invoices',
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: Theme.of(context).colorScheme.onSurface)),
              const Spacer(),
              Text('Last $limit',
                  style: TextStyle(
                      fontSize: 11,
                      color: Theme.of(context).colorScheme.onSurfaceVariant)),
            ],
          ),
          const SizedBox(height: 4),
          // Header row — solid brand blue per Yatri Cloud reference
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFF007CFF),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Row(
              children: const [
                Expanded(
                    flex: 2,
                    child: Text('Invoice',
                        style: TextStyle(
                            fontSize: 11,
                            color: Colors.white,
                            fontWeight: FontWeight.w600))),
                Expanded(
                    flex: 3,
                    child: Text('Customer',
                        style: TextStyle(
                            fontSize: 11,
                            color: Colors.white,
                            fontWeight: FontWeight.w600))),
                Expanded(
                    flex: 2,
                    child: Text('Amount',
                        textAlign: TextAlign.right,
                        style: TextStyle(
                            fontSize: 11,
                            color: Colors.white,
                            fontWeight: FontWeight.w600))),
                SizedBox(width: 60),
              ],
            ),
          ),
          Divider(
              height: 1,
              thickness: 1,
              color: Theme.of(context).colorScheme.outlineVariant),
          const SizedBox(height: 4),
          if (invoices.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 32),
              child: Center(
                  child: Text('No invoices yet',
                      style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                          fontSize: 13))),
            )
          else
            ...invoices.map(_buildCompactInvoiceRow),
        ],
      ),
    );
  }

  Widget _buildCompactInvoiceRow(Invoice inv) {
    final status = inv.paymentStatus;
    final Color statusColor;
    final String statusLabel;
    switch (status) {
      case PaymentStatus.paid:
        statusColor = const Color(0xFF2E7D32);
        statusLabel = 'Paid';
        break;
      case PaymentStatus.partial:
        statusColor = const Color(0xFFF57C00);
        statusLabel = 'Partial';
        break;
      default:
        final isOver = InvoiceCalculator.isOverdue(
            dueDate: inv.dueDate, outstanding: inv.outstandingBalance);
        statusColor =
            isOver ? const Color(0xFFC62828) : const Color(0xFF546E7A);
        statusLabel = isOver ? 'Overdue' : 'Unpaid';
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: Text(
                '#${inv.id.length > 8 ? inv.id.substring(inv.id.length - 8) : inv.id}',
                style:
                    const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                maxLines: 1,
                overflow: TextOverflow.ellipsis),
          ),
          Expanded(
            flex: 3,
            child: Text(inv.customer.name,
                style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.onSurfaceVariant),
                maxLines: 1,
                overflow: TextOverflow.ellipsis),
          ),
          Expanded(
            flex: 2,
            child: Text('$_currencySymbol ${_fmtAmt(inv.total)}',
                style:
                    const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                textAlign: TextAlign.right,
                maxLines: 1),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
            decoration: BoxDecoration(
                color: statusColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(6)),
            child: Text(statusLabel,
                style: TextStyle(
                    fontSize: 10,
                    color: statusColor,
                    fontWeight: FontWeight.w700)),
          ),
          const SizedBox(width: 8),
          Tooltip(
            message: 'Edit',
            child: InkWell(
              onTap: () => widget.onEditInvoice(inv),
              borderRadius: BorderRadius.circular(6),
              child: Padding(
                padding: const EdgeInsets.all(4),
                child: Icon(Icons.edit_outlined,
                    size: 15,
                    color: Theme.of(context).colorScheme.onSurfaceVariant),
              ),
            ),
          ),
          const SizedBox(width: 2),
          Tooltip(
            message: 'Download PDF',
            child: InkWell(
              onTap: () => PDFService.downloadPDF(context, inv),
              borderRadius: BorderRadius.circular(6),
              child: Padding(
                padding: const EdgeInsets.all(4),
                child: Icon(Icons.download_outlined,
                    size: 15,
                    color: Theme.of(context).colorScheme.onSurfaceVariant),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Shared: Due Soon Card ────────────────────────────────────────────────────

  Widget _buildDueSoonCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainer,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 12,
              offset: const Offset(0, 3))
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                    color: const Color(0xFFF57C00).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8)),
                child: const Icon(Icons.event_outlined,
                    color: Color(0xFFF57C00), size: 15),
              ),
              const SizedBox(width: 8),
              Text('Due Soon',
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: Theme.of(context).colorScheme.onSurface)),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                    color: const Color(0xFFF57C00).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10)),
                child: Text('${dueSoonInvoices.length}',
                    style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFFF57C00),
                        fontWeight: FontWeight.w700)),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ...dueSoonInvoices.take(5).map((inv) => Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  children: [
                    Expanded(
                        child: Text(inv.customer.name,
                            style: const TextStyle(fontSize: 12),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis)),
                    Text('$_currencySymbol ${_fmtAmt(inv.outstandingBalance)}',
                        style: const TextStyle(
                            fontSize: 12, fontWeight: FontWeight.w600)),
                    const SizedBox(width: 2),
                    _buildInvoiceActionMenu(inv),
                  ],
                ),
              )),
        ],
      ),
    );
  }

  // ── Shared: Out of Stock Card ────────────────────────────────────────────────

  Widget _buildOutOfStockCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainer,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.red.withValues(alpha: 0.18), width: 1),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 10,
              offset: const Offset(0, 2))
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                    color: Colors.red.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8)),
                child: const Icon(Icons.inventory_2_outlined,
                    color: Colors.red, size: 15),
              ),
              const SizedBox(width: 8),
              Text('Out of Stock',
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: Theme.of(context).colorScheme.onSurface)),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                    color: Colors.red.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10)),
                child: Text('${outOfStockProducts.length}',
                    style: const TextStyle(
                        fontSize: 12,
                        color: Colors.red,
                        fontWeight: FontWeight.w700)),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ...outOfStockProducts.take(5).map((p) => Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  children: [
                    Expanded(
                        child: Text(p.name,
                            style: const TextStyle(fontSize: 12),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis)),
                    const Text('0 left',
                        style: TextStyle(
                            fontSize: 12,
                            color: Colors.red,
                            fontWeight: FontWeight.w600)),
                    const SizedBox(width: 6),
                    Tooltip(
                      message: 'Update Stock',
                      child: InkWell(
                        onTap: () => _showUpdateStockDialog(p),
                        borderRadius: BorderRadius.circular(7),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 5),
                          decoration: BoxDecoration(
                            color: Colors.green.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(7),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.add_box_outlined,
                                  size: 13, color: Colors.green),
                              SizedBox(width: 4),
                              Text('Stock',
                                  style: TextStyle(
                                      fontSize: 11,
                                      color: Colors.green,
                                      fontWeight: FontWeight.w600)),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              )),
        ],
      ),
    );
  }

  // ── Shared: Overdue Compact Card ─────────────────────────────────────────────

  Widget _buildOverdueCompactCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainer,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
            color: const Color(0xFFC62828).withValues(alpha: 0.2), width: 1),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 10,
              offset: const Offset(0, 2))
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                    color: const Color(0xFFC62828).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8)),
                child: const Icon(Icons.warning_amber_rounded,
                    color: Color(0xFFC62828), size: 15),
              ),
              const SizedBox(width: 8),
              Text('Overdue',
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: Theme.of(context).colorScheme.onSurface)),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                    color: const Color(0xFFC62828).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10)),
                child: Text('${overdueInvoices.length}',
                    style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFFC62828),
                        fontWeight: FontWeight.w700)),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ...overdueInvoices.take(5).map((inv) => Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  children: [
                    Expanded(
                        child: Text(inv.customer.name,
                            style: const TextStyle(fontSize: 12),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis)),
                    Text('$_currencySymbol ${_fmtAmt(inv.outstandingBalance)}',
                        style: const TextStyle(
                            fontSize: 12,
                            color: Color(0xFFC62828),
                            fontWeight: FontWeight.w600)),
                    const SizedBox(width: 4),
                    Tooltip(
                      message: 'Record Payment',
                      child: InkWell(
                        onTap: () => showDialog(
                          context: context,
                          barrierDismissible: false,
                          builder: (_) => ApplyPaymentDialog(
                            invoice: inv,
                            onPaymentRecorded: _loadDashboardData,
                          ),
                        ),
                        borderRadius: BorderRadius.circular(7),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 5),
                          decoration: BoxDecoration(
                            color:
                                const Color(0xFF6A1B9A).withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(7),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.payments_outlined,
                                  size: 13, color: Color(0xFF6A1B9A)),
                              SizedBox(width: 4),
                              Text('Pay',
                                  style: TextStyle(
                                      fontSize: 11,
                                      color: Color(0xFF6A1B9A),
                                      fontWeight: FontWeight.w600)),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 2),
                    _buildPdfActionMenu(inv),
                  ],
                ),
              )),
        ],
      ),
    );
  }

  // ── Shared: Quick Actions Card ───────────────────────────────────────────────

  Widget _buildQuickActionsCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainer,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 12,
              offset: const Offset(0, 3))
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('Quick Actions',
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: Theme.of(context).colorScheme.onSurface)),
          const SizedBox(height: 12),
          _buildQuickActionRow(Icons.add_circle_outline_rounded, 'New Invoice',
              Theme.of(context).primaryColor, () {
            if (!mounted) return;
            context
                .findAncestorStateOfType<_DashboardScreenState>()
                ?.setState(() {
              context
                  .findAncestorStateOfType<_DashboardScreenState>()
                  ?._selectedIndex = 1;
            });
          }),
          const SizedBox(height: 4),
          _buildQuickActionRow(
              Icons.person_add_outlined, 'Customers', const Color(0xFF1565C0),
              () {
            if (!mounted) return;
            context
                .findAncestorStateOfType<_DashboardScreenState>()
                ?.setState(() {
              context
                  .findAncestorStateOfType<_DashboardScreenState>()
                  ?._selectedIndex = 5;
            });
          }),
          const SizedBox(height: 4),
          _buildQuickActionRow(
              Icons.bar_chart_outlined, 'Reports', const Color(0xFF2E7D32), () {
            if (!mounted) return;
            context
                .findAncestorStateOfType<_DashboardScreenState>()
                ?.setState(() {
              context
                  .findAncestorStateOfType<_DashboardScreenState>()
                  ?._selectedIndex = 7;
            });
          }),
        ],
      ),
    );
  }

  Widget _buildQuickActionRow(
      IconData icon, String label, Color color, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 4),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(7),
              decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8)),
              child: Icon(icon, color: color, size: 15),
            ),
            const SizedBox(width: 10),
            Expanded(
                child: Text(label,
                    style: TextStyle(
                        fontSize: 13,
                        color: Theme.of(context).colorScheme.onSurface,
                        fontWeight: FontWeight.w500))),
            Icon(Icons.chevron_right_rounded,
                size: 16,
                color: Theme.of(context).colorScheme.onSurfaceVariant),
          ],
        ),
      ),
    );
  }

  // ── Shared: Amount Formatter ─────────────────────────────────────────────────

  String _fmtAmt(double amount) {
    if (amount >= 10000000) {
      return '${(amount / 10000000).toStringAsFixed(2)}Cr';
    }
    if (amount >= 100000) return '${(amount / 100000).toStringAsFixed(2)}L';
    if (amount >= 1000) return '${(amount / 1000).toStringAsFixed(1)}K';
    return amount.toStringAsFixed(2);
  }

  // ── Layout: Bento Grid ──────────────────────────────────────────────────────

  Widget _buildBentoLayout() {
    final primary = Theme.of(context).primaryColor;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: AppLayout.maxWidthNormal),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildLayoutDiscoveryBanner(),
              _buildThemeDiscoveryBanner(),
              _buildSupportBanner(),
              _buildGreetingBanner(),
              const SizedBox(height: 20),
              // ── Top row: Hero chart + 2×2 KPI grid ──────────────────────────
              SizedBox(
                height: 290,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Hero: Revenue bar chart
                    Expanded(
                      flex: 3,
                      child: _buildRevenueBarChart(primary),
                    ),
                    const SizedBox(width: 14),
                    // 2×2 KPI tiles
                    Expanded(
                      flex: 2,
                      child: Column(
                        children: [
                          Expanded(
                            child: Row(
                              children: [
                                _buildKpiCard(
                                  'Revenue',
                                  '$_currencySymbol ${_fmtAmt(totalRevenue)}',
                                  Icons.account_balance_wallet_outlined,
                                  const Color(0xFF6A1B9A),
                                ),
                                const SizedBox(width: 14),
                                _buildKpiCard(
                                  'Invoices',
                                  totalInvoices.toString(),
                                  Icons.receipt_long_outlined,
                                  const Color(0xFFE65100),
                                ),
                              ],
                            ),
                          ),
                          Expanded(
                            child: Row(
                              children: [
                                _buildKpiCard(
                                  'Outstanding',
                                  '$_currencySymbol ${_fmtAmt(totalOutstanding)}',
                                  Icons.hourglass_top_outlined,
                                  const Color(0xFFC62828),
                                ),
                                const SizedBox(width: 14),
                                _buildKpiCard(
                                  'Overdue',
                                  overdueInvoices.length.toString(),
                                  Icons.warning_amber_outlined,
                                  const Color(0xFFB71C1C),
                                  alert: overdueInvoices.isNotEmpty,
                                ),
                              ],
                            ),
                          ),
                          Expanded(
                            child: Row(
                              children: [
                                _buildKpiCard(
                                    'Customers',
                                    totalCustomers.toString(),
                                    Icons.people_outline,
                                    const Color(0xFF1565C0)),
                                const SizedBox(width: 14),
                                _buildKpiCard(
                                  'Products',
                                  totalProducts.toString(),
                                  Icons.inventory_2_outlined,
                                  const Color(0xFF2E7D32),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              // ── Bottom row: Wide invoice table + narrow sidebar ───────────────
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    flex: 3,
                    child: Column(
                      children: [
                        _buildCompactRecentInvoices(limit: 8),
                        if (_topProducts.isNotEmpty) ...[
                          const SizedBox(height: 14),
                          _buildTopProductsCard(),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    flex: 2,
                    child: Column(
                      children: [
                        _buildQuickActionsCard(),
                        if (overdueInvoices.isNotEmpty) ...[
                          const SizedBox(height: 14),
                          _buildOverdueCompactCard(),
                        ],
                        if (dueSoonInvoices.isNotEmpty) ...[
                          const SizedBox(height: 14),
                          _buildDueSoonCard(),
                        ],
                        if (outOfStockProducts.isNotEmpty) ...[
                          const SizedBox(height: 14),
                          _buildOutOfStockCard(),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  // ── Shared: PDF-Only Action Menu (⋯) ───────────────────────────────────────

  Widget _buildPdfActionMenu(Invoice inv) {
    return PopupMenuButton<String>(
      icon: Icon(Icons.more_vert_rounded,
          size: 15, color: Theme.of(context).colorScheme.onSurfaceVariant),
      iconSize: 22,
      padding: EdgeInsets.zero,
      tooltip: 'PDF Actions',
      offset: const Offset(0, 24),
      onSelected: (value) {
        if (value == 'preview') {
          InvoicePdfServices.previewPDF(context, inv);
        } else if (value == 'download') {
          PDFService.downloadPDF(context, inv);
        }
      },
      itemBuilder: (ctx) => const [
        PopupMenuItem(
          value: 'preview',
          child: Row(children: [
            Icon(Icons.visibility_outlined, size: 16, color: Colors.green),
            SizedBox(width: 10),
            Text('Preview PDF', style: TextStyle(fontSize: 13)),
          ]),
        ),
        PopupMenuItem(
          value: 'download',
          child: Row(children: [
            Icon(Icons.download_outlined, size: 16, color: Colors.deepPurple),
            SizedBox(width: 10),
            Text('Download PDF', style: TextStyle(fontSize: 13)),
          ]),
        ),
      ],
    );
  }

  // ── Shared: Invoice Action Menu (⋯) ────────────────────────────────────────

  Widget _buildInvoiceActionMenu(Invoice inv) {
    return PopupMenuButton<String>(
      icon: Icon(Icons.more_vert_rounded,
          size: 15, color: Theme.of(context).colorScheme.onSurfaceVariant),
      iconSize: 22,
      padding: EdgeInsets.zero,
      tooltip: 'Actions',
      offset: const Offset(0, 24),
      onSelected: (value) {
        switch (value) {
          case 'payment':
            showDialog(
              context: context,
              barrierDismissible: false,
              builder: (_) => ApplyPaymentDialog(
                invoice: inv,
                onPaymentRecorded: _loadDashboardData,
              ),
            );
            break;
          case 'preview':
            InvoicePdfServices.previewPDF(context, inv);
            break;
          case 'download':
            PDFService.downloadPDF(context, inv);
            break;
        }
      },
      itemBuilder: (ctx) => const [
        PopupMenuItem(
          value: 'payment',
          child: Row(children: [
            Icon(Icons.payments_outlined, size: 16, color: Color(0xFF6A1B9A)),
            SizedBox(width: 10),
            Text('Record Payment', style: TextStyle(fontSize: 13)),
          ]),
        ),
        PopupMenuItem(
          value: 'preview',
          child: Row(children: [
            Icon(Icons.visibility_outlined, size: 16, color: Colors.green),
            SizedBox(width: 10),
            Text('Preview PDF', style: TextStyle(fontSize: 13)),
          ]),
        ),
        PopupMenuItem(
          value: 'download',
          child: Row(children: [
            Icon(Icons.download_outlined, size: 16, color: Colors.deepPurple),
            SizedBox(width: 10),
            Text('Download PDF', style: TextStyle(fontSize: 13)),
          ]),
        ),
      ],
    );
  }

  // ── Shared: Top Customers Card ───────────────────────────────────────────────

  Widget _buildTopCustomersCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainer,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 12,
              offset: const Offset(0, 3))
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                    color: const Color(0xFF1565C0).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8)),
                child: const Icon(Icons.emoji_events_outlined,
                    color: Color(0xFF1565C0), size: 15),
              ),
              const SizedBox(width: 8),
              Text('Top Customers',
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: Theme.of(context).colorScheme.onSurface)),
            ],
          ),
          const SizedBox(height: 12),
          ..._topCustomers.map((c) {
            final name = c['customer_name'] as String? ?? '';
            final paid = (c['total_paid'] as num).toDouble();
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 13,
                    backgroundColor:
                        const Color(0xFF1565C0).withValues(alpha: 0.1),
                    child: Text(
                      name.isNotEmpty ? name[0].toUpperCase() : '?',
                      style: const TextStyle(
                          fontSize: 11,
                          color: Color(0xFF1565C0),
                          fontWeight: FontWeight.bold),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                      child: Text(name,
                          style: const TextStyle(fontSize: 12),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis)),
                  Text('$_currencySymbol ${_fmtAmt(paid)}',
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Theme.of(context).colorScheme.onSurface)),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  // ── Shared: Top Products Card ────────────────────────────────────────────────

  Widget _buildTopProductsCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainer,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 12,
              offset: const Offset(0, 3))
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                    color: const Color(0xFF2E7D32).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8)),
                child: const Icon(Icons.trending_up_outlined,
                    color: Color(0xFF2E7D32), size: 15),
              ),
              const SizedBox(width: 8),
              Text('Top Products',
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: Theme.of(context).colorScheme.onSurface)),
            ],
          ),
          const SizedBox(height: 12),
          ..._topProducts.map((p) {
            final name = p['product_name'] as String? ?? '';
            final qty = (p['total_qty'] as num).toDouble();
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(5),
                    decoration: BoxDecoration(
                        color: const Color(0xFF2E7D32).withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(7)),
                    child: const Icon(Icons.inventory_2_outlined,
                        size: 13, color: Color(0xFF2E7D32)),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                      child: Text(name,
                          style: const TextStyle(fontSize: 12),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis)),
                  Text(
                      '${qty % 1 == 0 ? qty.toInt() : qty.toStringAsFixed(1)} units',
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Theme.of(context).colorScheme.onSurface)),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }
}

class _BetaTag extends StatelessWidget {
  const _BetaTag();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: const Color(0xFF7C3AED),
        borderRadius: BorderRadius.circular(4),
      ),
      child: const Text(
        'BETA',
        style: TextStyle(
          fontSize: 9,
          fontWeight: FontWeight.w700,
          color: Colors.white,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}
