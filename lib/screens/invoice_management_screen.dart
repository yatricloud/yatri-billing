import 'dart:async';
import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:invoiso/common.dart';
import 'package:invoiso/constants.dart';
import 'package:invoiso/domain/invoice_calculator.dart';
import 'package:invoiso/models/invoice.dart';
import 'package:invoiso/providers/invoice_provider.dart';
import 'package:invoiso/providers/repositories.dart';
import 'package:file_picker/file_picker.dart';
import 'package:invoiso/services/export_service.dart';
import 'package:invoiso/services/invoice_pdf_services.dart';
import 'package:invoiso/services/pdf_service.dart';
import 'package:invoiso/widgets/apply_payment_dialog.dart';
import 'package:invoiso/utils/error_handler.dart';
import 'package:intl/intl.dart';
import 'package:open_file/open_file.dart';
import 'package:invoiso/models/user.dart';
import 'package:invoiso/widgets/customer_info_button.dart';
import 'package:invoiso/utils/formatters.dart';

class InvoiceManagementScreen extends ConsumerStatefulWidget {
  final Function(Invoice) onEditInvoice;
  final Function(Invoice, String) onCloneInvoice;
  final User user;
  final String filterType; // 'Invoice' | 'Quotation'

  const InvoiceManagementScreen({
    super.key,
    required this.onEditInvoice,
    required this.onCloneInvoice,
    required this.user,
    this.filterType = 'Invoice',
  });

  @override
  ConsumerState<InvoiceManagementScreen> createState() =>
      _InvoiceManagementScreenState();
}

class _InvoiceManagementScreenState
    extends ConsumerState<InvoiceManagementScreen> {
  int _currentPage = 0;
  int _pageSize = 10;
  String _searchQuery = '';
  bool _isLoadingPage = false;
  bool _isBulkLoading = false;
  bool _hidePaid = false;
  String _dueDateFilter =
      'all'; // 'all' | 'overdue' | 'due_today' | 'due_week' | 'due_month'
  String _datePattern = 'dd/MM/yyyy';
  int _totalCount = 0;
  List<Invoice> _pageInvoices = [];
  final Set<String> _selectedIds = {};
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  final ScrollController _statsBarScrollController = ScrollController();
  Timer? _searchDebounce;

  /// Shared column widths used by both the header table and every row table so
  /// they always align pixel-perfectly.
  static const List<(String, String)> _dueDateFilterOptions = [
    ('all', 'All Dues'),
    ('overdue', 'Overdue'),
    ('due_today', 'Due Today'),
    ('due_week', 'Due This Week'),
    ('due_month', 'Due This Month'),
  ];

  // Invoice table: checkbox | # | ID | Customer | Date | Items | Total | Status | Outstanding | Actions
  static const Map<int, TableColumnWidth> _invoiceColumnWidths = {
    0: FixedColumnWidth(44),   // Checkbox
    1: FixedColumnWidth(50),   // # Index
    2: FixedColumnWidth(115),  // Invoice ID (e.g. #000001 never truncates)
    3: FlexColumnWidth(2.2),   // Customer Name
    4: FixedColumnWidth(125),  // Date
    5: FixedColumnWidth(64),   // Items count
    6: FixedColumnWidth(130),  // Total
    7: FixedColumnWidth(95),   // Status badge
    8: FixedColumnWidth(130),  // Outstanding
    9: FixedColumnWidth(145),  // Actions
  };

  // Quotation table: checkbox | # | ID | Customer | Date | Items | Total | Actions
  static const Map<int, TableColumnWidth> _quotationColumnWidths = {
    0: FixedColumnWidth(44),   // Checkbox
    1: FixedColumnWidth(50),   // # Index
    2: FixedColumnWidth(115),  // Quotation ID
    3: FlexColumnWidth(2.5),   // Customer
    4: FixedColumnWidth(125),  // Date
    5: FixedColumnWidth(64),   // Items
    6: FixedColumnWidth(130),  // Total
    7: FixedColumnWidth(145),  // Actions
  };

  Map<int, TableColumnWidth> get _columnWidths =>
      widget.filterType != 'Invoice'
          ? _quotationColumnWidths
          : _invoiceColumnWidths;


  // ─── Lifecycle ─────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _loadPage();
    _loadDateFormat();
  }

  Future<void> _loadDateFormat() async {
    final opt = await ref.read(settingsRepositoryProvider).getDateFormat();
    if (mounted) setState(() => _datePattern = opt.key);
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();
    _statsBarScrollController.dispose();
    _searchDebounce?.cancel();
    super.dispose();
  }

  // ─── Data loading ──────────────────────────────────────────────────────────

  Future<void> _loadPage() async {
    setState(() {
      _isLoadingPage = true;
      _selectedIds.clear(); // selection reset on every page/search change
    });
    try {
      final results = await Future.wait([
        ref.read(invoiceRepositoryProvider).getInvoicesPaginated(
          page: _currentPage,
          pageSize: _pageSize,
          searchQuery: _searchQuery,
          filterType: widget.filterType,
        ),
        ref.read(invoiceRepositoryProvider).getInvoiceCount(
          searchQuery: _searchQuery,
          filterType: widget.filterType,
        ),
      ]);
      if (mounted) {
        var pageInvoices = results[0] as List<Invoice>;
        if (_hidePaid) {
          // Keep Quotations; for Invoices only keep those with an outstanding balance
          pageInvoices = pageInvoices
              .where((inv) =>
                  inv.type != 'Invoice' ||
                  inv.outstandingBalance > InvoiceCalculator.moneyEpsilon)
              .toList();
        }
        if (_dueDateFilter != 'all') {
          pageInvoices = pageInvoices.where((inv) {
            if (inv.dueDate == null) return false;
            final today = InvoiceCalculator.dateOnly(DateTime.now());
            final due = InvoiceCalculator.dateOnly(inv.dueDate!);
            switch (_dueDateFilter) {
              case 'overdue':
                return InvoiceCalculator.isOverdue(
                  dueDate: inv.dueDate,
                  outstanding: inv.outstandingBalance,
                );
              case 'due_today':
                return due == today;
              case 'due_week':
                return !due.isBefore(today) &&
                    due.isBefore(today.add(const Duration(days: 7)));
              case 'due_month':
                return !due.isBefore(today) &&
                    due.isBefore(
                        DateTime(today.year, today.month + 1, today.day));
              default:
                return true;
            }
          }).toList();
        }
        setState(() {
          _pageInvoices = pageInvoices;
          _totalCount = results[1] as int;
          _isLoadingPage = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoadingPage = false);
        AppError.show(context, 'Failed to load invoices: $e',
            onRetry: _loadPage);
      }
    }
  }

  // ─── Selection helpers ─────────────────────────────────────────────────────

  bool get _isAllPageSelected =>
      _pageInvoices.isNotEmpty &&
      _pageInvoices.every((inv) => _selectedIds.contains(inv.id));

  bool get _isSomePageSelected =>
      _pageInvoices.any((inv) => _selectedIds.contains(inv.id));

  void _toggleSelectAll() {
    setState(() {
      if (_isAllPageSelected) {
        for (final inv in _pageInvoices) {
          _selectedIds.remove(inv.id);
        }
      } else {
        for (final inv in _pageInvoices) {
          _selectedIds.add(inv.id);
        }
      }
    });
  }

  void _toggleOne(String id) {
    setState(() {
      if (_selectedIds.contains(id)) {
        _selectedIds.remove(id);
      } else {
        _selectedIds.add(id);
      }
    });
  }

  // ─── Per-row actions ───────────────────────────────────────────────────────

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

  Future<void> _softDelete(Invoice invoice) async {
    final confirmed = await AppError.confirm(
      context,
      title: 'Move to Trash',
      message: 'Move Invoice #${invoice.invoiceNumber ?? invoice.id} to trash?',
      confirmLabel: 'Move to Trash',
      confirmColor: Colors.orange,
    );
    if (!confirmed) return;

    await ref.read(invoiceRepositoryProvider).softDeleteInvoice(invoice.id);
    ref.read(invoicesProvider.notifier).refresh();
    await _loadPage();
    if (mounted) AppError.showSuccess(context, 'Invoice moved to trash.');
  }

  // ─── Toolbar actions ───────────────────────────────────────────────────────

  Future<void> _exportCsv() async {
    final fmt = DateFormat(_datePattern);
    DateTime? fromDate;
    DateTime? toDate;
    bool exportAll = false;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          title: Row(
            children: [
              Icon(Icons.file_download_outlined,
                  color: Theme.of(context).primaryColor),
              const SizedBox(width: 10),
              Text('Export ${widget.filterType}s to CSV'),
            ],
          ),
          content: SizedBox(
            width: 400,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Export All toggle
                InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap: () => setS(() {
                    exportAll = !exportAll;
                    if (exportAll) {
                      fromDate = null;
                      toDate = null;
                    }
                  }),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      children: [
                        Checkbox(
                          value: exportAll,
                          onChanged: (v) => setS(() {
                            exportAll = v ?? false;
                            if (exportAll) {
                              fromDate = null;
                              toDate = null;
                            }
                          }),
                        ),
                        const SizedBox(width: 4),
                        const Text('Export All Records',
                            style: TextStyle(
                                fontSize: 14, fontWeight: FontWeight.w500)),
                      ],
                    ),
                  ),
                ),
                const Divider(height: 20),
                // Date range pickers
                Opacity(
                  opacity: exportAll ? 0.35 : 1.0,
                  child: AbsorbPointer(
                    absorbing: exportAll,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Or filter by date range:',
                          style: TextStyle(fontSize: 13, color: Theme.of(context).colorScheme.onSurfaceVariant),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: _DatePickerField(
                                label: 'From Date',
                                value: fromDate,
                                formatter: fmt,
                                onPicked: (d) => setS(() => fromDate = d),
                                onCleared: () => setS(() => fromDate = null),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: _DatePickerField(
                                label: 'To Date',
                                value: toDate,
                                formatter: fmt,
                                onPicked: (d) => setS(() => toDate = d),
                                onCleared: () => setS(() => toDate = null),
                              ),
                            ),
                          ],
                        ),
                        if (fromDate != null &&
                            toDate != null &&
                            toDate!.isBefore(fromDate!)) ...[
                          const SizedBox(height: 8),
                          const Text(
                            'To date must be after From date.',
                            style: TextStyle(fontSize: 12, color: Colors.red),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            ElevatedButton.icon(
              onPressed: (!exportAll &&
                      fromDate != null &&
                      toDate != null &&
                      toDate!.isBefore(fromDate!))
                  ? null
                  : () => Navigator.pop(ctx, true),
              icon: const Icon(Icons.download, size: 18),
              label: const Text('Export'),
            ),
          ],
        ),
      ),
    );

    if (confirmed != true || !mounted) return;

    try {
      final invoices = await ref.read(invoiceRepositoryProvider).getInvoicesForExport(
        fromDate: exportAll ? null : fromDate,
        toDate: exportAll ? null : toDate,
        filterType: widget.filterType,
      );
      final path = await ExportService.exportInvoicesToCsv(invoices,
          type: widget.filterType);
      if (mounted) {
        AppError.showSuccess(context,
            'Exported ${invoices.length} record${invoices.length == 1 ? '' : 's'} to: $path');
        await OpenFile.open(path);
      }
    } catch (e) {
      if (mounted) AppError.show(context, 'Export failed: $e');
    }
  }

  void _showTrashDialog() async {
    final deleted = await ref.read(invoiceRepositoryProvider).getDeletedInvoices();
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (ctx) => _TrashDialog(
        deletedInvoices: deleted,
        datePattern: _datePattern,
        onRestored: () async {
          ref.read(invoicesProvider.notifier).refresh();
          await _loadPage();
        },
      ),
    );
  }

  // ─── Bulk actions ──────────────────────────────────────────────────────────

  Future<void> _bulkSoftDelete() async {
    final count = _selectedIds.length;
    final confirmed = await AppError.confirm(
      context,
      title: 'Move to Trash',
      message: 'Move $count invoice${count == 1 ? '' : 's'} to trash?',
      confirmLabel: 'Move to Trash',
      confirmColor: Colors.orange,
    );
    if (!confirmed) return;

    setState(() => _isBulkLoading = true);
    try {
      for (final id in List<String>.from(_selectedIds)) {
        await ref.read(invoiceRepositoryProvider).softDeleteInvoice(id);
      }
      ref.read(invoicesProvider.notifier).refresh();
      await _loadPage(); // also clears _selectedIds
      if (mounted) {
        AppError.showSuccess(
            context, '$count invoice${count == 1 ? '' : 's'} moved to trash.');
      }
    } catch (e) {
      if (mounted) AppError.show(context, 'Bulk delete failed: $e');
    } finally {
      if (mounted) setState(() => _isBulkLoading = false);
    }
  }

  Future<void> _bulkExportCsv() async {
    final selected =
        _pageInvoices.where((inv) => _selectedIds.contains(inv.id)).toList();
    if (selected.isEmpty) return;

    setState(() => _isBulkLoading = true);
    try {
      final path = await ExportService.exportInvoicesToCsv(selected);
      if (mounted) {
        AppError.showSuccess(context,
            'Exported ${selected.length} invoice${selected.length == 1 ? '' : 's'} to CSV');
        await OpenFile.open(path);
      }
    } catch (e) {
      if (mounted) AppError.show(context, 'CSV export failed: $e');
    } finally {
      if (mounted) setState(() => _isBulkLoading = false);
    }
  }

  Future<void> _bulkExportPdfs() async {
    final selected =
        _pageInvoices.where((inv) => _selectedIds.contains(inv.id)).toList();
    if (selected.isEmpty) return;

    // Ask the user: save as folder or as a ZIP?
    final saveMode = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Icon(Icons.picture_as_pdf, color: Theme.of(ctx).primaryColor),
            const SizedBox(width: 12),
            const Text('Download PDFs'),
          ],
        ),
        content: Text(
          'How would you like to save ${selected.length} PDF${selected.length == 1 ? '' : 's'}?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          OutlinedButton.icon(
            icon: const Icon(Icons.folder_outlined),
            label: const Text('Save to Folder'),
            onPressed: () => Navigator.pop(ctx, 'folder'),
          ),
          FilledButton.icon(
            icon: const Icon(Icons.folder_zip_outlined),
            label: const Text('Save as ZIP'),
            onPressed: () => Navigator.pop(ctx, 'zip'),
          ),
        ],
      ),
    );
    if (saveMode == null || !mounted) return;

    String? outputDir;
    String? zipSavePath;

    if (saveMode == 'folder') {
      outputDir = await FilePicker.platform.getDirectoryPath(
        dialogTitle: 'Choose folder to save PDFs',
      );
      if (outputDir == null || !mounted) return;
    } else {
      zipSavePath = await FilePicker.platform.saveFile(
        dialogTitle: 'Save ZIP file',
        fileName:
            'invoices_${DateFormat('yyyyMMdd').format(DateTime.now())}.zip',
        type: FileType.custom,
        allowedExtensions: ['zip'],
      );
      if (zipSavePath == null || !mounted) return;
    }

    setState(() => _isBulkLoading = true);

    final progress = ValueNotifier<int>(0);

    unawaited(showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Icon(
              saveMode == 'zip'
                  ? Icons.folder_zip_outlined
                  : Icons.picture_as_pdf,
              color: Colors.orange,
            ),
            const SizedBox(width: 12),
            Text(saveMode == 'zip' ? 'Creating ZIP' : 'Generating PDFs'),
          ],
        ),
        content: ValueListenableBuilder<int>(
          valueListenable: progress,
          builder: (_, done, __) => Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Processing ${selected.length} PDF${selected.length == 1 ? '' : 's'}...',
              ),
              const SizedBox(height: 16),
              LinearProgressIndicator(
                value: done / selected.length,
                backgroundColor: Theme.of(context).colorScheme.outlineVariant,
              ),
              const SizedBox(height: 8),
              Text(
                '$done / ${selected.length}',
                style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 13),
              ),
            ],
          ),
        ),
      ),
    ));

    try {
      final String path;
      if (saveMode == 'zip') {
        path = await ExportService.exportInvoicesToZip(
          selected,
          zipSavePath!,
          onProgress: (done, _) => progress.value = done,
        );
      } else {
        path = await ExportService.exportInvoicesToPdfFolder(
          selected,
          onProgress: (done, _) => progress.value = done,
          outputDirectory: outputDir,
        );
      }
      if (mounted) {
        Navigator.of(context, rootNavigator: true).pop();
        AppError.showSuccess(context, 'Saved to: $path');
        await OpenFile.open(path);
      }
    } catch (e) {
      if (mounted) {
        Navigator.of(context, rootNavigator: true).pop();
        AppError.show(context, 'PDF export failed: $e');
      }
    } finally {
      progress.dispose();
      if (mounted) setState(() => _isBulkLoading = false);
    }
  }

  static const int _maxBulkPdfExport = 100;

  Future<void> _showFilteredDownloadDialog() async {
    DateTime? fromDate;
    DateTime? toDate;
    final fromIdCtrl = TextEditingController();
    final toIdCtrl = TextEditingController();
    int filterMode = 0; // 0 = date, 1 = invoice number
    int matchCount = 0;
    bool counting = false;

    Future<int> fetchCount(StateSetter setS) async {
      setS(() => counting = true);
      try {
        return await ref.read(invoiceRepositoryProvider).countInvoicesForExport(
          fromDate: filterMode == 0 ? fromDate : null,
          toDate: filterMode == 0 ? toDate : null,
          fromId: filterMode == 1 ? int.tryParse(fromIdCtrl.text) : null,
          toId: filterMode == 1 ? int.tryParse(toIdCtrl.text) : null,
          filterType: widget.filterType,
        );
      } finally {
        setS(() => counting = false);
      }
    }

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Row(
            children: [
              Icon(Icons.filter_alt_outlined),
              SizedBox(width: 10),
              Text('Download PDFs by Filter'),
            ],
          ),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SegmentedButton<int>(
                  segments: const [
                    ButtonSegment(
                        value: 0,
                        label: Text('By Date'),
                        icon: Icon(Icons.calendar_today_outlined, size: 16)),
                    ButtonSegment(
                        value: 1,
                        label: Text('By Invoice Number'),
                        icon: Icon(Icons.tag_outlined, size: 16)),
                  ],
                  selected: {filterMode},
                  onSelectionChanged: (v) async {
                    setS(() {
                      filterMode = v.first;
                      matchCount = 0;
                    });
                  },
                ),
                const SizedBox(height: 16),
                if (filterMode == 0) ...[
                  Row(children: [
                    Expanded(
                        child: _DatePickerField(
                      label: 'From date',
                      value: fromDate,
                      formatter: DateFormat('dd/MM/yyyy'),
                      onPicked: (d) {
                        setS(() {
                          fromDate = d;
                          matchCount = 0;
                        });
                      },
                      onCleared: () => setS(() {
                        fromDate = null;
                        matchCount = 0;
                      }),
                    )),
                    const SizedBox(width: 12),
                    Expanded(
                        child: _DatePickerField(
                      label: 'To date',
                      value: toDate,
                      formatter: DateFormat('dd/MM/yyyy'),
                      onPicked: (d) {
                        setS(() {
                          toDate = d;
                          matchCount = 0;
                        });
                      },
                      onCleared: () => setS(() {
                        toDate = null;
                        matchCount = 0;
                      }),
                    )),
                  ]),
                ] else ...[
                  Row(children: [
                    Expanded(
                        child: TextField(
                      controller: fromIdCtrl,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                          labelText: 'From invoice #',
                          border: OutlineInputBorder()),
                      onChanged: (_) => setS(() => matchCount = 0),
                    )),
                    const SizedBox(width: 12),
                    Expanded(
                        child: TextField(
                      controller: toIdCtrl,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                          labelText: 'To invoice #',
                          border: OutlineInputBorder()),
                      onChanged: (_) => setS(() => matchCount = 0),
                    )),
                  ]),
                ],
                const SizedBox(height: 16),
                Row(children: [
                  FilledButton.tonal(
                    onPressed: counting
                        ? null
                        : () async {
                            final c = await fetchCount(setS);
                            setS(() => matchCount = c);
                          },
                    child: counting
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : const Text('Check count'),
                  ),
                  const SizedBox(width: 12),
                  if (matchCount > 0)
                    Text(
                      matchCount > _maxBulkPdfExport
                          ? '$matchCount invoices — exceeds limit of $_maxBulkPdfExport'
                          : '$matchCount invoice${matchCount == 1 ? '' : 's'} match',
                      style: TextStyle(
                        color: matchCount > _maxBulkPdfExport
                            ? Colors.red
                            : Colors.green[700],
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                ]),
                if (matchCount > _maxBulkPdfExport)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      'Max $_maxBulkPdfExport PDFs per download. Narrow your filter.',
                      style: const TextStyle(color: Colors.red, fontSize: 12),
                    ),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel')),
            OutlinedButton.icon(
              icon: const Icon(Icons.folder_outlined),
              label: const Text('Save to Folder'),
              onPressed: matchCount > 0 && matchCount <= _maxBulkPdfExport
                  ? () => Navigator.pop(ctx, 'folder')
                  : null,
            ),
            FilledButton.icon(
              icon: const Icon(Icons.folder_zip_outlined),
              label: const Text('Save as ZIP'),
              onPressed: matchCount > 0 && matchCount <= _maxBulkPdfExport
                  ? () => Navigator.pop(ctx, 'zip')
                  : null,
            ),
          ],
        ),
      ),
    ).then((saveMode) async {
      if (saveMode == null || !mounted) return;

      final invoices = await ref.read(invoiceRepositoryProvider).getInvoicesForExport(
        fromDate: filterMode == 0 ? fromDate : null,
        toDate: filterMode == 0 ? toDate : null,
        fromId: filterMode == 1 ? int.tryParse(fromIdCtrl.text) : null,
        toId: filterMode == 1 ? int.tryParse(toIdCtrl.text) : null,
        filterType: widget.filterType,
      );

      if (invoices.isEmpty) {
        if (mounted) {
          AppError.show(context, 'No invoices found for the selected filter.');
        }
        return;
      }
      if (invoices.length > _maxBulkPdfExport) {
        if (mounted) {
          AppError.show(context,
              'Filter returned ${invoices.length} invoices — max is $_maxBulkPdfExport.');
        }
        return;
      }

      String? outputDir;
      String? zipSavePath;
      if (saveMode == 'folder') {
        outputDir = await FilePicker.platform
            .getDirectoryPath(dialogTitle: 'Choose folder to save PDFs');
        if (outputDir == null || !mounted) return;
      } else {
        zipSavePath = await FilePicker.platform.saveFile(
          dialogTitle: 'Save ZIP file',
          fileName:
              'invoices_${DateFormat('yyyyMMdd').format(DateTime.now())}.zip',
          type: FileType.custom,
          allowedExtensions: ['zip'],
        );
        if (zipSavePath == null || !mounted) return;
      }

      setState(() => _isBulkLoading = true);
      final progress = ValueNotifier<int>(0);

      unawaited(showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(children: [
            Icon(
                saveMode == 'zip'
                    ? Icons.folder_zip_outlined
                    : Icons.picture_as_pdf,
                color: Colors.orange),
            const SizedBox(width: 12),
            Text(saveMode == 'zip' ? 'Creating ZIP' : 'Generating PDFs'),
          ]),
          content: ValueListenableBuilder<int>(
            valueListenable: progress,
            builder: (_, done, __) => Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                    'Processing ${invoices.length} PDF${invoices.length == 1 ? '' : 's'}...'),
                const SizedBox(height: 16),
                LinearProgressIndicator(
                    value: done / invoices.length,
                    backgroundColor: Theme.of(context).colorScheme.outlineVariant),
                const SizedBox(height: 8),
                Text('$done / ${invoices.length}',
                    style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 13)),
              ],
            ),
          ),
        ),
      ));

      try {
        // Fetch PDF settings once for the entire batch.
        final settings = await PDFService.fetchPdfSettings();
        final String path;
        if (saveMode == 'zip') {
          path = await ExportService.exportInvoicesToZip(
            invoices,
            zipSavePath!,
            onProgress: (done, _) => progress.value = done,
            settings: settings,
          );
        } else {
          path = await ExportService.exportInvoicesToPdfFolder(
            invoices,
            onProgress: (done, _) => progress.value = done,
            outputDirectory: outputDir,
            settings: settings,
          );
        }
        if (mounted) {
          Navigator.of(context, rootNavigator: true).pop();
          AppError.showSuccess(context, 'Saved to: $path');
          await OpenFile.open(path);
        }
      } catch (e) {
        if (mounted) {
          Navigator.of(context, rootNavigator: true).pop();
          AppError.show(context, 'Export failed: $e');
        }
      } finally {
        progress.dispose();
        if (mounted) setState(() => _isBulkLoading = false);
      }
    });

    fromIdCtrl.dispose();
    toIdCtrl.dispose();
  }

  Future<void> _bulkMarkAsPaid() async {
    final unpaid = _pageInvoices
        .where((inv) =>
            _selectedIds.contains(inv.id) &&
            inv.outstandingBalance > InvoiceCalculator.moneyEpsilon)
        .toList();
    final alreadyPaid = _selectedIds.length - unpaid.length;

    if (unpaid.isEmpty) {
      AppError.show(context, 'All selected invoices are already fully paid.');
      return;
    }

    final confirmed = await AppError.confirm(
      context,
      title: 'Mark as Paid',
      message:
          'Mark ${unpaid.length} invoice${unpaid.length == 1 ? '' : 's'} as fully paid?'
          '${alreadyPaid > 0 ? '\n($alreadyPaid already paid — will be skipped)' : ''}',
      confirmLabel: 'Mark as Paid',
      confirmColor: Colors.green,
    );
    if (!confirmed || !mounted) return;

    setState(() => _isBulkLoading = true);
    try {
      final count = await ref.read(paymentRepositoryProvider).addPaymentBatch(
        invoices: unpaid,
        datePaid: DateTime.now(),
      );
      ref.read(invoicesProvider.notifier).refresh();
      await _loadPage();
      if (mounted) {
        AppError.showSuccess(
            context, '$count invoice${count == 1 ? '' : 's'} marked as paid.');
      }
    } catch (e) {
      if (mounted) AppError.show(context, 'Failed to mark as paid: $e');
    } finally {
      if (mounted) setState(() => _isBulkLoading = false);
    }
  }

  // ─── Pagination ────────────────────────────────────────────────────────────

  int get _totalPages => (_totalCount / _pageSize).ceil();

  // ─── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).brightness == Brightness.dark
          ? null
          : Colors.grey[50],
      appBar: AppBar(
        title: Text(
          '${widget.filterType} Management',
          style: const TextStyle(
            color: Color(0xFF0F172A),
            fontSize: 18,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.2,
          ),
        ),
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF0F172A),
        iconTheme: const IconThemeData(color: Color(0xFF475569)),
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleSpacing: 24,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(color: const Color(0xFFE2E8F0), height: 1),
        ),
        actions: [
          if (_isBulkLoading)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 12),
              child: Center(
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                      color: Color(0xFF007CFF), strokeWidth: 2),
                ),
              ),
            ),
          IconButton(
            icon: const Icon(Icons.download_for_offline_outlined),
            onPressed: _showFilteredDownloadDialog,
            tooltip: 'Download PDFs by date or invoice range',
          ),
          IconButton(
            icon: const Icon(Icons.file_download_outlined),
            onPressed: _exportCsv,
            tooltip: 'Export all to CSV',
          ),
          if (widget.user.isAdmin())
            IconButton(
              icon: const Icon(Icons.delete_sweep_outlined),
              onPressed: _showTrashDialog,
              tooltip: 'Trash',
            ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              _currentPage = 0;
              _loadPage();
            },
            tooltip: 'Refresh',
          ),
          const SizedBox(width: 12),
        ],
      ),
      body: Column(
        children: [
          // ── Search + stats ────────────────────────────────────────
          Container(
            decoration: const BoxDecoration(
              color: Colors.white,
              border: Border(
                bottom: BorderSide(color: Color(0xFFE2E8F0), width: 1),
              ),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            child: Row(
              children: [
                Expanded(
                  child: Container(
                    height: 42,
                    constraints: const BoxConstraints(maxWidth: 480),
                    child: TextField(
                      controller: _searchController,
                      focusNode: _searchFocusNode,
                      style: const TextStyle(fontSize: 14, color: Color(0xFF0F172A)),
                      decoration: InputDecoration(
                        hintText: 'Search by Invoice ID or Customer Name...',
                        hintStyle: const TextStyle(fontSize: 13, color: Color(0xFF94A3B8)),
                        prefixIcon: const Icon(Icons.search, size: 20, color: Color(0xFF64748B)),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        suffixIcon: _searchQuery.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.clear, size: 18),
                                onPressed: () {
                                  _searchController.clear();
                                  setState(() {
                                    _searchQuery = '';
                                    _currentPage = 0;
                                  });
                                  _loadPage();
                                },
                              )
                            : null,
                        filled: true,
                        fillColor: const Color(0xFFF8FAFC),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: const BorderSide(
                            color: Color(0xFF007CFF),
                            width: 1.5,
                          ),
                        ),
                      ),
                      onChanged: (value) {
                        setState(() {
                          _searchQuery = value;
                          _currentPage = 0;
                        });
                        _searchDebounce?.cancel();
                        _searchDebounce = Timer(
                          const Duration(milliseconds: 400),
                          _loadPage,
                        );
                      },
                    ),
                  ),
                ),
                const SizedBox(width: 20),
                Expanded(
                  child: ScrollConfiguration(
                    behavior: ScrollConfiguration.of(context).copyWith(
                      dragDevices: {
                        PointerDeviceKind.touch,
                        PointerDeviceKind.mouse,
                        PointerDeviceKind.trackpad,
                      },
                    ),
                    child: Scrollbar(
                      controller: _statsBarScrollController,
                      child: SingleChildScrollView(
                        controller: _statsBarScrollController,
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _buildStatChip(
                              'Total',
                              _totalCount.toString(),
                              Icons.receipt_long_outlined,
                            ),
                            const SizedBox(width: 10),
                            _buildStatChip(
                              'Page',
                              '${_currentPage + 1}/${_totalPages > 0 ? _totalPages : 1}',
                              Icons.layers_outlined,
                            ),
                            if (widget.filterType == 'Invoice') ...[
                              const SizedBox(width: 14),
                              // Hide Paid toggle
                              InkWell(
                                onTap: () {
                                  setState(() {
                                    _hidePaid = !_hidePaid;
                                    _currentPage = 0;
                                  });
                                  _loadPage();
                                },
                                borderRadius: BorderRadius.circular(8),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 12, vertical: 8),
                                  decoration: BoxDecoration(
                                    color: _hidePaid
                                        ? const Color(0xFF0F172A)
                                        : Colors.white,
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                      color: _hidePaid
                                          ? const Color(0xFF0F172A)
                                          : const Color(0xFFE2E8F0),
                                    ),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        _hidePaid
                                            ? Icons.visibility_off_outlined
                                            : Icons.visibility_outlined,
                                        size: 16,
                                        color: _hidePaid
                                            ? Colors.white
                                            : const Color(0xFF64748B),
                                      ),
                                      const SizedBox(width: 6),
                                      Text(
                                        'Hide Paid',
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600,
                                          color: _hidePaid
                                              ? Colors.white
                                              : const Color(0xFF475569),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ], // end filterType == 'Invoice'
                            if (widget.filterType == 'Invoice') ...[
                              const SizedBox(width: 10),
                              // Due date filter chips
                              ..._dueDateFilterOptions.map((option) {
                                final isActive = _dueDateFilter == option.$1;
                                return Padding(
                                  padding: const EdgeInsets.only(right: 6),
                                  child: InkWell(
                                    onTap: () {
                                      setState(() {
                                        _dueDateFilter = option.$1;
                                        _currentPage = 0;
                                      });
                                      _loadPage();
                                    },
                                    borderRadius: BorderRadius.circular(8),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 12, vertical: 8),
                                      decoration: BoxDecoration(
                                        color: isActive
                                            ? const Color(0xFF0F172A)
                                            : Colors.white,
                                        borderRadius: BorderRadius.circular(8),
                                        border: Border.all(
                                          color: isActive
                                              ? const Color(0xFF0F172A)
                                              : const Color(0xFFE2E8F0),
                                        ),
                                      ),
                                      child: Text(
                                        option.$2,
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600,
                                          color: isActive
                                              ? Colors.white
                                              : const Color(0xFF475569),
                                        ),
                                      ),
                                    ),
                                  ),
                                );
                              }),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),

                // ── Bulk-actions bar (animated in/out) ────────────────────
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 200),
                  child: _selectedIds.isEmpty
                      ? const SizedBox.shrink(key: ValueKey('no_selection'))
                      : _buildBulkActionsBar(),
                ),

                const SizedBox(height: 16),

                // ── Table ─────────────────────────────────────────────────
                _isLoadingPage
                ? const Center(child: CircularProgressIndicator())
                :
                Expanded(
                  child: _pageInvoices.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.search_off,
                                  size: 80, color: Theme.of(context).colorScheme.outlineVariant),
                              const SizedBox(height: 16),
                              Text(
                                _searchQuery.isEmpty
                                    ? 'No ${widget.filterType.toLowerCase()}s found'
                                    : 'No results for "$_searchQuery"',
                                style: TextStyle(
                                  fontSize: 18,
                                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                _searchQuery.isEmpty
                                    ? 'Create your first ${widget.filterType.toLowerCase()} to see it here'
                                    : 'Try adjusting your search',
                                style: TextStyle(
                                    fontSize: 14, color: Theme.of(context).colorScheme.onSurfaceVariant),
                              ),
                            ],
                          ),
                        )
                      : Align(
                          alignment: Alignment.topCenter,
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(
                                maxWidth: AppLayout.maxWidthWide),
                            child: SingleChildScrollView(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 24),
                              child: Container(
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: const Color(0xFFE2E8F0),
                                    width: 1,
                                  ),
                                  boxShadow: const [
                                    BoxShadow(
                                      color: Color(0x06000000),
                                      blurRadius: 10,
                                      offset: Offset(0, 2),
                                    ),
                                  ],
                                ),
                                clipBehavior: Clip.antiAlias,
                                child: Column(
                                  children: [
                                    // Table header
                                    Container(
                                      decoration: const BoxDecoration(
                                        color: Color(0xFFF8FAFC),
                                        border: Border(
                                          bottom: BorderSide(
                                            color: Color(0xFFE2E8F0),
                                            width: 1.5,
                                          ),
                                        ),
                                      ),
                                      child: Table(
                                        columnWidths: _columnWidths,
                                        children: [
                                          TableRow(
                                            children: [
                                              // Select-all checkbox
                                              Padding(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                        vertical: 10,
                                                        horizontal: 4),
                                                child: Checkbox(
                                                  value: _isAllPageSelected,
                                                  tristate:
                                                      _isSomePageSelected &&
                                                          !_isAllPageSelected,
                                                  onChanged: (_) =>
                                                      _toggleSelectAll(),
                                                  activeColor:
                                                      const Color(0xFF007CFF),
                                                  checkColor: Colors.white,
                                                  side: const BorderSide(
                                                      color: Color(0xFF94A3B8),
                                                      width: 1.5),
                                                ),
                                              ),
                                              _buildTableHeader('#'),
                                              _buildTableHeader('Invoice ID'),
                                              _buildTableHeader('Customer'),
                                              _buildTableHeader('Date'),
                                              _buildTableHeader('Items'),
                                              _buildTableHeader('Total'),
                                              if (widget.filterType ==
                                                  'Invoice') ...[
                                                _buildTableHeader('Status'),
                                                _buildTableHeader(
                                                    'Outstanding'),
                                              ],
                                              _buildTableHeader('Actions',
                                                  align: TextAlign.center),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ),
                                    // Table rows
                                    ..._pageInvoices.asMap().entries.map(
                                      (entry) {
                                        final invoice = entry.value;
                                        final index = entry.key;
                                        final globalIndex =
                                            (_currentPage * _pageSize) +
                                                index +
                                                1;
                                        return _buildInvoiceRow(
                                            invoice, globalIndex, index.isEven);
                                      },
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                ),

                // ── Pagination ────────────────────────────────────────────
                if (_pageInvoices.isNotEmpty)
                  Container(
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      border: Border(
                        top: BorderSide(color: Color(0xFFE2E8F0), width: 1),
                      ),
                    ),
                    padding: const EdgeInsets.symmetric(
                        vertical: 12, horizontal: 24),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            const Text('Rows per page:',
                                style: TextStyle(
                                    color: Color(0xFF64748B),
                                    fontSize: 13,
                                    fontWeight: FontWeight.w500)),
                            const SizedBox(width: 8),
                            DropdownButton<int>(
                              value: _pageSize,
                              underline: const SizedBox(),
                              items: [10, 25, 50, 100]
                                  .map((n) => DropdownMenuItem(
                                      value: n,
                                      child: Text('$n',
                                          style: const TextStyle(
                                              fontSize: 13,
                                              fontWeight: FontWeight.w600,
                                              color: Color(0xFF0F172A)))))
                                  .toList(),
                              onChanged: (n) {
                                if (n == null) return;
                                setState(() {
                                  _pageSize = n;
                                  _currentPage = 0;
                                });
                                _loadPage();
                              },
                            ),
                          ],
                        ),
                        Row(
                          children: [
                            OutlinedButton.icon(
                              onPressed: _currentPage > 0
                                  ? () {
                                      setState(() => _currentPage--);
                                      _loadPage();
                                    }
                                  : null,
                              icon: const Icon(Icons.chevron_left, size: 18),
                              label: const Text('Previous'),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: const Color(0xFF0F172A),
                                disabledForegroundColor: const Color(0xFF94A3B8),
                                side: const BorderSide(color: Color(0xFFE2E8F0)),
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(8)),
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 14, vertical: 8),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 14, vertical: 8),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF8FAFC),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                    color: const Color(0xFFE2E8F0)),
                              ),
                              child: Text(
                                'Page ${_currentPage + 1} of ${_totalPages > 0 ? _totalPages : 1}',
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: Color(0xFF0F172A),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            OutlinedButton.icon(
                              onPressed: (_currentPage + 1 < _totalPages)
                                  ? () {
                                      setState(() => _currentPage++);
                                      _loadPage();
                                    }
                                  : null,
                              icon: const Icon(Icons.chevron_right, size: 18),
                              label: const Text('Next'),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: const Color(0xFF0F172A),
                                disabledForegroundColor: const Color(0xFF94A3B8),
                                side: const BorderSide(color: Color(0xFFE2E8F0)),
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(8)),
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 14, vertical: 8),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
              ],
            ),
    );
  }

  // ─── Bulk actions bar ──────────────────────────────────────────────────────

  Widget _buildBulkActionsBar() {
    final count = _selectedIds.length;
    return Container(
      key: const ValueKey('bulk_bar'),
      color: Theme.of(context).primaryColor,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
      child: Row(
        children: [
          // Selected count badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              '$count selected',
              style: TextStyle(
                color: Theme.of(context).primaryColor,
                fontWeight: FontWeight.bold,
                fontSize: 14,
              ),
            ),
          ),
          const SizedBox(width: 12),

          _buildBulkButton(
            icon: Icons.deselect,
            label: 'Deselect All',
            onPressed: () => setState(() => _selectedIds.clear()),
          ),
          const SizedBox(width: 8),

          _buildBulkButton(
            icon: Icons.select_all,
            label: 'Select Page',
            onPressed: _isAllPageSelected
                ? null
                : () => setState(() {
                      for (final inv in _pageInvoices) {
                        _selectedIds.add(inv.id);
                      }
                    }),
          ),

          const Spacer(),

          _buildBulkButton(
            icon: Icons.payments_outlined,
            label: 'Mark as Paid',
            color: Colors.green[300]!,
            onPressed: _isBulkLoading ? null : _bulkMarkAsPaid,
          ),
          const SizedBox(width: 8),

          _buildBulkButton(
            icon: Icons.table_chart_outlined,
            label: 'Export CSV',
            onPressed: _isBulkLoading ? null : _bulkExportCsv,
          ),
          const SizedBox(width: 8),

          _buildBulkButton(
            icon: Icons.picture_as_pdf_outlined,
            label: 'Export PDFs',
            onPressed: _isBulkLoading ? null : _bulkExportPdfs,
          ),
          const SizedBox(width: 8),

          if (widget.user.isAdmin())
            _buildBulkButton(
              icon: Icons.delete_outline,
              label: 'Move to Trash',
              color: Colors.red[300]!,
              onPressed: _isBulkLoading ? null : _bulkSoftDelete,
            ),
        ],
      ),
    );
  }

  Widget _buildBulkButton({
    required IconData icon,
    required String label,
    required VoidCallback? onPressed,
    Color? color,
  }) {
    final c = color ?? Colors.white;
    return TextButton.icon(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        foregroundColor: c,
        disabledForegroundColor: Colors.white38,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: BorderSide(
              color: onPressed != null
                  ? c.withValues(alpha: 0.5)
                  : Colors.white24),
        ),
      ),
      icon: Icon(icon, size: 18),
      label: Text(label, style: const TextStyle(fontSize: 13)),
    );
  }

  // ─── Table helpers ─────────────────────────────────────────────────────────

  Widget _buildTableHeader(String text, {TextAlign align = TextAlign.left}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
      child: Text(
        text,
        textAlign: align,
        style: const TextStyle(
          color: Color(0xFF475569),
          fontSize: 12,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  Widget _buildInvoiceRow(Invoice invoice, int index, bool isEven) {
    final isSelected = _selectedIds.contains(invoice.id);
    return Container(
      decoration: BoxDecoration(
        color: isSelected
            ? const Color(0xFFEFF6FF)
            : (isEven ? Colors.white : const Color(0xFFFAFAFA)),
        border: Border(
          bottom: const BorderSide(color: Color(0xFFF1F5F9), width: 1),
          left: isSelected
              ? const BorderSide(color: Color(0xFF007CFF), width: 3)
              : BorderSide.none,
        ),
      ),
      child: Table(
        columnWidths: _columnWidths,
        children: [
          TableRow(
            children: [
              // Per-row checkbox
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
                child: Checkbox(
                  value: isSelected,
                  onChanged: (_) => _toggleOne(invoice.id),
                  activeColor: const Color(0xFF007CFF),
                  side: const BorderSide(color: Color(0xFFCBD5E1), width: 1.5),
                ),
              ),
              // Index
              _buildTableCell(
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    '$index',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF475569),
                    ),
                  ),
                ),
              ),
              // Invoice ID
              _buildTableCell(
                Text(
                  '#${invoice.invoiceNumber ?? invoice.id}',
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF0F172A),
                  ),
                ),
              ),
              // Customer + Optional Title subtitle
              _buildTableCell(
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            invoice.customer.name,
                            style: const TextStyle(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF0F172A),
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 4),
                        CustomerInfoButton(customer: invoice.customer),
                      ],
                    ),
                    if (invoice.invoiceTitle != null &&
                        invoice.invoiceTitle!.trim().isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        invoice.invoiceTitle!,
                        style: const TextStyle(
                          fontSize: 11.5,
                          color: Color(0xFF64748B),
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
              // Date
              _buildTableCell(_buildDateCell(invoice)),
              // Items count
              _buildTableCell(
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: Text(
                    '${invoice.items.length}',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF334155),
                    ),
                  ),
                ),
              ),
              // Total
              _buildTableCell(
                Text(
                  '${invoice.currencySymbol} ${invoice.total.toStringAsFixed(2)}',
                  style: const TextStyle(
                    fontSize: 13.5,
                    overflow: TextOverflow.ellipsis,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF0F172A),
                  ),
                ),
              ),
              if (widget.filterType == 'Invoice') ...[
                // Payment status chip
                _buildTableCell(_buildPaymentStatusChip(invoice.paymentStatus)),
                // Outstanding balance
                _buildTableCell(
                  invoice.paymentStatus == PaymentStatus.paid
                      ? const Text('—',
                          style: TextStyle(color: Color(0xFF94A3B8)))
                      : Text(
                          '${invoice.currencySymbol} ${invoice.outstandingBalance.toStringAsFixed(2)}',
                          style: TextStyle(
                            fontSize: 13,
                            overflow: TextOverflow.ellipsis,
                            fontWeight: FontWeight.w700,
                            color:
                                invoice.paymentStatus == PaymentStatus.partial
                                    ? const Color(0xFFD97706)
                                    : const Color(0xFFDC2626),
                          ),
                        ),
                ),
              ],
              // Actions (View, Edit, PDF + More)
              _buildTableCell(
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _buildRowIconButton(
                      icon: Icons.visibility_outlined,
                      tooltip: 'View Details',
                      onTap: () => InvoicePdfServices.showInvoiceDetails(
                          context, invoice),
                    ),
                    const SizedBox(width: 4),
                    _buildRowIconButton(
                      icon: Icons.edit_outlined,
                      tooltip: 'Edit',
                      onTap: () => widget.onEditInvoice(invoice),
                    ),
                    const SizedBox(width: 4),
                    _buildRowIconButton(
                      icon: Icons.picture_as_pdf_outlined,
                      tooltip: 'PDF Preview',
                      onTap: () =>
                          InvoicePdfServices.previewPDF(context, invoice),
                    ),
                    const SizedBox(width: 4),
                    PopupMenuButton<String>(
                      tooltip: 'More actions',
                      padding: EdgeInsets.zero,
                      icon: Container(
                        width: 30,
                        height: 30,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: const Color(0xFFE2E8F0)),
                        ),
                        child: const Icon(Icons.more_vert,
                            size: 16, color: Color(0xFF475569)),
                      ),
                      onSelected: (val) {
                        switch (val) {
                          case 'payment':
                            _showApplyPaymentDialog(invoice);
                          case 'duplicate':
                            _showCloneDialog(invoice);
                          case 'download':
                            PDFService.downloadPDF(context, invoice);
                          case 'print':
                            InvoicePdfServices.generatePDF(context, invoice);
                          case 'trash':
                            if (widget.user.isAdmin()) _softDelete(invoice);
                        }
                      },
                      itemBuilder: (context) => [
                        if (widget.filterType == 'Invoice' &&
                            invoice.paymentStatus != PaymentStatus.paid)
                          const PopupMenuItem(
                            value: 'payment',
                            child: Row(
                              children: [
                                Icon(Icons.payments_outlined,
                                    size: 16, color: Color(0xFF475569)),
                                SizedBox(width: 8),
                                Text('Apply Payment',
                                    style: TextStyle(fontSize: 13, color: Color(0xFF0F172A))),
                              ],
                            ),
                          ),
                        const PopupMenuItem(
                          value: 'duplicate',
                          child: Row(
                            children: [
                              Icon(Icons.copy_all_outlined,
                                  size: 16, color: Color(0xFF475569)),
                              SizedBox(width: 8),
                              Text('Duplicate',
                                  style: TextStyle(fontSize: 13, color: Color(0xFF0F172A))),
                            ],
                          ),
                        ),
                        const PopupMenuItem(
                          value: 'download',
                          child: Row(
                            children: [
                              Icon(Icons.download_outlined,
                                  size: 16, color: Color(0xFF475569)),
                              SizedBox(width: 8),
                              Text('Download PDF',
                                  style: TextStyle(fontSize: 13, color: Color(0xFF0F172A))),
                            ],
                          ),
                        ),
                        const PopupMenuItem(
                          value: 'print',
                          child: Row(
                            children: [
                              Icon(Icons.print_outlined,
                                  size: 16, color: Color(0xFF475569)),
                              SizedBox(width: 8),
                              Text('Print', style: TextStyle(fontSize: 13, color: Color(0xFF0F172A))),
                            ],
                          ),
                        ),
                        if (widget.user.isAdmin()) ...[
                          const PopupMenuDivider(),
                          const PopupMenuItem(
                            value: 'trash',
                            child: Row(
                              children: [
                                Icon(Icons.delete_outline,
                                    size: 16, color: Color(0xFF475569)),
                                SizedBox(width: 8),
                                Text('Move to Trash',
                                    style: TextStyle(
                                        fontSize: 13,
                                        color: Color(0xFF0F172A))),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTableCell(Widget child) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
      child: child,
    );
  }

  Widget _buildRowIconButton({
    required IconData icon,
    required String tooltip,
    required VoidCallback onTap,
    Color? iconColor,
  }) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: Container(
          width: 30,
          height: 30,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          child:
              Icon(icon, size: 16, color: iconColor ?? const Color(0xFF475569)),
        ),
      ),
    );
  }

  Widget _buildDateCell(Invoice invoice) {
    final orderStr =
        AppFormatters.formatShortDate(invoice.date, pattern: _datePattern);
    if (invoice.dueDate == null) {
      return Text(
        orderStr,
        style: const TextStyle(fontSize: 12.5, color: Color(0xFF334155)),
      );
    }
    final today = InvoiceCalculator.dateOnly(DateTime.now());
    final due = InvoiceCalculator.dateOnly(invoice.dueDate!);
    final isOverdue = InvoiceCalculator.isOverdue(
      dueDate: invoice.dueDate,
      outstanding: invoice.outstandingBalance,
    );
    final isToday = due == today;
    final dueStr =
        AppFormatters.formatShortDate(invoice.dueDate, pattern: _datePattern);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          orderStr,
          style: const TextStyle(fontSize: 12.5, color: Color(0xFF334155)),
        ),
        const SizedBox(height: 3),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Text(
                dueStr,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11.5,
                  color: isOverdue
                      ? const Color(0xFFDC2626)
                      : (isToday
                          ? const Color(0xFFD97706)
                          : const Color(0xFF64748B)),
                  fontWeight:
                      (isOverdue || isToday) ? FontWeight.w600 : FontWeight.normal,
                ),
              ),
            ),
            if (isOverdue || isToday) ...[
              const SizedBox(width: 4),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                decoration: BoxDecoration(
                  color: isOverdue
                      ? const Color(0xFFFEF2F2)
                      : const Color(0xFFFFFBEB),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(
                    color: isOverdue
                        ? const Color(0xFFFCA5A5)
                        : const Color(0xFFFCD34D),
                  ),
                ),
                child: Text(
                  isOverdue ? 'Overdue' : 'Today',
                  style: TextStyle(
                    fontSize: 9.5,
                    fontWeight: FontWeight.w700,
                    color: isOverdue
                        ? const Color(0xFFDC2626)
                        : const Color(0xFFD97706),
                  ),
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }

  Widget _buildStatChip(String label, String value, IconData icon,
      {Color? color}) {
    final effectiveColor = color ?? const Color(0xFF0F172A);
    return Container(
      height: 42,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: const Color(0xFF64748B)),
          const SizedBox(width: 8),
          Text(
            label.toUpperCase(),
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.5,
              color: Color(0xFF64748B),
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: const Color(0xFFF1F5F9),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              value,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: effectiveColor,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPaymentStatusChip(PaymentStatus status) {
    final Color bgColor;
    final Color borderColor;
    final Color textColor;
    final Color dotColor;
    final String label;
    switch (status) {
      case PaymentStatus.paid:
        bgColor = const Color(0xFFECFDF5);
        borderColor = const Color(0xFFA7F3D0);
        textColor = const Color(0xFF065F46);
        dotColor = const Color(0xFF10B981);
        label = 'Paid';
      case PaymentStatus.partial:
        bgColor = const Color(0xFFFFFBEB);
        borderColor = const Color(0xFFFDE68A);
        textColor = const Color(0xFF92400E);
        dotColor = const Color(0xFFF59E0B);
        label = 'Partial';
      case PaymentStatus.unpaid:
        bgColor = const Color(0xFFFEF2F2);
        borderColor = const Color(0xFFFECACA);
        textColor = const Color(0xFF991B1B);
        dotColor = const Color(0xFFEF4444);
        label = 'Unpaid';
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderColor),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              color: dotColor,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              color: textColor,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showApplyPaymentDialog(Invoice invoice) async {
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => ApplyPaymentDialog(
        invoice: invoice,
        onPaymentRecorded: () {
          ref.read(invoicesProvider.notifier).refresh();
          _loadPage();
        },
      ),
    );
  }
}

// Silence the unawaited future lint for the showDialog call used to drive the
// progress overlay (we close it programmatically via Navigator.pop).
void unawaited(Future<void> future) {}

// ─────────────────────────────────────────────
// Trash Dialog
class _TrashDialog extends ConsumerStatefulWidget {
  final List<Invoice> deletedInvoices;
  final VoidCallback onRestored;
  final String datePattern;

  const _TrashDialog(
      {required this.deletedInvoices,
      required this.onRestored,
      required this.datePattern});

  @override
  ConsumerState<_TrashDialog> createState() => _TrashDialogState();
}

class _TrashDialogState extends ConsumerState<_TrashDialog> {
  late List<Invoice> _invoices;

  @override
  void initState() {
    super.initState();
    _invoices = List.from(widget.deletedInvoices);
  }

  Future<void> _restore(Invoice invoice) async {
    await ref.read(invoiceRepositoryProvider).restoreInvoice(invoice.id);
    setState(() => _invoices.removeWhere((i) => i.id == invoice.id));
    widget.onRestored();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Invoice restored.'), backgroundColor: Colors.green),
      );
    }
  }

  Future<void> _permanentDelete(Invoice invoice) async {
    final confirmed = await AppError.confirm(
      context,
      title: 'Permanently Delete',
      message:
          'Permanently delete Invoice #${invoice.invoiceNumber ?? invoice.id}? This cannot be undone.',
    );
    if (!confirmed) return;
    await ref.read(invoiceRepositoryProvider).permanentDeleteInvoice(invoice.id);
    setState(() => _invoices.removeWhere((i) => i.id == invoice.id));
    widget.onRestored();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        width: 700,
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.red.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.delete_sweep, color: Colors.red),
                ),
                const SizedBox(width: 12),
                const Text('Trash',
                    style:
                        TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (_invoices.isEmpty)
              Padding(
                padding: const EdgeInsets.all(32),
                child: Center(
                  child: Text('Trash is empty',
                      style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 16)),
                ),
              )
            else
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 400),
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: _invoices.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (ctx, index) {
                    final inv = _invoices[index];
                    return ListTile(
                      leading:
                          Icon(Icons.receipt_long, color: Theme.of(context).colorScheme.onSurfaceVariant),
                      title: Text('#${inv.invoiceNumber ?? inv.id} — ${inv.customer.name}'),
                      subtitle: Row(
                        children: [
                          Text(AppFormatters.formatShortDate(inv.date,
                              pattern: widget.datePattern)),
                          SizedBox(width: 10,),
                          Container(
                            padding:
                            const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4),
                            decoration: BoxDecoration(
                              color: inv.type == 'Invoice'
                                  ? Colors.indigo
                                  .withValues(alpha: 0.1)
                                  : Colors.orange
                                  .withValues(alpha: 0.1),
                              borderRadius:
                              BorderRadius.circular(6),
                              border: Border.all(
                                color:
                                inv.type == 'Invoice'
                                    ? Colors.indigo
                                    .withValues(
                                    alpha: 0.35)
                                    : Colors.orange
                                    .withValues(
                                    alpha: 0.35),
                              ),
                            ),
                            child: Text(
                              inv.type,
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color:
                                inv.type == 'Invoice'
                                    ? Colors.indigo[700]
                                    : Colors.orange[800],
                                letterSpacing: 0.5,
                              ),
                            ),
                          )
                        ],
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          TextButton.icon(
                            onPressed: () => _restore(inv),
                            icon: const Icon(Icons.restore, size: 16),
                            label: const Text('Restore'),
                            style: TextButton.styleFrom(
                                foregroundColor: Colors.green),
                          ),
                          const SizedBox(width: 4),
                          TextButton.icon(
                            onPressed: () => _permanentDelete(inv),
                            icon: const Icon(Icons.delete_forever, size: 16),
                            label: const Text('Delete'),
                            style: TextButton.styleFrom(
                                foregroundColor: Colors.red),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Close'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DatePickerField extends StatelessWidget {
  final String label;
  final DateTime? value;
  final DateFormat formatter;
  final ValueChanged<DateTime> onPicked;
  final VoidCallback onCleared;

  const _DatePickerField({
    required this.label,
    required this.value,
    required this.formatter,
    required this.onPicked,
    required this.onCleared,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () async {
        final picked = await showDatePicker(
          context: context,
          initialDate: value ?? DateTime.now(),
          firstDate: DateTime(2000),
          lastDate: DateTime(2100),
        );
        if (picked != null) onPicked(picked);
      },
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          labelStyle: const TextStyle(fontSize: 13),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          suffixIcon: value != null
              ? IconButton(
                  icon: const Icon(Icons.clear, size: 16),
                  onPressed: onCleared,
                )
              : const Icon(Icons.calendar_today, size: 16),
        ),
        child: Text(
          value != null ? formatter.format(value!) : 'Any',
          style: TextStyle(
            fontSize: 13,
            color: value != null ? Theme.of(context).colorScheme.onSurface : Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}
