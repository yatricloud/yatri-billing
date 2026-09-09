import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:invoiso/common.dart';
import 'package:invoiso/domain/invoice_totals_calculator.dart';
import 'package:invoiso/providers/app_config_provider.dart';
import 'package:invoiso/providers/repositories.dart';
import 'package:uuid/uuid.dart';
import 'package:invoiso/models/customer.dart';
import 'package:invoiso/models/invoice.dart';
import 'package:invoiso/models/invoice_item.dart';
import 'package:invoiso/models/product.dart';
import 'package:invoiso/models/additional_cost.dart';
import 'package:invoiso/services/invoice_pdf_services.dart';
import 'package:invoiso/services/pdf_service.dart';
import 'package:invoiso/constants.dart';
import 'package:invoiso/theme/coinbase_tokens.dart';
import 'package:invoiso/theme/app_typography.dart';

class InvoiceFormGuard {
  Future<bool> Function()? canLeave;
}

class CreateInvoiceScreen extends ConsumerStatefulWidget {
  final Invoice? invoiceToEdit;

  /// When set, the form is pre-populated from this invoice and saved as a NEW
  /// invoice (cloneFrom != null implies invoiceToEdit == null).
  final Invoice? cloneFrom;

  /// The invoice type to use for the clone ('Invoice' or 'Quotation').
  /// Defaults to the source invoice type when null.
  final String? cloneType;

  /// Called when the user taps "New Invoice" while in edit mode.
  /// The parent (DashboardScreen) resets invoiceToEdit to null.
  final VoidCallback? onCreateNewInvoice;
  final InvoiceFormGuard? guard;

  const CreateInvoiceScreen({
    super.key,
    this.invoiceToEdit,
    this.cloneFrom,
    this.cloneType,
    this.onCreateNewInvoice,
    this.guard,
  });

  @override
  ConsumerState<CreateInvoiceScreen> createState() => _CreateInvoiceScreenState();
}

class _CreateInvoiceScreenState extends ConsumerState<CreateInvoiceScreen> {
  Customer? selectedCustomer;
  List<Customer> customers = [];
  List<Customer> filteredCustomers = [];
  List<Product> products = [];
  List<Product> filteredProducts = [];
  Map<String, ProductMetadata> _productMetadata = {};
  Timer? _productSearchDebounce;
  int _productSearchRequestId = 0;
  static const int _productFetchLimit = 10;
  Timer? _customerSearchDebounce;
  int _customerSearchRequestId = 0;
  static const int _customerFetchLimit = 5;
  List<InvoiceItem> invoiceItems = [];
  final Set<String> _savedAdHocIds =
      {}; // tracks custom item IDs already saved to products
  final List<({TextEditingController label, TextEditingController amount})>
      _additionalCostControllers = [];
  bool _showAdditionalCosts = false;

  final notesController = TextEditingController();
  final searchController = TextEditingController();
  final customerSearchController = TextEditingController();
  final nameController = TextEditingController();
  final emailController = TextEditingController();
  final phoneController = TextEditingController();
  final addressController = TextEditingController();
  final gstinController = TextEditingController();
  final businessNameController = TextEditingController();
  final taxRateController = TextEditingController();
  final dateController = TextEditingController();
  final dueDateController = TextEditingController();
  DateTime _selectedOrderDate = DateTime.now();
  DateTime? _selectedDueDate;

  final _customerScrollController = ScrollController();
  final _productScrollController = ScrollController();
  final _invoiceItemsScrollController = ScrollController();

  bool _isTaxEnabled = true;
  bool _isPerItem = false;
  bool isEditing = false;
  bool isLoading = false;

  String invoiceType = 'Invoice';
  String? invoiceTitle;
  double taxRate = Tax.defaultTaxRate;
  Invoice? _invoice;
  String currentInvoiceNumber = "";
  String _currencyCode = 'INR';
  String _currencySymbol = '₹';
  List<UpiEntry> _upiEntries = [];
  UpiEntry? _selectedUpi;
  List<BankAccount> _bankAccounts = [];
  BankAccount? _selectedBankAccount;
  bool _showGstFields = true;
  bool _fractionalQuantity = false;
  String _quantityLabel = '';
  bool _showQuantity = true;
  bool _showPreviousBalance = false;
  bool _showAliasNameInPdf = false;
  bool _allowDuplicateInvoiceItems = false;
  double _previousBalanceDue = 0.0;
  bool _isPreviousBalanceLoading = false;
  bool _isSavingCustomer = false;
  int _previousBalanceRequestSerial = 0;
  BusinessType _businessType = BusinessType.both;
  String _datePattern = 'dd/MM/yyyy';
  String _adHocItemType = 'product'; // type for custom items added inline
  String? _cleanFormSnapshot;
  int _pendingInitialLoads = 2;

  TaxMode get _taxMode {
    if (!_isTaxEnabled) return TaxMode.none;
    return _isPerItem ? TaxMode.perItem : TaxMode.global;
  }

  @override
  void initState() {
    super.initState();
    widget.guard?.canLeave = _confirmLeaveIfDirty;
    taxRateController.text = (taxRate * 100).toStringAsFixed(1);
    _loadCustomersAndProducts(widget.invoiceToEdit != null);
    _selectedOrderDate = DateTime.now();
    dateController.text = DateFormat(_datePattern).format(_selectedOrderDate);
    _setAdditionalNote();
    if (widget.invoiceToEdit != null) {
      _invoice = widget.invoiceToEdit;
      isEditing = true;
      selectedCustomer = _invoice!.customer;
      invoiceItems = List.from(_invoice!.items);
      nameController.text = _invoice!.customer.name;
      emailController.text = _invoice!.customer.email;
      phoneController.text = _invoice!.customer.phone;
      addressController.text = _invoice!.customer.address;
      gstinController.text = _invoice!.customer.gstin;
      businessNameController.text = _invoice!.customer.businessName;
      taxRate = _invoice!.taxRate;
      taxRateController.text = (taxRate * 100).toStringAsFixed(1);
      _isTaxEnabled = _invoice!.taxMode != TaxMode.none;
      _isPerItem = _invoice!.taxMode == TaxMode.perItem;
      invoiceType = _invoice!.type;
      invoiceTitle = _invoice!.invoiceTitle;
      currentInvoiceNumber = _invoice!.invoiceNumber ?? _invoice!.id;
      _selectedOrderDate = _invoice!.date;
      dateController.text = DateFormat(_datePattern).format(_selectedOrderDate);
      if (_invoice!.dueDate != null) {
        _selectedDueDate = _invoice!.dueDate;
        dueDateController.text =
            DateFormat(_datePattern).format(_invoice!.dueDate!);
      }
      _quantityLabel = _invoice!.quantityLabel ?? '';
      for (final c in _invoice!.additionalCosts) {
        _additionalCostControllers.add((
          label: TextEditingController(text: c.label),
          amount: TextEditingController(text: c.amount.toStringAsFixed(2)),
        ));
      }
      if (_additionalCostControllers.isNotEmpty) _showAdditionalCosts = true;
    } else if (widget.cloneFrom != null) {
      // Clone: pre-populate fields but treat as a brand-new invoice.
      // isEditing stays false → _createInvoice() will be called on save.
      final src = widget.cloneFrom!;
      selectedCustomer = src.customer;
      invoiceItems = List.from(src.items);
      nameController.text = src.customer.name;
      emailController.text = src.customer.email;
      phoneController.text = src.customer.phone;
      addressController.text = src.customer.address;
      gstinController.text = src.customer.gstin;
      businessNameController.text = src.customer.businessName;
      taxRate = src.taxRate;
      taxRateController.text = (taxRate * 100).toStringAsFixed(1);
      _isTaxEnabled = src.taxMode != TaxMode.none;
      _isPerItem = src.taxMode == TaxMode.perItem;
      invoiceType = widget.cloneType ?? src.type;
      invoiceTitle = invoiceType == src.type ? src.invoiceTitle : null;
      _quantityLabel = src.quantityLabel ?? '';
      for (final c in src.additionalCosts) {
        _additionalCostControllers.add((
          label: TextEditingController(text: c.label),
          amount: TextEditingController(text: c.amount.toStringAsFixed(2)),
        ));
      }
      if (_additionalCostControllers.isNotEmpty) _showAdditionalCosts = true;
      // date stays as today; currentInvoiceNumber is generated in _loadCustomersAndProducts
    }
  }

  @override
  void didUpdateWidget(covariant CreateInvoiceScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.guard != widget.guard) {
      if (oldWidget.guard?.canLeave == _confirmLeaveIfDirty) {
        oldWidget.guard?.canLeave = null;
      }
      widget.guard?.canLeave = _confirmLeaveIfDirty;
    }
  }

  Future<void> _setAdditionalNote({bool forceDefault = false}) async {
    final String addNote;
    if (!forceDefault && widget.invoiceToEdit != null) {
      addNote = widget.invoiceToEdit!.notes ?? '';
    } else if (!forceDefault && widget.cloneFrom != null) {
      addNote = widget.cloneFrom!.notes ?? '';
    } else {
      addNote = await ref.read(settingsRepositoryProvider).getSetting(SettingKey.additionalInfo) ??
          ref.read(appEditionConfigProvider).additionalNote;
    }
    final taxRateSetting = await ref.read(settingsRepositoryProvider).getSetting(SettingKey.defaultTaxRate);
    final parsedRate = double.tryParse(taxRateSetting ?? '') ?? 18.0;
    if (widget.invoiceToEdit == null && widget.cloneFrom == null) {
      taxRate = parsedRate / 100.0;
      taxRateController.text = parsedRate.toStringAsFixed(1);
    }
    if(!mounted) return;
    setState(() {
      notesController.text = addNote;
    });
    _completeInitialLoad();
  }

  @override
  void dispose() {
    _productSearchDebounce?.cancel();
    _customerSearchDebounce?.cancel();
    if (widget.guard?.canLeave == _confirmLeaveIfDirty) {
      widget.guard?.canLeave = null;
    }
    notesController.dispose();
    searchController.dispose();
    customerSearchController.dispose();
    nameController.dispose();
    emailController.dispose();
    phoneController.dispose();
    addressController.dispose();
    taxRateController.dispose();
    dateController.dispose();
    dueDateController.dispose();
    _customerScrollController.dispose();
    _productScrollController.dispose();
    _invoiceItemsScrollController.dispose();
    gstinController.dispose();
    businessNameController.dispose();
    for (final row in _additionalCostControllers) {
      row.label.dispose();
      row.amount.dispose();
    }
    super.dispose();
  }

  void _completeInitialLoad() {
    if (_pendingInitialLoads <= 0) return;
    _pendingInitialLoads--;
    if (_pendingInitialLoads == 0) {
      _markFormClean();
    }
  }

  void _markFormClean() {
    _cleanFormSnapshot = _currentFormSnapshot();
  }

  bool get _hasUnsavedChanges {
    if (!isEditing && _invoice != null) return false;
    final clean = _cleanFormSnapshot;
    if (clean == null) return false;
    return _currentFormSnapshot() != clean;
  }

  String _currentFormSnapshot() {
    return jsonEncode({
      'mode': widget.invoiceToEdit != null
          ? 'edit:${widget.invoiceToEdit!.id}'
          : widget.cloneFrom != null
              ? 'clone:${widget.cloneFrom!.id}:$invoiceType'
              : 'create',
      'selectedCustomerId': selectedCustomer?.id ?? '',
      'customer': {
        'name': nameController.text.trim(),
        'email': emailController.text.trim(),
        'phone': phoneController.text.trim(),
        'address': addressController.text.trim(),
        'gstin': gstinController.text.trim(),
        'businessName': businessNameController.text.trim(),
      },
      'items': invoiceItems.map((item) {
        final product = item.product;
        return {
          'productId': product.id,
          'name': product.name,
          'price': product.price,
          'quantity': item.quantity,
          'discount': item.discount,
          'discountPerUnit': item.discountPerUnit,
          'extraCost': item.extraCost ?? 0.0,
          'taxRate': product.tax_rate,
          'hsn': product.hsncode,
          'type': product.type,
          'isProductSaved': item.isProductSaved,
        };
      }).toList(),
      'additionalCosts': _additionalCostControllers
          .map((row) => {
                'label': row.label.text.trim(),
                'amount': row.amount.text.trim(),
              })
          .toList(),
      'showAdditionalCosts': _showAdditionalCosts,
      'notes': notesController.text.trim(),
      'invoiceType': invoiceType,
      'taxEnabled': _isTaxEnabled,
      'perItemTax': _isPerItem,
      'taxRate': taxRate,
      'taxRateText': taxRateController.text.trim(),
      'date': _selectedOrderDate.toIso8601String(),
      'dueDate': _selectedDueDate?.toIso8601String() ?? '',
      'currencyCode': _currencyCode,
      'upiId': _selectedUpi?.id ?? '',
      'bankAccount': _selectedBankAccount?.accountNumber ?? '',
      'quantityLabel': _quantityLabel.trim(),
    });
  }

  Future<bool> _confirmLeaveIfDirty() async {
    if (!_hasUnsavedChanges || isLoading) return true;

    final action = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Unsaved changes'),
        content: const Text(
          'You have unsaved changes in this invoice. Save them before leaving?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, 'keep'),
            child: const Text('Keep Editing'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, 'discard'),
            child: const Text('Discard'),
          ),
          ElevatedButton.icon(
            onPressed: () => Navigator.pop(dialogContext, 'save'),
            icon: const Icon(Icons.save_rounded, size: 18),
            label: const Text('Save'),
          ),
        ],
      ),
    );

    switch (action) {
      case 'discard':
        return true;
      case 'save':
        return widget.invoiceToEdit != null
            ? await _updateInvoice()
            : await _createInvoice();
      default:
        return false;
    }
  }

  Future<void> _loadCustomersAndProducts(bool isEditing) async {
    if(!mounted) return;
    setState(() => isLoading = true);

    try {
      final settingsRepo = ref.read(settingsRepositoryProvider);
      final results = await Future.wait([
        ref.read(customerRepositoryProvider).getCustomersPaginated(
            offset: 0, limit: _customerFetchLimit), // 0
        ref.read(productRepositoryProvider).getProductsPaginated(
            offset: 0, limit: _productFetchLimit, type: _businessType.key), // 1
        isEditing
            ? Future.value(widget.invoiceToEdit?.invoiceNumber ?? widget.invoiceToEdit?.id)
            : ref.read(invoiceRepositoryProvider).peekNextInvoiceNumber(invoiceType), // 2
        settingsRepo.getCurrency(), // 3 — discarded below when editing/cloning
        settingsRepo.getUpiIds(), // 4
        settingsRepo.getBankAccounts(), // 5
        settingsRepo.getShowGstFields(), // 6
        settingsRepo.getFractionalQuantity(), // 7
        settingsRepo.getQuantityLabel(), // 8
        settingsRepo.getShowQuantity(), // 9
        settingsRepo.getBusinessType(), // 10
        settingsRepo.getDateFormat(), // 11
        settingsRepo.getShowPreviousBalance(), // 12
        settingsRepo.getShowAliasNameInPdf(), // 13
        settingsRepo.getShowTaxButtonInInvoicePage(), // 14
        settingsRepo.getDefaultInvoiceTitle(), // 15
        settingsRepo.getAllowDuplicateInvoiceItems(), // 16
        settingsRepo.getDefaultTaxMode(), // 17
      ]);

      final c = results[0] as List<Customer>;
      final p = results[1] as List<Product>;
      final metadataIds = {
        ...p.map((e) => e.id),
        ...invoiceItems.map((e) => e.product.id),
      }.toList();
      final productMetadata = await ref
          .read(productRepositoryProvider)
          .getProductMetadataForIds(metadataIds);
      final invNumber = results[2] as String?;

      // Use the existing invoice's currency when editing or cloning,
      // otherwise fall back to the current app-wide currency setting.
      final String loadedCurrencyCode;
      final String loadedCurrencySymbol;
      if (isEditing && widget.invoiceToEdit != null) {
        loadedCurrencyCode = widget.invoiceToEdit!.currencyCode;
        loadedCurrencySymbol = widget.invoiceToEdit!.currencySymbol;
      } else if (widget.cloneFrom != null) {
        loadedCurrencyCode = widget.cloneFrom!.currencyCode;
        loadedCurrencySymbol = widget.cloneFrom!.currencySymbol;
      } else {
        final currency = results[3] as CurrencyOption;
        loadedCurrencyCode = currency.code;
        loadedCurrencySymbol = currency.symbol;
      }

      final upiEntries = results[4] as List<UpiEntry>;
      final bankAccounts = results[5] as List<BankAccount>;
      final showGst = results[6] as bool;
      final fractionalQty = results[7] as bool;
      final quantityLabelSetting = results[8] as String;
      final showQuantity = results[9] as bool;
      final businessType = results[10] as BusinessType;
      final dateFormatOpt = results[11] as DateFormatOption;
      final showPrevBalance = results[12] as bool;
      final showAliasNameInPdf = results[13] as bool;
      final showTaxButtonInInvoicePage = results[14] as bool;
      final defaultInvoiceTitle = results[15] as String?;
      final allowDuplicateInvoiceItems = results[16] as bool;
      final defaultTaxMode = results[17] as String;

      // Determine which UPI to pre-select.
      String? existingUpiId;
      if (isEditing && widget.invoiceToEdit != null) {
        existingUpiId = widget.invoiceToEdit!.upiId;
      } else if (widget.cloneFrom != null) {
        existingUpiId = widget.cloneFrom!.upiId;
      }

      UpiEntry? preselectedUpi;
      if (existingUpiId != null && existingUpiId.isNotEmpty) {
        preselectedUpi =
            upiEntries.where((e) => e.id == existingUpiId).firstOrNull;
      }
      preselectedUpi ??= upiEntries.where((e) => e.isDefault).firstOrNull ??
          upiEntries.firstOrNull;

      // Determine which bank account to pre-select.
      String? existingBankId;
      if (isEditing && widget.invoiceToEdit != null) {
        existingBankId = widget.invoiceToEdit!.bankAccountId;
      } else if (widget.cloneFrom != null) {
        existingBankId = widget.cloneFrom!.bankAccountId;
      }
      BankAccount? preselectedBank;
      if (existingBankId != null && existingBankId.isNotEmpty) {
        preselectedBank = bankAccounts
            .where((e) => e.accountNumber == existingBankId)
            .firstOrNull;
      }
      preselectedBank ??= bankAccounts.where((e) => e.isDefault).firstOrNull ??
          bankAccounts.firstOrNull;

      // Pre-mark custom items that were already saved to the product list,
      // using the persisted is_product_saved flag on each InvoiceItem.
      _savedAdHocIds.addAll(
        invoiceItems
            .where((item) =>
                item.product.id.startsWith('custom-') && item.isProductSaved)
            .map((item) => item.product.id),
      );
      if(!mounted) return;
      setState(() {
        customers = c;
        filteredCustomers = List.from(c);
        products = p;
        filteredProducts = List.from(p);
        _productMetadata = productMetadata;
        if (invNumber != null) {
          currentInvoiceNumber = invNumber;
        }
        _currencyCode = loadedCurrencyCode;
        _currencySymbol = loadedCurrencySymbol;
        _upiEntries = upiEntries;
        _selectedUpi = preselectedUpi;
        _bankAccounts = bankAccounts;
        _selectedBankAccount = preselectedBank;
        _showGstFields = showGst;
        _fractionalQuantity = fractionalQty;
        _showQuantity = showQuantity;
        _showPreviousBalance = showPrevBalance;
        _showAliasNameInPdf = showAliasNameInPdf;
        _allowDuplicateInvoiceItems = allowDuplicateInvoiceItems;
        if (!isEditing && widget.cloneFrom == null) {
          _isTaxEnabled = showTaxButtonInInvoicePage;
          _isPerItem = defaultTaxMode == 'perItem';
        }
        _businessType = businessType;
        _adHocItemType =
            businessType == BusinessType.service ? 'service' : 'product';
        // For new invoices, use the global setting. Edit/clone already set _quantityLabel in initState.
        if (!isEditing && widget.cloneFrom == null) {
          _quantityLabel = quantityLabelSetting;
          invoiceTitle = invoiceType == 'Invoice' ? defaultInvoiceTitle : null;
        }
        _datePattern = dateFormatOpt.key;
        dateController.text =
            DateFormat(_datePattern).format(_selectedOrderDate);
        if (_selectedDueDate != null) {
          dueDateController.text =
              DateFormat(_datePattern).format(_selectedDueDate!);
        }
        isLoading = false;
      });
      // Edit/clone may have preloaded selectedCustomer from an invoice
      // snapshot whose id was never actually saved to the customers table
      // (see _resolveInvoiceCustomer). Confirm it still exists so the UI
      // doesn't silently treat an unsaved customer as saved.
      if ((isEditing || widget.cloneFrom != null) && selectedCustomer != null) {
        final stillExists = await ref
            .read(customerRepositoryProvider)
            .getCustomerById(selectedCustomer!.id);
        if (!mounted) return;
        if (stillExists == null) {
          setState(() => selectedCustomer = null);
        }
      }
      if (showPrevBalance && selectedCustomer != null) {
        await _loadPreviousBalanceDue(selectedCustomer);
      }
      _completeInitialLoad();
    } catch (e) {
      if(!mounted) return;
      setState(() => isLoading = false);
      _completeInitialLoad();
      if (mounted) {
        if(kDebugMode) print(e);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading data: $e'),showCloseIcon: true,),
        );
      }
    }
  }

  void addInvoiceProductPrompt(Product product) {
    final quantityController = TextEditingController();
    final discountController = TextEditingController(
        text: product.defaultDiscount > 0
            ? product.defaultDiscount.toString()
            : '0');
    final unitPriceController =
        TextEditingController(text: product.price.toString());
    final extraCostController = TextEditingController();
    final unitController = TextEditingController(text: product.unit);

    bool discountPerUnit = true;
    String dialogUnit = product.unit;
    int insertAt = invoiceItems.length + 1;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Theme.of(context).primaryColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(Icons.shopping_cart,
                    color: Theme.of(context).primaryColor),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  '${product.name} ($_currencySymbol ${product.price})',
                  style: const TextStyle(fontSize: AppFontSize.xlarge),
                ),
              ),
            ],
          ),
          content: SizedBox(
            width: MediaQuery.of(context).size.width * 0.3,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (product.unlimitedStock)
                  Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.green[50],
                      border: Border.all(color: Colors.green[200]!),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.all_inclusive,
                            color: Colors.green, size: 18),
                        const SizedBox(width: 8),
                        const Text('Unlimited Stock',
                            style: TextStyle(color: Colors.green)),
                      ],
                    ),
                  )
                else if (product.stock <= 0)
                  Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.red[50],
                      border: Border.all(color: Colors.red[200]!),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.warning_amber,
                            color: Colors.red, size: 18),
                        const SizedBox(width: 8),
                        const Text('Out of Stock',
                            style: TextStyle(
                                color: Colors.red,
                                fontWeight: FontWeight.bold)),
                      ],
                    ),
                  )
                else
                  Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.green[50],
                      border: Border.all(color: Colors.green[200]!),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.inventory_2,
                            color: Colors.green, size: 18),
                        const SizedBox(width: 8),
                        Text('Available Stock: ${product.stock}',
                            style: const TextStyle(color: Colors.green)),
                      ],
                    ),
                  ),
                Builder(builder: (context) {
                  final meta = _productMetadata[product.id];
                  final expiryDate = (meta?.expiryDate?.isNotEmpty ?? false)
                      ? DateTime.tryParse(meta!.expiryDate!)
                      : null;
                  final isExpired =
                      expiryDate != null && expiryDate.isBefore(DateTime.now());
                  final storageLocation = meta?.storageLocation;
                  if ((storageLocation == null || storageLocation.isEmpty) &&
                      expiryDate == null) {
                    return const SizedBox.shrink();
                  }
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        if (storageLocation != null && storageLocation.isNotEmpty)
                          Chip(
                            avatar: const Icon(Icons.place_outlined,
                                size: 14, color: Colors.blueGrey),
                            label: Text(storageLocation,
                                style: const TextStyle(fontSize: AppFontSize.xsmall)),
                            visualDensity: VisualDensity.compact,
                            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            backgroundColor: Colors.blueGrey[50],
                          ),
                        if (expiryDate != null)
                          Chip(
                            avatar: Icon(
                                isExpired ? Icons.error_outline : Icons.event_outlined,
                                size: 14,
                                color: isExpired ? Colors.red : Colors.orange[800]),
                            label: Text(
                                '${isExpired ? 'Expired ' : 'Exp '}${DateFormat(_datePattern).format(expiryDate)}',
                                style: TextStyle(
                                    fontSize: AppFontSize.xsmall,
                                    color: isExpired ? Colors.red : null)),
                            visualDensity: VisualDensity.compact,
                            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            backgroundColor: isExpired ? Colors.red[50] : Colors.orange[50],
                          ),
                      ],
                    ),
                  );
                }),
                if (_showQuantity) ...[
                  TextField(
                    controller: quantityController,
                    decoration: InputDecoration(
                      labelText: _quantityLabel.trim().isNotEmpty
                          ? _quantityLabel.trim()
                          : 'Quantity',
                      hintText: '1',
                      border: OutlineInputBorder(
                          borderRadius:
                              BorderRadius.circular(AppBorderRadius.xsmall)),
                      prefixIcon: const Icon(Icons.numbers),
                      filled: true,
                      fillColor: Theme.of(context).colorScheme.surfaceContainerHighest,
                    ),
                    keyboardType: _fractionalQuantity
                        ? const TextInputType.numberWithOptions(decimal: true)
                        : TextInputType.number,
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                    ],
                  ),
                  const SizedBox(height: 16),
                  _buildUnitPicker(
                    selectedUnit: dialogUnit,
                    customController: unitController,
                    onUnitChanged: (v) => setDialogState(() => dialogUnit = v),
                  ),
                  const SizedBox(height: 16),
                ],
                TextField(
                  controller: discountController,
                  decoration: InputDecoration(
                    labelText: 'Discount',
                    border: OutlineInputBorder(
                        borderRadius:
                            BorderRadius.circular(AppBorderRadius.xsmall)),
                    prefixIcon: const Icon(Icons.discount),
                    filled: true,
                    fillColor: Theme.of(context).colorScheme.surfaceContainerHighest,
                  ),
                  keyboardType: TextInputType.number,
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                  ],
                ),
                const SizedBox(height: 8),
                _buildDiscountPerUnitToggle(discountPerUnit,
                    (val) => setDialogState(() => discountPerUnit = val)),
                const SizedBox(height: 16),
                TextField(
                  controller: unitPriceController,
                  decoration: InputDecoration(
                    labelText: 'Unit Price (override)',
                    helperText: 'Default: $_currencySymbol${product.price}',
                    border: OutlineInputBorder(
                        borderRadius:
                            BorderRadius.circular(AppBorderRadius.xsmall)),
                    prefixText: '$_currencySymbol ',
                    filled: true,
                    fillColor: Theme.of(context).colorScheme.surfaceContainerHighest,
                  ),
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                  ],
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: extraCostController,
                  decoration: InputDecoration(
                    labelText: 'Extra Cost (optional)',
                    hintText: '0.00',
                    helperText: 'Flat fee added on top of the line total',
                    border: OutlineInputBorder(
                        borderRadius:
                            BorderRadius.circular(AppBorderRadius.xsmall)),
                    prefixIcon: const Icon(Icons.add_circle_outline, size: 18),
                    filled: true,
                    fillColor: Theme.of(context).colorScheme.surfaceContainerHighest,
                  ),
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                  ],
                ),
                if (invoiceItems.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  const Divider(height: 1),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Icon(Icons.format_list_numbered,
                          size: 16, color: Theme.of(context).colorScheme.onSurfaceVariant),
                      const SizedBox(width: 8),
                      Text('Insert at position',
                          style: TextStyle(fontSize: 13, color: Theme.of(context).colorScheme.onSurfaceVariant)),
                      const Spacer(),
                      IconButton(
                        icon: const Icon(Icons.remove_circle_outline),
                        onPressed: insertAt > 1
                            ? () => setDialogState(() => insertAt--)
                            : null,
                        iconSize: 20,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                      ),
                      const SizedBox(width: 12),
                      Text('$insertAt',
                          style: const TextStyle(
                              fontSize: 16, fontWeight: FontWeight.bold)),
                      const SizedBox(width: 12),
                      IconButton(
                        icon: const Icon(Icons.add_circle_outline),
                        onPressed: insertAt < invoiceItems.length + 1
                            ? () => setDialogState(() => insertAt++)
                            : null,
                        iconSize: 20,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8)),
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              ),
              onPressed: () async {
                final qty = !_showQuantity
                    ? 1.0
                    : _fractionalQuantity
                        ? (double.tryParse(quantityController.text) ?? 1.0)
                        : (int.tryParse(quantityController.text) ?? 1)
                            .toDouble();
                final discount =
                    double.tryParse(discountController.text) ?? 0.0;
                final parsedUnitPrice =
                    double.tryParse(unitPriceController.text);
                final unitPrice = (parsedUnitPrice != null &&
                        parsedUnitPrice != product.price)
                    ? parsedUnitPrice
                    : null;
                final extraCost = double.tryParse(extraCostController.text);

                // Check stock
                if (!product.unlimitedStock &&
                    product.stock > 0 &&
                    qty > product.stock) {
                  // Insufficient stock — ask user if they want to add anyway
                  Navigator.pop(context);
                  final addAnyway = await showDialog<bool>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: const Text('Insufficient Stock'),
                      content: Text(
                        'Only ${product.stock} unit(s) available. Add $qty anyway?',
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(ctx, false),
                          child: const Text('Cancel'),
                        ),
                        ElevatedButton(
                          onPressed: () => Navigator.pop(ctx, true),
                          style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.orange),
                          child: const Text('Add Anyway'),
                        ),
                      ],
                    ),
                  );
                  if (addAnyway == true) {
                    addInvoiceProduct(
                        InvoiceItem(
                            product: product,
                            quantity: qty,
                            discount: discount,
                            unitPrice: unitPrice,
                            extraCost: extraCost,
                            unit: dialogUnit.trim(),
                            discountPerUnit: discountPerUnit),
                        insertAt: insertAt);
                  }
                } else if (!product.unlimitedStock && product.stock <= 0) {
                  Navigator.pop(context);
                  final addAnyway = await showDialog<bool>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: const Text('Out of Stock'),
                      content:
                          Text('${product.name} is out of stock. Add anyway?'),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(ctx, false),
                          child: const Text('Cancel'),
                        ),
                        ElevatedButton(
                          onPressed: () => Navigator.pop(ctx, true),
                          style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.orange),
                          child: const Text('Add Anyway'),
                        ),
                      ],
                    ),
                  );
                  if (addAnyway == true) {
                    addInvoiceProduct(
                        InvoiceItem(
                            product: product,
                            quantity: qty,
                            discount: discount,
                            unitPrice: unitPrice,
                            extraCost: extraCost,
                            unit: dialogUnit.trim(),
                            discountPerUnit: discountPerUnit),
                        insertAt: insertAt);
                  }
                } else {
                  Navigator.pop(context);
                  addInvoiceProduct(
                      InvoiceItem(
                          product: product,
                          quantity: qty,
                          discount: discount,
                          unitPrice: unitPrice,
                          extraCost: extraCost,
                          unit: dialogUnit.trim(),
                          discountPerUnit: discountPerUnit),
                      insertAt: insertAt);
                }
              },
              child: const Text('Add'),
            ),
          ],
        ),
      ),
    );
  }

  void addInvoiceProduct(InvoiceItem invoiceItem, {int? insertAt}) {
    final isAdHoc = invoiceItem.product.id.startsWith('custom-');
    final exists = !isAdHoc &&
        !_allowDuplicateInvoiceItems &&
        invoiceItems.any((item) => item.product.id == invoiceItem.product.id);

    if (exists) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: Colors.white),
              SizedBox(width: 12),
              Text('This product has already been added'),
            ],
          ),
          backgroundColor: Colors.orange,
          behavior: SnackBarBehavior.floating,
          showCloseIcon: true,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppBorderRadius.xsmall)),
        ),
      );
    } else {
      final isAppend = insertAt == null || insertAt >= invoiceItems.length + 1;
      if(!mounted) return;
      setState(() {
        if (!isAppend) {
          invoiceItems.insert(insertAt - 1, invoiceItem);
        } else {
          invoiceItems.add(invoiceItem);
        }
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_invoiceItemsScrollController.hasClients && isAppend) {
          _invoiceItemsScrollController.animateTo(
            _invoiceItemsScrollController.position.maxScrollExtent,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
          );
        }
      });
    }
  }

  /// Builds the Customer to attach to the invoice. If the form fields no
  /// longer match `selectedCustomer`'s saved record (edited but not saved
  /// via _saveCustomer), the invoice must NOT keep pointing at that
  /// customer's id — doing so would link invoiceId -> customerId while the
  /// snapshot's name/address/etc silently disagree with that customer's
  /// actual row. Falls back to a fresh, unlinked id in that case.
  bool get _customerFormMatchesSelected {
    final sel = selectedCustomer;
    return sel != null &&
        sel.name == nameController.text &&
        sel.email == emailController.text &&
        sel.phone == phoneController.text &&
        sel.address == addressController.text &&
        sel.gstin == gstinController.text &&
        sel.businessName == businessNameController.text;
  }

  Customer _resolveInvoiceCustomer() {
    final name = nameController.text;
    final email = emailController.text;
    final phone = phoneController.text;
    final address = addressController.text;
    final gstin = gstinController.text;
    final businessName = businessNameController.text;

    final matchesSelected = _customerFormMatchesSelected;
    final sel = selectedCustomer;

    return Customer(
      id: matchesSelected ? sel!.id : const Uuid().v4(),
      name: name,
      email: email,
      phone: phone,
      address: address,
      gstin: gstin,
      businessName: businessName,
    );
  }

  Future<bool> _createInvoice() async {
    if (nameController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Row(
            children: [
              Icon(Icons.error_outline, color: Colors.white),
              SizedBox(width: 12),
              Text('Please provide customer name'),
            ],
          ),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
          showCloseIcon: true,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppBorderRadius.xsmall)),
        ),
      );
      return false;
    }

    if (invoiceItems.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Row(
            children: [
              Icon(Icons.error_outline, color: Colors.white),
              SizedBox(width: 12),
              Text('Please add at least one item'),
            ],
          ),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
          showCloseIcon: true,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppBorderRadius.xsmall)),
        ),
      );
      return false;
    }

    if(!mounted) return false;
    setState(() => isLoading = true);

    try {
      final invoiceId = await InvoicePdfServices.generateNextId();
      final invoiceNumber =
          await InvoicePdfServices.generateNextInvoiceNumber(invoiceType);
      final invoice = Invoice(
        id: invoiceId,
        invoiceNumber: invoiceNumber,
        customer: _resolveInvoiceCustomer(),
        items: List.from(invoiceItems),
        date: _selectedOrderDate,
        dueDate: _selectedDueDate,
        notes: notesController.text.isNotEmpty ? notesController.text : null,
        taxRate: _taxMode == TaxMode.global ? taxRate : 0.0,
        type: invoiceType,
        invoiceTitle: invoiceType == 'Invoice' ? invoiceTitle : null,
        currencyCode: _currencyCode,
        currencySymbol: _currencySymbol,
        taxMode: _taxMode,
        upiId: _selectedUpi?.id,
        bankAccountId: _selectedBankAccount?.accountNumber,
        quantityLabel:
            _quantityLabel.trim().isEmpty ? null : _quantityLabel.trim(),
        additionalCosts: _buildAdditionalCosts(),
      );

      await ref.read(invoiceRepositoryProvider).insertInvoice(invoice);

      if (!mounted) return true;
      setState(() {
        _invoice = invoice;
        currentInvoiceNumber = invoice.invoiceNumber ?? invoice.id;
        isLoading = false;
      });
      _markFormClean();

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.check_circle, color: Colors.white),
              const SizedBox(width: 12),
              Text('$invoiceType created successfully!'),
            ],
          ),
          backgroundColor: Colors.green,
          behavior: SnackBarBehavior.floating,
          showCloseIcon: true,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppBorderRadius.xsmall)),
        ),
      );
      return true;
    } catch (e) {
      if (!mounted) return false;
      setState(() => isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error creating invoice: $e'),showCloseIcon: true,),
      );
      return false;
    }
  }

  void _editInvoiceItem(int index) {
    final item = invoiceItems[index];
    final quantityController = TextEditingController(
        text: item.quantity == 1.0
            ? ''
            : item.quantity == item.quantity.roundToDouble()
                ? item.quantity.toInt().toString()
                : item.quantity.toString());
    final discountController =
        TextEditingController(text: item.discount.toString());
    final unitPriceController =
        TextEditingController(text: item.effectivePrice.toString());
    final extraCostController = TextEditingController(
        text: item.extraCost != null ? item.extraCost.toString() : '');
    bool discountPerUnit = item.discountPerUnit;
    final unitController = TextEditingController(text: item.effectiveUnit.toString());
    String dialogUnit = item.effectiveUnit.toString();
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Row(
            children: [
              Icon(Icons.edit, color: Colors.blue),
              SizedBox(width: 12),
              Text('Edit Item', style: TextStyle(fontSize: AppFontSize.xlarge)),
            ],
          ),
          content: SizedBox(
            width: MediaQuery.of(context).size.width * 0.3,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.blue.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(AppBorderRadius.xsmall),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        item.product.type == 'service'
                            ? Icons.design_services_outlined
                            : Icons.inventory_2,
                        color: Colors.blue[700],
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          item.product.name,
                          style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: AppFontSize.xlarge),
                        ),
                      ),
                      if (_businessType == BusinessType.both) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: item.product.type == 'service'
                                ? Colors.purple.withValues(alpha: 0.15)
                                : Colors.indigo.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            item.product.type == 'service'
                                ? 'Service'
                                : 'Product',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: item.product.type == 'service'
                                  ? Colors.purple[700]
                                  : Colors.indigo[700],
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                Builder(builder: (context) {
                  final meta = _productMetadata[item.product.id];
                  final expiryDate = (meta?.expiryDate?.isNotEmpty ?? false)
                      ? DateTime.tryParse(meta!.expiryDate!)
                      : null;
                  final isExpired =
                      expiryDate != null && expiryDate.isBefore(DateTime.now());
                  final storageLocation = meta?.storageLocation;
                  if ((storageLocation == null || storageLocation.isEmpty) &&
                      expiryDate == null) {
                    return const SizedBox.shrink();
                  }
                  return Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        if (storageLocation != null && storageLocation.isNotEmpty)
                          Chip(
                            avatar: const Icon(Icons.place_outlined,
                                size: 14, color: Colors.blueGrey),
                            label: Text(storageLocation,
                                style: const TextStyle(fontSize: AppFontSize.xsmall)),
                            visualDensity: VisualDensity.compact,
                            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            backgroundColor: Colors.blueGrey[50],
                          ),
                        if (expiryDate != null)
                          Chip(
                            avatar: Icon(
                                isExpired ? Icons.error_outline : Icons.event_outlined,
                                size: 14,
                                color: isExpired ? Colors.red : Colors.orange[800]),
                            label: Text(
                                '${isExpired ? 'Expired ' : 'Exp '}${DateFormat(_datePattern).format(expiryDate)}',
                                style: TextStyle(
                                    fontSize: AppFontSize.xsmall,
                                    color: isExpired ? Colors.red : null)),
                            visualDensity: VisualDensity.compact,
                            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            backgroundColor: isExpired ? Colors.red[50] : Colors.orange[50],
                          ),
                      ],
                    ),
                  );
                }),
                const SizedBox(height: 20),
                if (_showQuantity) ...[
                  TextField(
                    controller: quantityController,
                    decoration: InputDecoration(
                      labelText: _quantityLabel.trim().isNotEmpty
                          ? _quantityLabel.trim()
                          : 'Quantity',
                      border: OutlineInputBorder(
                          borderRadius:
                              BorderRadius.circular(AppBorderRadius.xsmall)),
                      prefixIcon: const Icon(Icons.numbers),
                      filled: true,
                      fillColor: Theme.of(context).colorScheme.surfaceContainerHighest,
                    ),
                    keyboardType: _fractionalQuantity
                        ? const TextInputType.numberWithOptions(decimal: true)
                        : TextInputType.number,
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                    ],
                  ),
                  const SizedBox(height: 16),
                  _buildUnitPicker(
                    selectedUnit: dialogUnit,
                    customController: unitController,
                    onUnitChanged: (v) => setDialogState(() => dialogUnit = v),
                  ),
                ],
                const SizedBox(height: 16),
                TextField(
                  controller: discountController,
                  decoration: InputDecoration(
                    labelText: 'Discount',
                    border: OutlineInputBorder(
                        borderRadius:
                            BorderRadius.circular(AppBorderRadius.xsmall)),
                    prefixIcon: const Icon(Icons.discount),
                    filled: true,
                    fillColor: Theme.of(context).colorScheme.surfaceContainerHighest,
                  ),
                  keyboardType: TextInputType.number,
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                  ],
                ),
                const SizedBox(height: 8),
                _buildDiscountPerUnitToggle(discountPerUnit,
                    (val) => setDialogState(() => discountPerUnit = val)),
                const SizedBox(height: 16),
                TextField(
                  controller: unitPriceController,
                  decoration: InputDecoration(
                    labelText: 'Unit Price (override)',
                    helperText:
                        'Default: $_currencySymbol${item.product.price}',
                    border: OutlineInputBorder(
                        borderRadius:
                            BorderRadius.circular(AppBorderRadius.xsmall)),
                    prefixText: '$_currencySymbol ',
                    filled: true,
                    fillColor: Theme.of(context).colorScheme.surfaceContainerHighest,
                  ),
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                  ],
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: extraCostController,
                  decoration: InputDecoration(
                    labelText: 'Extra Cost (optional)',
                    hintText: '0.00',
                    helperText: 'Flat fee added on top of the line total',
                    border: OutlineInputBorder(
                        borderRadius:
                            BorderRadius.circular(AppBorderRadius.xsmall)),
                    prefixIcon: const Icon(Icons.add_circle_outline, size: 18),
                    filled: true,
                    fillColor: Theme.of(context).colorScheme.surfaceContainerHighest,
                  ),
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                  ],
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8)),
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              ),
              onPressed: () {
                final parsedUnitPrice =
                    double.tryParse(unitPriceController.text);
                final unitPrice = (parsedUnitPrice != null &&
                        parsedUnitPrice != item.product.price)
                    ? parsedUnitPrice
                    : null;
                final extraCost = double.tryParse(extraCostController.text);
                final updatedItem = InvoiceItem(
                  product: item.product,
                  quantity: !_showQuantity
                      ? 1.0
                      : _fractionalQuantity
                          ? (double.tryParse(quantityController.text) ??
                              item.quantity)
                          : (int.tryParse(quantityController.text) ??
                                  double.tryParse(quantityController.text)
                                      ?.toInt() ??
                                  item.quantity.toInt())
                              .toDouble(),
                  discount:
                      double.tryParse(discountController.text) ?? item.discount,
                  unitPrice: unitPrice,
                  extraCost: extraCost,
                  unit: dialogUnit.trim(),
                  discountPerUnit: discountPerUnit,
                );
                if(!mounted) return;
                setState(() {
                  invoiceItems[index] = updatedItem;
                });

                Navigator.pop(context);
              },
              child: const Text('Update'),
            ),
          ],
        ),
      ),
    );
  }

  void _addAdHocItemDialog() {
    final nameController = TextEditingController();
    final aliasNameController = TextEditingController();
    final priceController = TextEditingController();
    final quantityController = TextEditingController();
    final discountController = TextEditingController(text: '0');
    final taxRateController = TextEditingController(text: '0');
    final extraCostController = TextEditingController();
    final unitController = TextEditingController();

    bool discountPerUnit = true;
    bool dialogPriceIncludesTax = false;
    String dialogItemType = _adHocItemType;
    int insertAt = invoiceItems.length + 1;
    String selectedUnit = '';

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Row(
            children: [
              Icon(Icons.add_box, color: Colors.deepPurple),
              SizedBox(width: 12),
              Text('Custom Item',
                  style: TextStyle(fontSize: AppFontSize.xlarge)),
            ],
          ),
          content: SizedBox(
            width: MediaQuery.of(context).size.width * 0.3,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_businessType == BusinessType.both) ...[
                  SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(
                          value: 'product',
                          label: Text('Product'),
                          icon: Icon(Icons.inventory_2_outlined, size: 16)),
                      ButtonSegment(
                          value: 'service',
                          label: Text('Service'),
                          icon: Icon(Icons.design_services_outlined, size: 16)),
                    ],
                    selected: {dialogItemType},
                    onSelectionChanged: (val) =>
                        setDialogState(() => dialogItemType = val.first),
                  ),
                  const SizedBox(height: 16),
                ],
                TextField(
                  controller: nameController,
                  decoration: InputDecoration(
                    labelText: 'Item Name',
                    border: OutlineInputBorder(
                        borderRadius:
                            BorderRadius.circular(AppBorderRadius.xsmall)),
                    prefixIcon: const Icon(Icons.label),
                    filled: true,
                    fillColor: Theme.of(context).colorScheme.surfaceContainerHighest,
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: aliasNameController,
                  decoration: InputDecoration(
                    labelText: 'Alias (for PDF)',
                    border: OutlineInputBorder(
                        borderRadius:
                            BorderRadius.circular(AppBorderRadius.xsmall)),
                    prefixIcon: const Icon(Icons.translate),
                    filled: true,
                    fillColor: Theme.of(context).colorScheme.surfaceContainerHighest,
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: priceController,
                  decoration: InputDecoration(
                    labelText: _showQuantity ? 'Unit Price' : 'Rate',
                    border: OutlineInputBorder(
                        borderRadius:
                            BorderRadius.circular(AppBorderRadius.xsmall)),
                    prefixText: '$_currencySymbol ',
                    filled: true,
                    fillColor: Theme.of(context).colorScheme.surfaceContainerHighest,
                  ),
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                  ],
                ),
                if (_showQuantity) ...[
                  const SizedBox(height: 16),
                  TextField(
                    controller: quantityController,
                    decoration: InputDecoration(
                      labelText: _quantityLabel.trim().isNotEmpty
                          ? _quantityLabel.trim()
                          : 'Quantity',
                      hintText: '1',
                      border: OutlineInputBorder(
                          borderRadius:
                              BorderRadius.circular(AppBorderRadius.xsmall)),
                      prefixIcon: const Icon(Icons.numbers),
                      filled: true,
                      fillColor: Theme.of(context).colorScheme.surfaceContainerHighest,
                    ),
                    keyboardType: _fractionalQuantity
                        ? const TextInputType.numberWithOptions(decimal: true)
                        : TextInputType.number,
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                    ],
                  ),
                  const SizedBox(height: 16),
                  _buildUnitPicker(
                    selectedUnit: selectedUnit,
                    customController: unitController,
                    onUnitChanged: (v) => setDialogState(() => selectedUnit = v),
                  ),
                ],
                const SizedBox(height: 16),
                TextField(
                  controller: discountController,
                  decoration: InputDecoration(
                    labelText: 'Discount',
                    border: OutlineInputBorder(
                        borderRadius:
                            BorderRadius.circular(AppBorderRadius.xsmall)),
                    prefixIcon: const Icon(Icons.discount),
                    filled: true,
                    fillColor: Theme.of(context).colorScheme.surfaceContainerHighest,
                  ),
                  keyboardType: TextInputType.number,
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                  ],
                ),
                const SizedBox(height: 8),
                _buildDiscountPerUnitToggle(discountPerUnit,
                    (val) => setDialogState(() => discountPerUnit = val)),
                const SizedBox(height: 16),
                TextField(
                  controller: extraCostController,
                  decoration: InputDecoration(
                    labelText: 'Extra Cost (optional)',
                    hintText: '0.00',
                    helperText: 'Flat fee added on top of the line total',
                    border: OutlineInputBorder(
                        borderRadius:
                            BorderRadius.circular(AppBorderRadius.xsmall)),
                    prefixIcon: const Icon(Icons.add_circle_outline, size: 18),
                    filled: true,
                    fillColor: Theme.of(context).colorScheme.surfaceContainerHighest,
                  ),
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                  ],
                ),
                if (_taxMode == TaxMode.perItem) ...[
                  const SizedBox(height: 16),
                  TextField(
                    controller: taxRateController,
                    decoration: InputDecoration(
                      labelText: 'Tax Rate (%)',
                      border: OutlineInputBorder(
                          borderRadius:
                              BorderRadius.circular(AppBorderRadius.xsmall)),
                      prefixIcon: const Icon(Icons.percent),
                      filled: true,
                      fillColor: Theme.of(context).colorScheme.surfaceContainerHighest,
                    ),
                    keyboardType: TextInputType.number,
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                    ],
                  ),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                    title: const Text('Price includes tax'),
                    value: dialogPriceIncludesTax,
                    onChanged: (val) => setDialogState(
                        () => dialogPriceIncludesTax = val ?? false),
                  ),
                ],
                if (invoiceItems.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  const Divider(height: 1),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Icon(Icons.format_list_numbered,
                          size: 16, color: Theme.of(context).colorScheme.onSurfaceVariant),
                      const SizedBox(width: 8),
                      Text('Insert at position',
                          style: TextStyle(fontSize: 13, color: Theme.of(context).colorScheme.onSurfaceVariant)),
                      const Spacer(),
                      IconButton(
                        icon: const Icon(Icons.remove_circle_outline),
                        onPressed: insertAt > 1
                            ? () => setDialogState(() => insertAt--)
                            : null,
                        iconSize: 20,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                      ),
                      const SizedBox(width: 12),
                      Text('$insertAt',
                          style: const TextStyle(
                              fontSize: 16, fontWeight: FontWeight.bold)),
                      const SizedBox(width: 12),
                      IconButton(
                        icon: const Icon(Icons.add_circle_outline),
                        onPressed: insertAt < invoiceItems.length + 1
                            ? () => setDialogState(() => insertAt++)
                            : null,
                        iconSize: 20,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.deepPurple,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8)),
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              ),
              onPressed: () {
                final name = nameController.text.trim();
                final price = double.tryParse(priceController.text) ?? 0.0;
                final taxRate = _taxMode == TaxMode.perItem
                    ? (int.tryParse(taxRateController.text) ?? 0)
                    : 0;
                if (name.isEmpty) return;

                final adHocProduct = Product(
                  id: 'custom-${const Uuid().v4()}',
                  name: name,
                  description: '',
                  price: price,
                  stock: 0,
                  hsncode: '',
                  tax_rate: taxRate,
                  unit: selectedUnit.trim(),
                  type: dialogItemType,
                  aliasName: aliasNameController.text.trim().isEmpty
                      ? null
                      : aliasNameController.text.trim(),
                  priceIncludesTax: dialogPriceIncludesTax,
                );
                final extraCost = double.tryParse(extraCostController.text);
                final item = InvoiceItem(
                  product: adHocProduct,
                  quantity: !_showQuantity
                      ? 1.0
                      : _fractionalQuantity
                          ? (double.tryParse(quantityController.text) ?? 1.0)
                          : (int.tryParse(quantityController.text) ?? 1)
                              .toDouble(),
                  discount: double.tryParse(discountController.text) ?? 0.0,
                  extraCost: extraCost,
                  unit: selectedUnit.trim(),
                  discountPerUnit: discountPerUnit,
                );
                Navigator.pop(context);
                addInvoiceProduct(item, insertAt: insertAt);
              },
              child: const Text('Add', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }

  // void _filterProducts(String query) {
  //   setState(() {
  //     if (query.isEmpty) {
  //       filteredProducts = List.from(products);
  //     } else {
  //       filteredProducts = products
  //           .where((product) => product.name.toLowerCase().contains(query.toLowerCase()))
  //           .toList();
  //     }
  //   });
  // }

  void _filterProducts(String query) {
    if (!mounted) return;
    _productSearchDebounce?.cancel();
    _productSearchDebounce = Timer(const Duration(milliseconds: 400), () async {
      final requestId = ++_productSearchRequestId;
      final repo = ref.read(productRepositoryProvider);
      final results = await repo.getProductsPaginated(
          offset: 0, limit: _productFetchLimit, query: query, type: _businessType.key);
      final metadata =
          await repo.getProductMetadataForIds(results.map((e) => e.id).toList());
      if (requestId != _productSearchRequestId || !mounted) return;
      setState(() {
        filteredProducts = results;
        _productMetadata = {..._productMetadata, ...metadata};
      });
    });
  }

  void _filterCustomers(String query) {
    if (!mounted) return;
    _customerSearchDebounce?.cancel();
    _customerSearchDebounce = Timer(const Duration(milliseconds: 400), () async {
      final requestId = ++_customerSearchRequestId;
      final results = await ref.read(customerRepositoryProvider).getCustomersPaginated(
          offset: 0, limit: _customerFetchLimit, query: query);
      if (requestId != _customerSearchRequestId || !mounted) return;
      setState(() {
        filteredCustomers = results;
      });
    });
  }

  Future<void> _selectCustomer(Customer? customer) async {
    if(!mounted) return;
    setState(() {
      selectedCustomer = customer;
      nameController.text = customer?.name ?? '';
      emailController.text = customer?.email ?? '';
      phoneController.text = customer?.phone ?? '';
      addressController.text = customer?.address ?? '';
      gstinController.text = customer?.gstin ?? '';
      businessNameController.text = customer?.businessName ?? '';
    });
    await _loadPreviousBalanceDue(customer);
  }

  Future<void> _loadPreviousBalanceDue(Customer? customer) async {
    final requestId = ++_previousBalanceRequestSerial;

    if (!_showPreviousBalance ||
        customer == null ||
        customer.id.trim().isEmpty ||
        invoiceType != 'Invoice')
    {
      if (!mounted) return;
      setState(() {
        _previousBalanceDue = 0.0;
        _isPreviousBalanceLoading = false;
      });
      return;
    }
    if(!mounted) return;
    setState(() => _isPreviousBalanceLoading = true);
    try {
      final balance = await ref.read(invoiceRepositoryProvider).getPreviousBalanceDueForCustomer(
        customerId: customer.id,
        currencyCode: _currencyCode,
        asOfDate: _selectedOrderDate,
        currentInvoiceId: currentInvoiceNumber.isNotEmpty
            ? currentInvoiceNumber
            : _invoice?.id,
      );
      if (!mounted || requestId != _previousBalanceRequestSerial) return;
      setState(() {
        _previousBalanceDue = balance;
        _isPreviousBalanceLoading = false;
      });
    } catch (_) {
      if (!mounted || requestId != _previousBalanceRequestSerial) return;
      setState(() {
        _previousBalanceDue = 0.0;
        _isPreviousBalanceLoading = false;
      });
    }
  }

  Widget _customerSearchView() {
    return Card(
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: Color(0xFFE2E8F0)),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
            decoration: const BoxDecoration(
              color: Color(0xFFF8FAFC),
              border: Border(bottom: BorderSide(color: Color(0xFFE2E8F0))),
              borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.people_outline_rounded,
                        size: 16, color: Color(0xFF64748B)),
                    const SizedBox(width: 8),
                    Text('Customers',
                        style: AppTypography.titleSm(CbTokens.ink)),
                  ],
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: customerSearchController,
                  onChanged: _filterCustomers,
                  decoration: InputDecoration(
                    labelText: 'Search Customer',
                    labelStyle: TextStyle(fontSize: AppFontSize.small, color: CbTokens.muted),
                    border: OutlineInputBorder(
                        borderRadius:
                            BorderRadius.circular(AppBorderRadius.xsmall),
                        borderSide: const BorderSide(color: CbTokens.hairline)),
                    enabledBorder: OutlineInputBorder(
                        borderRadius:
                            BorderRadius.circular(AppBorderRadius.xsmall),
                        borderSide: const BorderSide(color: CbTokens.hairline)),
                    filled: true,
                    fillColor: CbTokens.canvas,
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: AppPadding.small,
                        vertical: AppPadding.xsmall),
                  ),
                ),
              ],
            ),
          ),
          SizedBox(
            height: MediaQuery.of(context).size.height * 0.15,
            child: filteredCustomers.isEmpty
                ? Center(
                    child: Text('No customers found',
                        style: AppTypography.bodySm(CbTokens.muted)),
                  )
                : Scrollbar(
                    controller: _customerScrollController,
                    thumbVisibility: true,
                    child: ListView.builder(
                      itemCount: filteredCustomers.length > 5
                          ? 5
                          : filteredCustomers.length,
                      controller: _customerScrollController,
                      itemBuilder: (context, index) {
                        final customer = filteredCustomers[index];
                        final isSelected = selectedCustomer?.id == customer.id;
                        return Container(
                          margin: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? const Color(0xFFEFF6FF)
                                : null,
                            borderRadius: BorderRadius.circular(8),
                            border: isSelected ? Border.all(color: const Color(0xFFBFDBFE)) : null,
                          ),
                          child: ListTile(
                            leading: CircleAvatar(
                              backgroundColor: CbTokens.primary,
                              radius: AppFontSize.large,
                              child: Text(
                                customer.name.isNotEmpty ? customer.name[0].toUpperCase() : '?',
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 13),
                              ),
                            ),
                            title: Text(
                              customer.name,
                              style: TextStyle(
                                fontSize: AppFontSize.medium,
                                fontWeight: isSelected
                                    ? FontWeight.bold
                                    : FontWeight.normal,
                              ),
                            ),
                            subtitle: Text(customer.phone, style: AppTypography.caption(CbTokens.muted)),
                            trailing: isSelected
                                ? const Text('Selected', style: TextStyle(color: CbTokens.primary, fontWeight: FontWeight.w600, fontSize: 12))
                                : TextButton(
                                    onPressed: () => _selectCustomer(customer),
                                    child: const Text('Select', style: TextStyle(fontSize: 12)),
                                  ),
                            onTap: () => _selectCustomer(customer),
                          ),
                        );
                      },
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _productSearchView() {
    return Card(
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: Color(0xFFE2E8F0)),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 14),
            decoration: const BoxDecoration(
              color: Color(0xFFF8FAFC),
              border: Border(bottom: BorderSide(color: Color(0xFFE2E8F0))),
              borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.inventory_2_outlined,
                        size: 16, color: Color(0xFF64748B)),
                    const SizedBox(width: 8),
                    Text('Products & Services',
                        overflow: TextOverflow.ellipsis,
                        style: AppTypography.titleSm(CbTokens.ink)),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  'Out of stock items are shown in red',
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.caption(const Color(0xFFDC2626)),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: searchController,
                  onChanged: _filterProducts,
                  decoration: InputDecoration(
                    labelText: 'Search Product',
                    labelStyle: TextStyle(fontSize: AppFontSize.small, color: CbTokens.muted),
                    border: OutlineInputBorder(
                        borderRadius:
                            BorderRadius.circular(AppBorderRadius.xsmall),
                        borderSide: const BorderSide(color: CbTokens.hairline)),
                    enabledBorder: OutlineInputBorder(
                        borderRadius:
                            BorderRadius.circular(AppBorderRadius.xsmall),
                        borderSide: const BorderSide(color: CbTokens.hairline)),
                    filled: true,
                    fillColor: CbTokens.canvas,
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: AppPadding.small,
                        vertical: AppPadding.xsmall),
                  ),
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: _addAdHocItemDialog,
                    style: TextButton.styleFrom(
                      foregroundColor: CbTokens.primary,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                    ),
                    child: const Text('+ Custom Item',
                        style: TextStyle(fontSize: AppFontSize.small, fontWeight: FontWeight.w600)),
                  ),
                ),
              ],
            ),
          ),
          SizedBox(
            height: MediaQuery.of(context).size.height * 0.35,
            child: filteredProducts.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.search_off,
                            size: 40, color: Theme.of(context).colorScheme.onSurfaceVariant),
                        const SizedBox(height: 8),
                        Text('No products found',
                            style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
                      ],
                    ),
                  )
                : Scrollbar(
                    thumbVisibility: true,
                    controller: _productScrollController,
                    child: ListView.builder(
                      itemCount: filteredProducts.length > 8
                          ? 8
                          : filteredProducts.length,
                      controller: _productScrollController,
                      itemBuilder: (context, index) {
                        final product = filteredProducts[index];
                        final meta = _productMetadata[product.id];
                        final expiryDate = (meta?.expiryDate?.isNotEmpty ?? false)
                            ? DateTime.tryParse(meta!.expiryDate!)
                            : null;
                        final isExpired =
                            expiryDate != null && expiryDate.isBefore(DateTime.now());
                        final storageLocation = meta?.storageLocation;
                        return Container(
                          margin: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: const Color(0xFFE2E8F0)),
                          ),
                          child: ListTile(
                            title: Text(
                              product.name,
                              maxLines: 5,
                              style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: AppFontSize.medium),
                            ),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'HSN/SAC: ${product.hsncode.toUpperCase()}',
                                  maxLines: 2,
                                  style: const TextStyle(
                                      color: Color(0xFF007CFF),
                                      fontWeight: FontWeight.w500,
                                      fontSize: AppFontSize.small),
                                ),
                                const SizedBox(height: 2),
                                Row(
                                  children: [
                                    Flexible(
                                      child: Text(
                                        '$_currencySymbol${product.price.toStringAsFixed(2)}  ·  Stock: ${product.unlimitedStock ? '∞' : product.stock}',
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                            color: Color(0xFF16A34A),
                                            fontWeight: FontWeight.bold,
                                            fontSize: AppFontSize.small),
                                      ),
                                    ),
                                    if (product.defaultDiscount > 0) ...[
                                      const SizedBox(width: 6),
                                      Flexible(
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 5, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: const Color(0xFFFFF7ED),
                                            border: Border.all(
                                                color: const Color(0xFFFDBA74)),
                                            borderRadius:
                                                BorderRadius.circular(4),
                                          ),
                                          child: Text(
                                            '-$_currencySymbol${product.defaultDiscount.toStringAsFixed(0)}',
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                                color: Color(0xFFC2410C),
                                                fontSize: 10,
                                                fontWeight: FontWeight.bold),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                                if (storageLocation != null &&
                                        storageLocation.isNotEmpty ||
                                    expiryDate != null) ...[
                                  const SizedBox(height: 4),
                                  Wrap(
                                    spacing: 6,
                                    runSpacing: 4,
                                    children: [
                                      if (storageLocation != null &&
                                          storageLocation.isNotEmpty)
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: const Color(0xFFF1F5F9),
                                            borderRadius: BorderRadius.circular(4),
                                            border: Border.all(color: const Color(0xFFCBD5E1)),
                                          ),
                                          child: Text(
                                            storageLocation,
                                            style: const TextStyle(fontSize: 10, color: Color(0xFF475569)),
                                          ),
                                        ),
                                      if (expiryDate != null)
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: isExpired ? const Color(0xFFFEE2E2) : const Color(0xFFFEF3C7),
                                            borderRadius: BorderRadius.circular(4),
                                            border: Border.all(color: isExpired ? const Color(0xFFFCA5A5) : const Color(0xFFFCD34D)),
                                          ),
                                          child: Text(
                                            '${isExpired ? 'Expired ' : 'Exp '}${DateFormat(_datePattern).format(expiryDate)}',
                                            style: TextStyle(
                                              fontSize: 10,
                                              fontWeight: FontWeight.w600,
                                              color: isExpired ? const Color(0xFFB91C1C) : const Color(0xFFB45309),
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                ],
                              ],
                            ),
                            trailing: OutlinedButton(
                              onPressed: () => addInvoiceProductPrompt(product),
                              style: OutlinedButton.styleFrom(
                                backgroundColor: Colors.white,
                                foregroundColor: const Color(0xFF007CFF),
                                side: const BorderSide(color: Color(0xFF007CFF)),
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                minimumSize: Size.zero,
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                                textStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
                              ),
                              child: const Text('+ Add'),
                            ),
                            onTap: () => addInvoiceProductPrompt(product),
                          ),
                        );
                      },
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _invoiceDetailsForm() {
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(8),
      borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
    );
    final focusedBorder = OutlineInputBorder(
      borderRadius: BorderRadius.circular(8),
      borderSide: const BorderSide(color: Color(0xFF007CFF), width: 1.5),
    );

    return Card(
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 14),
            decoration: const BoxDecoration(
              color: Color(0xFFF8FAFC),
              border: Border(bottom: BorderSide(color: Color(0xFFE2E8F0))),
              borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
            ),
            child: Row(
              children: [
                const Icon(Icons.receipt_long_outlined,
                    size: 16, color: Color(0xFF64748B)),
                const SizedBox(width: 8),
                Text(
                  '$invoiceType Details',
                  style: AppTypography.titleSm(const Color(0xFF0F172A)),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: dateController,
                        readOnly: true,
                        style: const TextStyle(fontSize: 13, color: Color(0xFF0F172A)),
                        decoration: InputDecoration(
                          labelText: 'Order Date',
                          labelStyle: const TextStyle(fontSize: 13, color: Color(0xFF64748B)),
                          border: border,
                          enabledBorder: border,
                          focusedBorder: focusedBorder,
                          filled: true,
                          fillColor: const Color(0xFFF8FAFC),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                          suffixIcon: const Icon(Icons.calendar_today_outlined, size: 16, color: Color(0xFF64748B)),
                        ),
                        onTap: () async {
                          final picked = await showDatePicker(
                            context: context,
                            initialDate: _selectedOrderDate,
                            firstDate: DateTime(2000),
                            lastDate: DateTime(2100),
                          );
                          if (picked != null) {
                            if (!mounted) return;
                            setState(() {
                              _selectedOrderDate = picked;
                              dateController.text =
                                  DateFormat(_datePattern).format(picked);
                            });
                            await _loadPreviousBalanceDue(selectedCustomer);
                          }
                        },
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: TextField(
                        controller: dueDateController,
                        readOnly: true,
                        style: const TextStyle(fontSize: 13, color: Color(0xFF0F172A)),
                        decoration: InputDecoration(
                          labelText: 'Due Date',
                          labelStyle: const TextStyle(fontSize: 13, color: Color(0xFF64748B)),
                          border: border,
                          enabledBorder: border,
                          focusedBorder: focusedBorder,
                          filled: true,
                          fillColor: const Color(0xFFF8FAFC),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                          suffixIcon: dueDateController.text.isNotEmpty
                              ? IconButton(
                                  icon: const Icon(Icons.clear, size: 16),
                                  onPressed: () {
                                    if (!mounted) return;
                                    setState(() {
                                      _selectedDueDate = null;
                                      dueDateController.clear();
                                    });
                                  },
                                )
                              : const Icon(Icons.calendar_today_outlined, size: 16, color: Color(0xFF64748B)),
                        ),
                        onTap: () async {
                          final picked = await showDatePicker(
                            context: context,
                            initialDate: _selectedDueDate ?? DateTime.now(),
                            firstDate: DateTime(2000),
                            lastDate: DateTime(2100),
                          );
                          if (picked != null) {
                            if (!mounted) return;
                            setState(() {
                              _selectedDueDate = picked;
                              dueDateController.text =
                                  DateFormat(_datePattern).format(picked);
                            });
                          }
                        },
                      ),
                    )
                  ],
                ),
                const SizedBox(height: 14),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        isExpanded: true,
                        value: invoiceType,
                        style: const TextStyle(fontSize: 13, color: Color(0xFF0F172A)),
                        decoration: InputDecoration(
                          labelText: 'Type',
                          labelStyle: const TextStyle(fontSize: 13, color: Color(0xFF64748B)),
                          helperText: isEditing
                              ? 'Type can\'t be changed after creation'
                              : null,
                          border: border,
                          enabledBorder: border,
                          focusedBorder: focusedBorder,
                          filled: true,
                          fillColor: const Color(0xFFF8FAFC),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        ),
                        items: const [
                          DropdownMenuItem(
                              value: 'Invoice',
                              child: Text('Invoice', style: TextStyle(fontSize: 13))),
                          DropdownMenuItem(
                              value: 'Quotation',
                              child: Text('Quotation', style: TextStyle(fontSize: 13))),
                          DropdownMenuItem(
                              value: 'Receipt',
                              child: Text('Receipt', style: TextStyle(fontSize: 13))),
                        ],
                        onChanged: isEditing
                            ? null
                            : (value) {
                                if (value != null) resetInvoiceType(value);
                              },
                      ),
                    ),
                    if (invoiceType == 'Invoice') ...[
                      const SizedBox(width: 14),
                      Expanded(
                        child: DropdownButtonFormField<String?>(
                          isExpanded: true,
                          value: invoiceTitle,
                          style: const TextStyle(fontSize: 13, color: Color(0xFF0F172A)),
                          decoration: InputDecoration(
                            labelText: _showGstFields ? 'GST Title' : 'TAX Title',
                            labelStyle: const TextStyle(fontSize: 13, color: Color(0xFF64748B)),
                            border: border,
                            enabledBorder: border,
                            focusedBorder: focusedBorder,
                            filled: true,
                            fillColor: const Color(0xFFF8FAFC),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                          ),
                          items: const [
                            DropdownMenuItem(
                                value: null,
                                child: Text('Invoice', style: TextStyle(fontSize: 13))),
                            DropdownMenuItem(
                                value: 'Tax Invoice',
                                child: Text('Tax Invoice', style: TextStyle(fontSize: 13))),
                            DropdownMenuItem(
                                value: 'Bill of Supply',
                                child: Text('Bill of Supply', style: TextStyle(fontSize: 13))),
                            DropdownMenuItem(
                                value: 'Invoice-cum-Bill of Supply',
                                child: Text('Invoice-cum-Bill of Supply', style: TextStyle(fontSize: 13))),
                            DropdownMenuItem(
                                value: 'Credit Note',
                                child: Text('Credit Note', style: TextStyle(fontSize: 13))),
                            DropdownMenuItem(
                                value: 'Debit Note',
                                child: Text('Debit Note', style: TextStyle(fontSize: 13))),
                            DropdownMenuItem(
                                value: 'Revised Invoice',
                                child: Text('Revised Invoice', style: TextStyle(fontSize: 13))),
                          ],
                          onChanged: (value) => setState(() => invoiceTitle = value),
                        ),
                      ),
                    ],
                    if (_quantityLabel.trim().isNotEmpty) ...[
                      const SizedBox(width: 14),
                      Expanded(
                        child: Tooltip(
                          message: 'Qty column label — change in Invoice Settings',
                          child: InputDecorator(
                            decoration: InputDecoration(
                              labelText: 'Qty Label',
                              labelStyle: const TextStyle(fontSize: 13, color: Color(0xFF64748B)),
                              prefixIcon: const Icon(Icons.tag, size: 16, color: Color(0xFF64748B)),
                              border: border,
                              enabledBorder: border,
                              focusedBorder: focusedBorder,
                              filled: true,
                              fillColor: const Color(0xFFF8FAFC),
                              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                            ),
                            child: Text(
                              _quantityLabel.trim(),
                              style: const TextStyle(fontSize: 13, color: Color(0xFF0F172A)),
                            ),
                          ),
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
    );
  }

  Future<void> resetInvoiceType(String invoiceType_) async {
    if(!mounted) return;
    setState(() {
      invoiceType = invoiceType_;
      if (invoiceType_ != 'Invoice') invoiceTitle = null;
    });
    if (!isEditing) {
      final invNumber =
          await InvoicePdfServices.peekNextInvoiceNumber(invoiceType_);
      if (mounted) setState(() => currentInvoiceNumber = invNumber);
    }
    await _loadPreviousBalanceDue(selectedCustomer);
  }

  Future<void> resetValues(String invoiceType_) async {
    if(!mounted) return;
    final invType = await InvoicePdfServices.peekNextInvoiceNumber(invoiceType_);
    setState(() {
      invoiceType = invoiceType_;
      currentInvoiceNumber = invType;
      _invoice = null;
      isEditing = false;
      selectedCustomer = null;
      invoiceItems.clear();
      for (final row in _additionalCostControllers) {
        row.label.dispose();
        row.amount.dispose();
      }
      _additionalCostControllers.clear();
      _showAdditionalCosts = false;
      notesController.clear();
      nameController.clear();
      emailController.clear();
      phoneController.clear();
      addressController.clear();
      gstinController.clear();
      businessNameController.clear();
      taxRate = Tax.defaultTaxRate;
      _selectedOrderDate = DateTime.now();
      dateController.text = DateFormat(_datePattern).format(_selectedOrderDate);
      _selectedDueDate = null;
      dueDateController.clear();
      _previousBalanceDue = 0.0;
      _isPreviousBalanceLoading = false;
    });
    await _setAdditionalNote(forceDefault: true);
    _markFormClean();
  }

  Future<void> _showPhoneTakenError(String ownerName) async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.error_outline, color: Colors.red),
            SizedBox(width: 12),
            Text('Phone Number Already In Use'),
          ],
        ),
        content: Text(
          'This phone number belongs to "$ownerName".\n\nCannot save this customer with a phone number that already belongs to someone else.',
        ),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  Future<void> _saveCustomer() async {
    if (_isSavingCustomer) return;
    if(!mounted) return;
    setState(() => _isSavingCustomer = true);
    try {
    final name = nameController.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: Colors.white),
              SizedBox(width: 12),
              Text('Please enter a customer name before saving'),
            ],
          ),
          backgroundColor: Colors.orange,
          behavior: SnackBarBehavior.floating,
          showCloseIcon: true,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      );
      return;
    }

    final phone = phoneController.text.trim();

    // Editing an already-selected customer whose phone changed: ask whether
    // to overwrite that customer's record or split off a new one, instead
    // of silently matching/creating based on phone alone.
    var forceNew = false;
    final sel = selectedCustomer;
    if (sel != null && sel.id.isNotEmpty && phone != sel.phone) {
      if (!mounted) return;
      final choice = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Row(
            children: [
              Icon(Icons.phone_forwarded, color: Colors.orange),
              SizedBox(width: 12),
              Text('Phone Number Changed'),
            ],
          ),
          content: Text(
            'The phone number for "${sel.name}" was changed.\n\nUpdate their existing record, or save these details as a new customer?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, null),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, 'new'),
              child: const Text('Save as New'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
              onPressed: () => Navigator.pop(ctx, 'update'),
              child: const Text('Update Existing',
                  style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      );
      if (choice == null) return;
      if (choice == 'update') {
        final phoneOwner = await ref.read(customerRepositoryProvider).findByPhone(phone);
        if (phoneOwner != null && phoneOwner.id != sel.id) {
          await _showPhoneTakenError(phoneOwner.name);
          return;
        }
        final updated = Customer(
          id: sel.id,
          name: name,
          email: emailController.text.trim(),
          phone: phone,
          address: addressController.text.trim(),
          gstin: gstinController.text.trim(),
          businessName: businessNameController.text.trim(),
        );
        await ref.read(customerRepositoryProvider).updateCustomer(updated);
        final reloaded = await ref.read(customerRepositoryProvider).getAllCustomers();
        if (!mounted) return;
        setState(() {
          selectedCustomer = updated;
          customers = reloaded;
          filteredCustomers = reloaded;
        });
        await _loadPreviousBalanceDue(updated);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('${updated.name} updated in customer list'),
              behavior: SnackBarBehavior.floating,
              showCloseIcon: true,
            ),
          );
        }
        return;
      }
      // choice == 'new': fall through to the phone-lookup flow below,
      // which still guards against colliding with a *different* customer's phone.
      forceNew = true;
    }

    final existing = await ref.read(customerRepositoryProvider).findByPhone(phone);

    if (existing != null && forceNew) {
      // User explicitly chose "Save as New" above, but this phone number
      // is already used by a different customer. Phone numbers must be
      // unique — block instead of creating a duplicate.
      await _showPhoneTakenError(existing.name);
      return;
    }

    if (existing != null) {
      if (!mounted) return;
      final choice = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Row(
            children: [
              Icon(Icons.person_search, color: Colors.orange),
              SizedBox(width: 12),
              Text('Customer Already Exists'),
            ],
          ),
          content: Text(
            '"${existing.name}" is already saved with this phone number.\n\nUse their existing details, or update their record with the current information?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, 'use'),
              child: const Text('Use Existing'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
              onPressed: () => Navigator.pop(ctx, 'update'),
              child:
                  const Text('Update', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      );
      if (choice == null) return;

      if (choice == 'use') {
        if (!mounted) return;
        setState(() {
          selectedCustomer = existing;
          nameController.text = existing.name;
          emailController.text = existing.email;
          phoneController.text = existing.phone;
          addressController.text = existing.address;
          gstinController.text = existing.gstin;
          businessNameController.text = existing.businessName;
        });
        await _loadPreviousBalanceDue(existing);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Using existing customer "${existing.name}"'),
              behavior: SnackBarBehavior.floating,
              showCloseIcon: true,
            ),
          );
        }
        return;
      }

      final updated = Customer(
        id: existing.id,
        name: name,
        email: emailController.text.trim(),
        phone: phone,
        address: addressController.text.trim(),
        gstin: gstinController.text.trim(),
        businessName: businessNameController.text.trim(),
      );
      await ref.read(customerRepositoryProvider).updateCustomer(updated);
      final reloaded = await ref.read(customerRepositoryProvider).getAllCustomers();
      if(!mounted) return;
      setState(() {
        selectedCustomer = updated;
        customers = reloaded;
        filteredCustomers = reloaded;
      });
      await _loadPreviousBalanceDue(updated);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${updated.name} updated in customer list'),
            behavior: SnackBarBehavior.floating,
            showCloseIcon: true,
          ),
        );
      }
    } else {
      final newCustomer = Customer(
        id: const Uuid().v4(),
        name: name,
        email: emailController.text.trim(),
        phone: phone,
        address: addressController.text.trim(),
        gstin: gstinController.text.trim(),
        businessName: businessNameController.text.trim(),
      );
      await ref.read(customerRepositoryProvider).insertCustomer(newCustomer);
      final reloaded = await ref.read(customerRepositoryProvider).getAllCustomers();
      if(!mounted) return;
      setState(() {
        selectedCustomer = newCustomer;
        customers = reloaded;
        filteredCustomers = reloaded;
      });
      await _loadPreviousBalanceDue(newCustomer);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${newCustomer.name} saved to customer list'),
            behavior: SnackBarBehavior.floating,
            showCloseIcon: true,
          ),
        );
      }
    }
    } finally {
      if (mounted) setState(() => _isSavingCustomer = false);
    }
  }

  /// Re-reads the selected customer's current record and overwrites the
  /// form fields with it. The invoice keeps whatever was last saved on it
  /// (a snapshot) until this is explicitly triggered — editing an invoice
  /// does NOT silently pull in customer changes made elsewhere since.
  Future<void> _refreshCustomerFromRecord() async {
    final current = selectedCustomer;
    if (current == null || current.id.trim().isEmpty) return;
    final latest = await ref.read(customerRepositoryProvider).getCustomerById(current.id);
    if (!mounted) return;
    if (latest == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Customer record no longer exists'),showCloseIcon: true,),
      );
      return;
    }
    if(!mounted) return;
    setState(() {
      selectedCustomer = latest;
      nameController.text = latest.name;
      emailController.text = latest.email;
      phoneController.text = latest.phone;
      addressController.text = latest.address;
      gstinController.text = latest.gstin;
      businessNameController.text = latest.businessName;
    });
    if(!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
          content: Text('Customer details refreshed'),
      showCloseIcon: true,),
    );
  }

  void _clearCustomerSelection() {
    if (!mounted) return;
    setState(() {
      selectedCustomer = null;
      nameController.clear();
      emailController.clear();
      phoneController.clear();
      addressController.clear();
      gstinController.clear();
      businessNameController.clear();
      _previousBalanceDue = 0.0;
      _isPreviousBalanceLoading = false;
    });
  }

  Widget _customerDetailsForm() {
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(8),
      borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
    );
    final focusedBorder = OutlineInputBorder(
      borderRadius: BorderRadius.circular(8),
      borderSide: const BorderSide(color: Color(0xFF007CFF), width: 1.5),
    );

    return Card(
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
            decoration: const BoxDecoration(
              color: Color(0xFFF8FAFC),
              border: Border(bottom: BorderSide(color: Color(0xFFE2E8F0))),
              borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                const Icon(Icons.person_outline_rounded,
                    size: 16, color: Color(0xFF64748B)),
                const SizedBox(width: 8),
                Text(
                  'Customer Details',
                  style: AppTypography.titleSm(const Color(0xFF0F172A)),
                ),
                const Spacer(),
                Wrap(
                  alignment: WrapAlignment.end,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    (selectedCustomer != null && _customerFormMatchesSelected)
                        ? Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 5),
                            decoration: BoxDecoration(
                              color: const Color(0xFFEFF6FF),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: const Color(0xFFBFDBFE)),
                            ),
                            child: const Text(
                              'Saved',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF007CFF),
                              ),
                            ),
                          )
                        : Tooltip(
                            message: 'Save customer to customer list',
                            child: ElevatedButton(
                              onPressed: _isSavingCustomer ? null : _saveCustomer,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF007CFF),
                                foregroundColor: Colors.white,
                                elevation: 0,
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 14, vertical: 8),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                              ),
                              child: Text(
                                _isSavingCustomer ? 'Saving...' : 'Save Customer',
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ),
                    if (selectedCustomer != null && selectedCustomer!.id.trim().isNotEmpty) ...[
                      Tooltip(
                        message: 'Reload this customer\'s latest saved details',
                        child: OutlinedButton(
                          onPressed: _refreshCustomerFromRecord,
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 6),
                            side: const BorderSide(color: Color(0xFFCBD5E1)),
                            foregroundColor: const Color(0xFF0F172A),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                          child: const Text('Refresh',
                              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500)),
                        ),
                      ),
                      Tooltip(
                        message: 'Clear customer selection and enter a new one',
                        child: OutlinedButton(
                          onPressed: _clearCustomerSelection,
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 6),
                            side: const BorderSide(color: Color(0xFFCBD5E1)),
                            foregroundColor: const Color(0xFF0F172A),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                          child: const Text('Clear',
                              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500)),
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Row 1: Customer Name | Business Name
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: nameController,
                        onChanged: (_) => setState(() {}),
                        style: const TextStyle(fontSize: 13, color: Color(0xFF0F172A)),
                        decoration: InputDecoration(
                          labelText: 'Customer Name *',
                          labelStyle: const TextStyle(fontSize: 13, color: Color(0xFF64748B)),
                          border: border,
                          enabledBorder: border,
                          focusedBorder: focusedBorder,
                          filled: true,
                          fillColor: const Color(0xFFF8FAFC),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        ),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: TextField(
                        controller: businessNameController,
                        onChanged: (_) => setState(() {}),
                        style: const TextStyle(fontSize: 13, color: Color(0xFF0F172A)),
                        decoration: InputDecoration(
                          labelText: 'Business Name',
                          labelStyle: const TextStyle(fontSize: 13, color: Color(0xFF64748B)),
                          border: border,
                          enabledBorder: border,
                          focusedBorder: focusedBorder,
                          filled: true,
                          fillColor: const Color(0xFFF8FAFC),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                // Row 2: Phone | Email
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: phoneController,
                        onChanged: (_) => setState(() {}),
                        style: const TextStyle(fontSize: 13, color: Color(0xFF0F172A)),
                        decoration: InputDecoration(
                          labelText: 'Phone',
                          labelStyle: const TextStyle(fontSize: 13, color: Color(0xFF64748B)),
                          border: border,
                          enabledBorder: border,
                          focusedBorder: focusedBorder,
                          filled: true,
                          fillColor: const Color(0xFFF8FAFC),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        ),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: TextField(
                        controller: emailController,
                        onChanged: (_) => setState(() {}),
                        style: const TextStyle(fontSize: 13, color: Color(0xFF0F172A)),
                        decoration: InputDecoration(
                          labelText: 'Email',
                          labelStyle: const TextStyle(fontSize: 13, color: Color(0xFF64748B)),
                          border: border,
                          enabledBorder: border,
                          focusedBorder: focusedBorder,
                          filled: true,
                          fillColor: const Color(0xFFF8FAFC),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                // Row 3: Address | GSTIN (conditional)
                Row(
                  children: [
                    Expanded(
                      flex: _showGstFields ? 3 : 1,
                      child: TextField(
                        controller: addressController,
                        onChanged: (_) => setState(() {}),
                        style: const TextStyle(fontSize: 13, color: Color(0xFF0F172A)),
                        decoration: InputDecoration(
                          labelText: 'Address',
                          labelStyle: const TextStyle(fontSize: 13, color: Color(0xFF64748B)),
                          border: border,
                          enabledBorder: border,
                          focusedBorder: focusedBorder,
                          filled: true,
                          fillColor: const Color(0xFFF8FAFC),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        ),
                      ),
                    ),
                    if (_showGstFields) ...[
                      const SizedBox(width: 14),
                      Expanded(
                        flex: 2,
                        child: TextField(
                          controller: gstinController,
                          onChanged: (_) => setState(() {}),
                          style: const TextStyle(fontSize: 13, color: Color(0xFF0F172A)),
                          decoration: InputDecoration(
                            labelText: 'Tax/VAT Number (GSTIN)',
                            labelStyle: const TextStyle(fontSize: 13, color: Color(0xFF64748B)),
                            border: border,
                            enabledBorder: border,
                            focusedBorder: focusedBorder,
                            filled: true,
                            fillColor: const Color(0xFFF8FAFC),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                          ),
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
    );
  }

  List<AdditionalCost> _buildAdditionalCosts() {
    final costs = <AdditionalCost>[];
    for (final row in _additionalCostControllers) {
      final label = row.label.text.trim();
      final amount = double.tryParse(row.amount.text) ?? 0.0;
      if (label.isNotEmpty && amount > 0) {
        costs.add(AdditionalCost(label: label, amount: amount));
      }
    }
    return costs;
  }

  Widget _buildAdditionalCostsSection() {
    final primary = Theme.of(context).primaryColor;
    return Container(
      margin: const EdgeInsets.only(top: 8),
      decoration: BoxDecoration(
        color: Colors.teal.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(AppBorderRadius.xsmall),
        border: Border.all(color: Colors.teal.withValues(alpha: 0.25)),
      ),
      child: Column(
        children: [
          // Header row — always visible, toggles collapse
          InkWell(
            borderRadius: const BorderRadius.vertical(
                top: Radius.circular(AppBorderRadius.xsmall)),
            onTap: () {
              if(!mounted) return;
              setState(() => _showAdditionalCosts = !_showAdditionalCosts);
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Row(
                children: [
                  Text(
                    'Additional Costs',
                    style: AppTypography.bodySm(CbTokens.ink).copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (_additionalCostControllers.isNotEmpty) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: CbTokens.primary,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        '${_additionalCostControllers.length}',
                        style: const TextStyle(
                            fontSize: 11,
                            color: Colors.white,
                            fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                  const Spacer(),
                  Icon(
                    _showAdditionalCosts
                        ? Icons.expand_less
                        : Icons.expand_more,
                    color: CbTokens.muted,
                    size: 20,
                  ),
                ],
              ),
            ),
          ),

          // Collapsible body
          if (_showAdditionalCosts) ...[
            const Divider(height: 1, color: CbTokens.hairline),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                children: [
                  ..._additionalCostControllers.asMap().entries.map((entry) {
                    final i = entry.key;
                    final row = entry.value;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(
                        children: [
                          Expanded(
                            flex: 3,
                            child: TextField(
                              controller: row.label,
                              onChanged: (_) {
                                if(!mounted) return;
                                setState(() {});
                                },
                              decoration: InputDecoration(
                                labelText: 'Label',
                                hintText: 'e.g. Shipping',
                                isDense: true,
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(
                                      AppBorderRadius.xsmall),
                                ),
                                filled: true,
                                fillColor: Theme.of(context).colorScheme.surfaceContainerHighest,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            flex: 2,
                            child: TextField(
                              controller: row.amount,
                              onChanged: (_) {
                                if(!mounted) return;
                                setState(() {});
                              },
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                      decimal: true),
                              decoration: InputDecoration(
                                labelText: 'Amount',
                                prefixText: '$_currencySymbol ',
                                isDense: true,
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(
                                      AppBorderRadius.xsmall),
                                ),
                                filled: true,
                                fillColor: Theme.of(context).colorScheme.surfaceContainerHighest,
                              ),
                            ),
                          ),
                          const SizedBox(width: 4),
                          IconButton(
                            icon: const Icon(Icons.remove_circle_outline,
                                color: Colors.red, size: 20),
                            tooltip: 'Remove',
                            onPressed: () {
                              if(!mounted) return;
                              setState(() {
                                _additionalCostControllers[i].label.dispose();
                                _additionalCostControllers[i].amount.dispose();
                                _additionalCostControllers.removeAt(i);
                              });
                            },
                          ),
                        ],
                      ),
                    );
                  }),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: () {
                        if(!mounted) return;
                        setState(() {
                          _additionalCostControllers.add((
                            label: TextEditingController(),
                            amount: TextEditingController(),
                          ));
                        });
                      },
                      icon: Icon(Icons.add_circle_outline,
                          color: primary, size: 16),
                      label: Text('Add Row',
                          style: TextStyle(color: primary, fontSize: 13)),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildDiscountPerUnitToggle(bool value, ValueChanged<bool> onChanged) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Discount per unit',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
            Text(
              value ? '(price − discount) × qty' : '(price × qty) − discount',
              style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
          ],
        ),
        Switch(value: value, onChanged: onChanged),
      ],
    );
  }

  Widget _buildUnitPicker({
    required String selectedUnit,
    required TextEditingController customController,
    required ValueChanged<String> onUnitChanged,
  }) {
    return _UnitPicker(
      initialUnit: selectedUnit,
      customController: customController,
      onUnitChanged: onUnitChanged,
    );
  }

  Widget _buildItemDetail(String label, String value, {Color? color}) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '$label: ',
          style: TextStyle(
            fontSize: 13,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: color,
          ),
        ),
      ],
    );
  }

  Widget _buildTotalRow(String label, double amount, bool isTotal) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          '$label:',
          style: TextStyle(
            fontSize: isTotal ? 18 : 14,
            fontWeight: isTotal ? FontWeight.bold : FontWeight.normal,
            color: isTotal ? Colors.green : Theme.of(context).colorScheme.onSurface,
          ),
        ),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            '$_currencySymbol${amount.toStringAsFixed(2)}',
            textAlign: TextAlign.end,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: isTotal ? 20 : 14,
              fontWeight: FontWeight.bold,
              color: isTotal ? Colors.green : Theme.of(context).colorScheme.onSurface,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPreviousBalanceDueRow() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 190;
        final value = _isPreviousBalanceLoading
            ? SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.orange[800],
                ),
              )
            : Text(
                '$_currencySymbol${_previousBalanceDue.toStringAsFixed(2)}',
                textAlign: TextAlign.end,
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
                style: TextStyle(
                  fontSize: compact ? 13 : 14,
                  fontWeight: FontWeight.bold,
                  color: Colors.orange[900],
                ),
              );

        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.orange[50],
            borderRadius: BorderRadius.circular(AppBorderRadius.xsmall),
            border: Border.all(color: Colors.orange[200]!, width: 0.8),
          ),
          child: Row(
            children: [
              Icon(
                Icons.account_balance_wallet_outlined,
                size: 16,
                color: Colors.orange[800],
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  compact ? 'Prev. Balance' : 'Previous Balance Due',
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                  style: TextStyle(
                    fontSize: compact ? 12 : 13,
                    fontWeight: FontWeight.w600,
                    color: Colors.orange[900],
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Flexible(
                flex: compact ? 2 : 1,
                child: Align(
                  alignment: Alignment.centerRight,
                  child: value,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildTotalDueRow(double totalDue) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 170;
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.orange[700],
            borderRadius: BorderRadius.circular(AppBorderRadius.xsmall),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  compact ? 'Due' : 'Total Due',
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                  style: TextStyle(
                    fontSize: compact ? 11 : 13,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Flexible(
                flex: compact ? 2 : 1,
                child: Text(
                  '$_currencySymbol${totalDue.toStringAsFixed(2)}',
                  textAlign: TextAlign.end,
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                  style: TextStyle(
                    fontSize: compact ? 12 : 14,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildPaymentSummaryPanel(Invoice invoice) {
    final amountPaid = invoice.amountPaid;
    final outstanding = invoice.outstandingBalance;
    final isPaid = outstanding <= 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        const Divider(height: 24),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Text(
                'Amount Paid:',
                style: TextStyle(fontSize: 14, color: Colors.green[700]),
              ),
            ),
            Text(
              '$_currencySymbol${amountPaid.toStringAsFixed(2)}',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: Colors.green[700],
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        if (isPaid)
          Container(
            margin: const EdgeInsets.only(top: 6),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.green,
              borderRadius: BorderRadius.circular(4),
            ),
            child: const Text(
              'PAID IN FULL',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 13,
                letterSpacing: 1,
              ),
            ),
          )
        else
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  'Amount Due:',
                  style: TextStyle(fontSize: 14, color: Colors.orange[800]),
                ),
              ),
              Text(
                '$_currencySymbol${outstanding.toStringAsFixed(2)}',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: Colors.orange[800],
                ),
              ),
            ],
          ),
      ],
    );
  }

  Widget _invoiceItems(double tax, double subtotal, double total,
      double grossSubtotal, double totalDiscount) {
    return Card(
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: Color(0xFFE2E8F0)),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
            decoration: const BoxDecoration(
              color: Color(0xFFF8FAFC),
              border: Border(bottom: BorderSide(color: Color(0xFFE2E8F0))),
              borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
            ),
            child: Row(
              children: [
                const Icon(Icons.list_alt_rounded,
                    size: 16, color: Color(0xFF64748B)),
                const SizedBox(width: 8),
                Text(
                  '$invoiceType Items',
                  style: AppTypography.titleSm(const Color(0xFF0F172A)),
                ),
                const Spacer(),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEFF6FF),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: const Color(0xFFBFDBFE)),
                  ),
                  child: Text(
                    '${invoiceItems.length} items',
                    style: const TextStyle(
                        color: Color(0xFF007CFF),
                        fontWeight: FontWeight.w600,
                        fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
          SizedBox(
            height: MediaQuery.of(context).size.height * 0.32,
            child: invoiceItems.isEmpty
                ? const Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.receipt_long_outlined, size: 40, color: Color(0xFF94A3B8)),
                        SizedBox(height: 12),
                        Text(
                          'No items added yet',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF475569),
                          ),
                        ),
                        SizedBox(height: 4),
                        Text(
                          'Select products from the panel to add them',
                          style: TextStyle(
                            fontSize: 13,
                            color: Color(0xFF94A3B8),
                          ),
                        ),
                      ],
                    ),
                  )
                : Scrollbar(
                    controller: _invoiceItemsScrollController,
                    thumbVisibility: true,
                    child: ListView.builder(
                      controller: _invoiceItemsScrollController,
                      itemCount: invoiceItems.length,
                      itemBuilder: (context, index) {
                        final item = invoiceItems[index];
                        return Container(
                          margin: const EdgeInsets.symmetric(
                              horizontal: AppMargin.small,
                              vertical: AppMargin.xxxsmall),
                          decoration: BoxDecoration(
                            color: CbTokens.canvas,
                            borderRadius:
                                BorderRadius.circular(AppBorderRadius.xsmall),
                            border: Border.all(color: CbTokens.hairline),
                          ),
                          child: ListTile(
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: AppPadding.medium,
                                vertical: AppPadding.xxxsmall),
                            leading: Container(
                              width: 32,
                              height: 32,
                              decoration: BoxDecoration(
                                color: CbTokens.surfaceSoft,
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(color: CbTokens.hairline),
                              ),
                              child: Center(
                                child: Text(
                                  "${index + 1}",
                                  style: AppTypography.captionStrong(CbTokens.muted),
                                ),
                              ),
                            ),
                            title: Row(
                              children: [
                                Text(
                                  _showAliasNameInPdf &&
                                          (item.product.aliasName
                                                  ?.trim()
                                                  .isNotEmpty ??
                                              false)
                                      ? '${item.product.name} (${item.product.aliasName})'
                                      : item.product.name,
                                  style: AppTypography.bodySm(CbTokens.ink).copyWith(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                AppSpacing.wMedium,
                                if (_businessType == BusinessType.both)
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFF1F5F9),
                                      borderRadius: BorderRadius.circular(4),
                                      border: Border.all(
                                        color: const Color(0xFFE2E8F0),
                                      ),
                                    ),
                                    child: Text(
                                      item.product.type == 'service'
                                          ? 'Service'
                                          : 'Product',
                                      style: const TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.w600,
                                        color: Color(0xFF475569),
                                      ),
                                    ),
                                  )
                              ],
                            ),
                            subtitle: Padding(
                              padding: const EdgeInsets.only(top: 8),
                              child: Wrap(
                                spacing: 16,
                                runSpacing: 4,
                                children: [
                                  if(item.unitPrice != null)
                                    _buildItemDetail('Price',
                                        '$_currencySymbol${item.effectivePrice.toStringAsFixed(2)} *',
                                        color: Colors.orange[700])
                                  else
                                    _buildItemDetail('Price',
                                        '$_currencySymbol${item.product.price.toStringAsFixed(2)}'),
                                  if (_taxMode == TaxMode.perItem)
                                    _buildItemDetail(
                                        'Tax', '${item.product.tax_rate}%'),
                                  if(item.product.priceIncludesTax)...[
                                    _buildItemDetail(
                                        _taxMode == TaxMode.perItem ? '' : 'Tax', 'Inclusive',color: Colors.teal[700]),
                                    _buildItemDetail('Net Price',
                                        '$_currencySymbol${InvoiceTotalsCalculator.netPrice(price: item.effectivePrice, taxRatePercent: item.product.tax_rate.toDouble(), priceIncludesTax: true).toStringAsFixed(2)}',
                                        color: Colors.teal[700]),
                                  ],
                                  _buildItemDetail(
                                      'HSN/SAC', item.product.hsncode.toString()),
                                  if (_showQuantity)
                                    _buildItemDetail(
                                        _quantityLabel.trim().isNotEmpty
                                            ? _quantityLabel.trim()
                                            : 'Qty',
                                        '${item.quantity == item.quantity.roundToDouble() ? item.quantity.toInt().toString() : item.quantity.toString()}'
                                        '${item.effectiveUnit.trim().isEmpty ? '' : ' ${item.effectiveUnit}'}'),
                                  _buildItemDetail('Discount',
                                      '$_currencySymbol${item.discount.toStringAsFixed(2)}${item.discountPerUnit ? ' ×qty' : ''}'),
                                  if (item.discountPerUnit && item.discount > 0)
                                    _buildItemDetail('Net',
                                        '$_currencySymbol${(item.effectivePrice - item.discount).toStringAsFixed(2)}/item',
                                        color: Colors.teal[700]),
                                  if (item.extraCost != null &&
                                      item.extraCost! > 0)
                                    _buildItemDetail('Extra',
                                        '+$_currencySymbol${item.extraCost!.toStringAsFixed(2)}',
                                        color: Colors.teal[700]),
                                ],
                              ),
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 10, vertical: 5),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFDCFCE7),
                                    borderRadius: BorderRadius.circular(6),
                                    border: Border.all(color: const Color(0xFF86EFAC)),
                                  ),
                                  child: Text(
                                    '$_currencySymbol${item.total.toStringAsFixed(2)}',
                                    style: const TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w700,
                                      color: Color(0xFF15803D),
                                    ),
                                  ),
                                ),
                                if (item.product.id.startsWith('custom-') &&
                                    !_savedAdHocIds
                                        .contains(item.product.id)) ...[
                                  const SizedBox(width: 8),
                                  Tooltip(
                                    message: 'Save to product list',
                                    child: OutlinedButton(
                                      style: OutlinedButton.styleFrom(
                                        foregroundColor: const Color(0xFF007CFF),
                                        backgroundColor: Colors.white,
                                        side: const BorderSide(color: Color(0xFFCBD5E1)),
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 10, vertical: 4),
                                        minimumSize: Size.zero,
                                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                        shape: RoundedRectangleBorder(
                                            borderRadius:
                                                BorderRadius.circular(6)),
                                      ),
                                      child: const Text('Save', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
                                      onPressed: () async {
                                        final messenger =
                                            ScaffoldMessenger.of(context);
                                        // Guard against duplicates: if a product with
                                        // the same name already exists, skip insert.
                                        final existing = await ref
                                            .read(productRepositoryProvider)
                                            .findDuplicateByName(
                                                item.product.name);
                                        if (!mounted) return;
                                        if (existing != null) {
                                          setState(() => _savedAdHocIds
                                              .add(item.product.id));
                                          messenger.showSnackBar(
                                            SnackBar(
                                              content: Text(
                                                  '"${item.product.name}" already exists in product list'),
                                              behavior:
                                                  SnackBarBehavior.floating,
                                            ),
                                          );
                                          return;
                                        }
                                        final newProduct = Product(
                                          id: const Uuid().v4(),
                                          name: item.product.name,
                                          description: '',
                                          price: item.effectivePrice,
                                          stock: 0,
                                          hsncode: item.product.hsncode,
                                          tax_rate: item.product.tax_rate,
                                          unit: item.product.unit,
                                          type: item.product.type,
                                          aliasName: item.product.aliasName,
                                          priceIncludesTax:
                                              item.product.priceIncludesTax,
                                        );
                                        await ref.read(productRepositoryProvider).insertProduct(
                                            newProduct);
                                        item.isProductSaved = true;
                                        // Persist immediately so the flag survives
                                        // even if the user closes without saving the invoice.
                                        if (isEditing && _invoice != null) {
                                          await ref.read(invoiceItemRepositoryProvider)
                                              .markProductSaved(_invoice!.id,
                                                  item.product.id);
                                        }
                                        final reloaded = await ref
                                            .read(productRepositoryProvider)
                                            .getAllProducts();
                                        if (!mounted) return;
                                        setState(() {
                                          _savedAdHocIds.add(item.product.id);
                                          products = reloaded;
                                          filteredProducts = reloaded;
                                        });
                                        messenger.showSnackBar(
                                          SnackBar(
                                            content: Text(
                                                '${newProduct.name} saved to product list'),
                                            behavior: SnackBarBehavior.floating,
                                          ),
                                        );
                                      },
                                    ),
                                  ),
                                ],
                                const SizedBox(width: 8),
                                IconButton(
                                  icon: const Icon(Icons.edit, size: 20),
                                  color: Colors.blue,
                                  onPressed: () => _editInvoiceItem(index),
                                  tooltip: 'Edit Item',
                                ),
                                IconButton(
                                  icon: const Icon(Icons.delete, size: 20),
                                  color: Colors.red,
                                  onPressed: () {
                                    if(!mounted) return;
                                    setState(() {
                                      invoiceItems.removeAt(index);
                                    });
                                  },
                                  tooltip: 'Remove Item',
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
          ),
          Container(
            padding: const EdgeInsets.all(20),
            decoration: const BoxDecoration(
              color: Colors.white,
              border: Border(top: BorderSide(color: Color(0xFFE2E8F0))),
              borderRadius:
                  BorderRadius.vertical(bottom: Radius.circular(12)),
            ),
            child: Column(
              children: [
                _buildAdditionalCostsSection(),
                const SizedBox(height: 16),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      flex: _upiEntries.isNotEmpty ? 3 : 4,
                      child: TextField(
                        controller: notesController,
                        maxLength: DefaultValues.additionalNotesLength,
                        style: const TextStyle(fontSize: 13, color: Color(0xFF0F172A)),
                        decoration: InputDecoration(
                          labelText: 'Notes (Optional)',
                          labelStyle: const TextStyle(fontSize: 13, color: Color(0xFF64748B)),
                          border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
                          enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
                          focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: const BorderSide(color: Color(0xFF007CFF), width: 1.5)),
                          filled: true,
                          fillColor: const Color(0xFFF8FAFC),
                        ),
                        maxLines: 3,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                        flex: 2,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (_upiEntries.isNotEmpty) ...[
                              DropdownButtonFormField<UpiEntry?>(
                                isExpanded: true,
                                value: _selectedUpi,
                                style: const TextStyle(fontSize: 12, color: Color(0xFF0F172A)),
                                decoration: InputDecoration(
                                  labelText: 'Payment UPI Account',
                                  labelStyle: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                                  prefixIcon: const Icon(Icons.qr_code_rounded,
                                      size: 15, color: Color(0xFF64748B)),
                                  border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(8),
                                      borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
                                  enabledBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(8),
                                      borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
                                  focusedBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(8),
                                      borderSide: const BorderSide(color: Color(0xFF007CFF), width: 1.5)),
                                  filled: true,
                                  fillColor: const Color(0xFFF8FAFC),
                                  contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 12, vertical: 12),
                                ),
                                items: [
                                  const DropdownMenuItem<UpiEntry?>(
                                    value: null,
                                    child: Text('None',
                                        style: TextStyle(color: Color(0xFF64748B),
                                            fontSize: 12)),
                                  ),
                                  ..._upiEntries
                                      .map((e) => DropdownMenuItem<UpiEntry?>(
                                            value: e,
                                            child: Text(e.displayLabel, style: const TextStyle(fontSize: 12)),
                                          )),
                                ],
                                onChanged: (val) {
                                  if(!mounted) return;
                                  setState(() => _selectedUpi = val);
                                },
                              ),
                            ],
                            if (_bankAccounts.isNotEmpty) ...[
                              const SizedBox(height: 12),
                              DropdownButtonFormField<BankAccount?>(
                                isExpanded: true,
                                value: _selectedBankAccount,
                                style: const TextStyle(fontSize: 12, color: Color(0xFF0F172A)),
                                decoration: InputDecoration(
                                  labelText: 'Bank Account',
                                  labelStyle: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                                  prefixIcon: const Icon(
                                      Icons.account_balance_outlined,
                                      size: 15, color: Color(0xFF64748B)),
                                  border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(8),
                                      borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
                                  enabledBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(8),
                                      borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
                                  focusedBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(8),
                                      borderSide: const BorderSide(color: Color(0xFF007CFF), width: 1.5)),
                                  filled: true,
                                  fillColor: const Color(0xFFF8FAFC),
                                  contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 12, vertical: 12),
                                ),
                                items: [
                                  const DropdownMenuItem<BankAccount?>(
                                    value: null,
                                    child: Text('None',
                                        style: TextStyle(color: Color(0xFF64748B), fontSize: 12)),
                                  ),
                                  ..._bankAccounts.map(
                                      (e) => DropdownMenuItem<BankAccount?>(
                                            value: e,
                                            child: Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                if (e.isDefault) ...[
                                                  Icon(Icons.star_rounded,
                                                      size: 12,
                                                      color: Colors.amber[700]),
                                                  const SizedBox(width: 4),
                                                ],
                                                Text(e.displayLabel,
                                                style: const TextStyle(fontSize: 12)
                                                ),
                                              ],
                                            ),
                                          )),
                                ],
                                onChanged: (val) {
                                  if(!mounted) return;
                                  setState(() => _selectedBankAccount = val);
                                },
                              ),
                            ],
                          ],
                        )),
                    const SizedBox(width: 14),
                    Expanded(
                      flex: (_upiEntries.isNotEmpty || _bankAccounts.isNotEmpty)
                          ? 2
                          : 3,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                              children: [
                                const Flexible(
                                  child: Text(
                                    'Enable Tax',
                                    style:
                                        TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: Color(0xFF0F172A)),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                Transform.scale(
                                  scale: 0.7,
                                  child: Switch(
                                    value: _isTaxEnabled,
                                    onChanged: (value) {
                                      if(!mounted) return;
                                      setState(() {
                                        _isTaxEnabled = value;
                                      });
                                    },
                                  ),
                                ),
                              ],
                            ),
                          if (_isTaxEnabled) ...[
                            const SizedBox(height: 8),
                            // Global / Per Item selector
                            SegmentedButton<bool>(
                              segments: const [
                                ButtonSegment(
                                  value: true,
                                  label: Text('Global',
                                      style: TextStyle(fontSize: 11)),
                                ),
                                ButtonSegment(
                                  value: false,
                                  label: Text('Per Item',
                                      style: TextStyle(fontSize: 11)),
                                ),
                              ],
                              selected: {!_isPerItem},
                              onSelectionChanged: (selected) {
                                if(!mounted) return;
                                setState(() {
                                  _isPerItem = !selected.first;
                                });
                              },
                              style: const ButtonStyle(
                                visualDensity: VisualDensity.compact,
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              ),
                            ),
                            const SizedBox(height: 6),
                            if (!_isPerItem)
                              SizedBox(
                                width: 90,
                                child: TextField(
                                  controller: taxRateController,
                                  style: const TextStyle(fontSize: 12),
                                  keyboardType: TextInputType.number,
                                  decoration: InputDecoration(
                                    labelText: 'Tax Rate',
                                    labelStyle: const TextStyle(fontSize: 11),
                                    suffixText: '%',
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(6),
                                      borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                                    ),
                                    contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                                    isDense: true,
                                  ),
                                  onChanged: (value) {
                                    if (!mounted) return;
                                    setState(() {
                                      taxRate = (double.tryParse(value) ?? (taxRate * 100)) / 100;
                                    });
                                  },
                                ),
                              )
                            else
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFEFF6FF),
                                  borderRadius: BorderRadius.circular(4),
                                  border: Border.all(
                                      color: const Color(0xFFBFDBFE)),
                                ),
                                child: const Text(
                                  'Tax rate from each product',
                                  style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: Color(0xFF1D4ED8)),
                                ),
                              ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      flex: 3,
                      child: Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF8FAFC),
                          borderRadius:
                              BorderRadius.circular(10),
                          border: Border.all(color: const Color(0xFFE2E8F0)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            _buildTotalRow(
                                'Subtotal',
                                totalDiscount > 0 ? grossSubtotal : subtotal,
                                false),
                            if (totalDiscount > 0) ...[
                              const SizedBox(height: 4),
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Text('Discount:',
                                      style: TextStyle(
                                          fontSize: 14,
                                          color: Colors.orange[700])),
                                  Text(
                                      '-$_currencySymbol${totalDiscount.toStringAsFixed(2)}',
                                      style: TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.orange[700])),
                                ],
                              ),
                            ],
                            const SizedBox(height: 8),
                            _buildTotalRow('Tax', tax, false),
                            ..._buildAdditionalCosts().map((c) => Padding(
                                  padding: const EdgeInsets.only(top: 4),
                                  child: _buildTotalRow(
                                    c.label.isEmpty ? 'Extra Cost' : c.label,
                                    c.amount,
                                    false,
                                  ),
                                )),
                            if (_showPreviousBalance &&
                                selectedCustomer != null) ...[
                              const SizedBox(height: 8),
                              _buildPreviousBalanceDueRow(),
                            ],
                            const SizedBox(height: 20),
                            _buildTotalRow('Total', total, true),
                            if (_showPreviousBalance &&
                                selectedCustomer != null &&
                                !_isPreviousBalanceLoading &&
                                _previousBalanceDue > 0) ...[
                              const SizedBox(height: 8),
                              _buildTotalDueRow(total + _previousBalanceDue),
                            ],
                            if (isEditing &&
                                _invoice != null &&
                                _invoice!.type == 'Invoice' &&
                                _invoice!.payments.isNotEmpty)
                              _buildPaymentSummaryPanel(_invoice!),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          )
        ],
      ),
    );
  }

  Widget _buildActionButton({
    required String label,
    required VoidCallback? onPressed,
  }) {
    return OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF0F172A),
        side: const BorderSide(color: Color(0xFFCBD5E1)),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
        textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
      ),
      child: Text(label),
    );
  }

  Widget _actionButtons() {
    final isEditMode = widget.invoiceToEdit != null;
    return Card(
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: Color(0xFFE2E8F0)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppPadding.medium),
        child: Wrap(
          spacing: 12,
          runSpacing: 12,
          alignment: WrapAlignment.center,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            FilledButton(
              onPressed: invoiceItems.isNotEmpty && !isLoading
                  ? (isEditMode ? _updateInvoice : _createInvoice)
                  : null,
              style: FilledButton.styleFrom(
                minimumSize: Size(MediaQuery.of(context).size.width * 0.22, 46),
                backgroundColor: const Color(0xFF007CFF),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(6),
                ),
                elevation: 0,
                textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
              ),
              child: Text(
                isLoading
                    ? 'Processing...'
                    : (isEditMode
                        ? 'Update $invoiceType'
                        : 'Create $invoiceType'),
              ),
            ),
            _buildActionButton(
              label: 'View',
              onPressed: _invoice != null
                  ? () => InvoicePdfServices.showInvoiceDetails(context, _invoice!)
                  : null,
            ),
            _buildActionButton(
              label: 'Preview',
              onPressed: _invoice != null
                  ? () => InvoicePdfServices.previewPDF(context, _invoice!)
                  : null,
            ),
            _buildActionButton(
              label: 'Download',
              onPressed: _invoice != null
                  ? () => PDFService.downloadPDF(context, _invoice!)
                  : null,
            ),
            _buildActionButton(
              label: 'Print',
              onPressed: _invoice != null
                  ? () => InvoicePdfServices.generatePDF(context, _invoice!)
                  : null,
            ),
          ],
        ),
      ),
    );
  }

  Future<bool> _updateInvoice() async {
    if (_invoice == null) return false;

    if (nameController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Row(
            children: [
              Icon(Icons.error_outline, color: Colors.white),
              SizedBox(width: 12),
              Text('Please provide customer name'),
            ],
          ),
          backgroundColor: Colors.red,
          showCloseIcon: true,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppBorderRadius.xsmall)),
        ),
      );
      return false;
    }

    if (invoiceItems.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Row(
            children: [
              Icon(Icons.error_outline, color: Colors.white),
              SizedBox(width: 12),
              Text('Please add at least one item'),
            ],
          ),
          backgroundColor: Colors.red,
          showCloseIcon: true,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppBorderRadius.xsmall)),
        ),
      );
      return false;
    }
    if(!mounted) return false;
    setState(() => isLoading = true);

    try {
      final updatedInvoice = Invoice(
        id: _invoice!.id,
        invoiceNumber: _invoice!.invoiceNumber,
        customer: _resolveInvoiceCustomer(),
        items: List.from(invoiceItems),
        date: _selectedOrderDate,
        dueDate: _selectedDueDate,
        notes: notesController.text.isNotEmpty ? notesController.text : null,
        taxRate: _taxMode == TaxMode.global ? taxRate : 0.0,
        type: invoiceType,
        invoiceTitle: invoiceType == 'Invoice' ? invoiceTitle : null,
        currencyCode: _currencyCode,
        currencySymbol: _currencySymbol,
        taxMode: _taxMode,
        upiId: _selectedUpi?.id,
        bankAccountId: _selectedBankAccount?.accountNumber,
        quantityLabel:
            _quantityLabel.trim().isEmpty ? null : _quantityLabel.trim(),
        additionalCosts: _buildAdditionalCosts(),
      );

      await ref.read(invoiceRepositoryProvider).updateInvoice(updatedInvoice);

      final refreshedInvoice =
          await ref.read(invoiceRepositoryProvider).getInvoiceById(updatedInvoice.id);

      if (!mounted) return true;
      setState(() {
        _invoice = refreshedInvoice ?? updatedInvoice;
        isLoading = false;
      });
      _markFormClean();

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.check_circle, color: Colors.white),
              const SizedBox(width: 12),
              Text('$invoiceType updated successfully!'),
            ],
          ),
          backgroundColor: Colors.green,
          showCloseIcon: true,
          duration: const Duration(milliseconds: 2000),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppBorderRadius.xsmall)),
        ),
      );
      return true;
    } catch (e) {
      if (!mounted) return false;
      setState(() => isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error updating invoice: $e'),showCloseIcon: true,),
      );
      return false;
    }
  }

  Widget _buildSuccessActionButton({
    required String label,
    required VoidCallback onPressed,
    bool isPrimary = false,
  }) {
    if (isPrimary) {
      return FilledButton(
        onPressed: onPressed,
        style: FilledButton.styleFrom(
          backgroundColor: const Color(0xFF007CFF),
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
          textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
        ),
        child: Text(label),
      );
    }
    return OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF0F172A),
        side: const BorderSide(color: Color(0xFFCBD5E1)),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
        textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
      ),
      child: Text(label),
    );
  }

  Widget buildInvoiceSuccessScreen() {
    return Center(
      child: Card(
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: Color(0xFFE2E8F0)),
        ),
        margin: const EdgeInsets.all(32),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            color: Colors.white,
          ),
          child: Padding(
            padding: const EdgeInsets.all(40),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFFDCFCE7),
                    shape: BoxShape.circle,
                    border: Border.all(color: const Color(0xFF86EFAC)),
                  ),
                  child: const Icon(Icons.check_circle_outline,
                      color: Color(0xFF15803D), size: 48),
                ),
                const SizedBox(height: 20),
                Text(
                  '$invoiceType Created Successfully',
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF0F172A),
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 10),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEFF6FF),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: const Color(0xFFBFDBFE)),
                  ),
                  child: Text(
                    '$invoiceType ID: ${_invoice?.invoiceNumber}',
                    style: const TextStyle(
                      fontSize: 14,
                      color: Color(0xFF1D4ED8),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(height: 28),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  alignment: WrapAlignment.center,
                  children: [
                    _buildSuccessActionButton(
                      label: 'View Details',
                      isPrimary: true,
                      onPressed: () => InvoicePdfServices.showInvoiceDetails(
                          context, _invoice!),
                    ),
                    _buildSuccessActionButton(
                      label: 'Preview PDF',
                      onPressed: () =>
                          InvoicePdfServices.previewPDF(context, _invoice!),
                    ),
                    _buildSuccessActionButton(
                      label: 'Download PDF',
                      onPressed: () =>
                          PDFService.downloadPDF(context, _invoice!),
                    ),
                    _buildSuccessActionButton(
                      label: 'Print PDF',
                      onPressed: () =>
                          InvoicePdfServices.generatePDF(context, _invoice!),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                // Offer to save customer only if they weren't already in the list
                if (selectedCustomer == null &&
                    nameController.text.trim().isNotEmpty)
                  Container(
                    constraints: const BoxConstraints(maxWidth: 480),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      color: Colors.amber.shade50,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.amber.shade300),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.person_add_alt_1_outlined,
                            color: Colors.amber.shade800, size: 22),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'Save "${nameController.text.trim()}" to your customer list for future use?',
                            style: TextStyle(
                                fontSize: 13, color: Colors.amber.shade900),
                          ),
                        ),
                        const SizedBox(width: 12),
                        TextButton(
                          style: TextButton.styleFrom(
                            foregroundColor: Colors.amber.shade900,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 8),
                          ),
                          onPressed: () async {
                            final phone = phoneController.text.trim();
                            final existing = phone.isNotEmpty
                                ? await ref.read(customerRepositoryProvider).findByPhone(phone)
                                : null;
                            final newCustomer = existing ??
                                Customer(
                                  id: const Uuid().v4(),
                                  name: nameController.text.trim(),
                                  email: emailController.text.trim(),
                                  phone: phone,
                                  address: addressController.text.trim(),
                                  gstin: gstinController.text.trim(),
                                  businessName:
                                      businessNameController.text.trim(),
                                );
                            if (existing == null) {
                              await ref.read(customerRepositoryProvider).insertCustomer(newCustomer);
                            }
                            final reloaded =
                                await ref.read(customerRepositoryProvider).getAllCustomers();
                            if (mounted) {
                              setState(() {
                                selectedCustomer = newCustomer;
                                customers = reloaded;
                                filteredCustomers = reloaded;
                              });
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                      '${newCustomer.name} saved to customer list'),
                                  behavior: SnackBarBehavior.floating,
                                  showCloseIcon: true,
                                ),
                              );
                            }
                          },
                          child: const Text('Save',
                              style: TextStyle(fontWeight: FontWeight.bold)),
                        ),
                        TextButton(
                          style: TextButton.styleFrom(
                            foregroundColor: Theme.of(context).colorScheme.onSurfaceVariant,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 8),
                          ),
                          onPressed: () {
                            if(!mounted) return;
                            setState(() =>
                            selectedCustomer = Customer(
                              id: '',
                              name: nameController.text.trim(),
                              email: '',
                              phone: '',
                              address: '',
                              gstin: '',
                              businessName: '',
                            ));
                          },
                          child: const Text('Dismiss'),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: 16),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    minimumSize:
                        Size(MediaQuery.of(context).size.width * 0.2, 56),
                    backgroundColor: Theme.of(context).primaryColor,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                        borderRadius:
                            BorderRadius.circular(AppBorderRadius.xsmall)),
                    elevation: 2,
                  ),
                  onPressed: () => resetValues("Invoice"),
                  icon: const Icon(Icons.add_circle_outline),
                  label: const Text(
                    'Create New Invoice',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _withUnsavedChangesPopScope(Widget child) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        if (await _confirmLeaveIfDirty() && mounted) {
          Navigator.of(context).pop(result);
        }
      },
      child: child,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (isLoading && customers.isEmpty) {
      return _withUnsavedChangesPopScope(Scaffold(
        appBar: AppBar(
          title: Text('Create New $invoiceType'),
          backgroundColor: Colors.white,
          foregroundColor: const Color(0xFF0F172A),
          elevation: 0,
          surfaceTintColor: Colors.transparent,
          centerTitle: false,
          titleSpacing: 24,
          titleTextStyle: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: Color(0xFF0F172A),
          ),
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(1),
            child: Container(color: const Color(0xFFE2E8F0), height: 1),
          ),
        ),
        body: const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('Loading data...'),
            ],
          ),
        ),
      ));
    }

    final additionalTotal =
        _buildAdditionalCosts().fold(0.0, (sum, c) => sum + c.amount);
    final totals = InvoiceTotalsCalculator.totals(
      lines: invoiceItems.map((item) => InvoiceTotalsCalculator.line(
            price: item.effectivePrice,
            quantity: item.quantity,
            discount: item.discount,
            discountPerUnit: item.discountPerUnit,
            extraCost: item.extraCost ?? 0.0,
            taxRatePercent: item.product.tax_rate.toDouble(),
            priceIncludesTax: item.product.priceIncludesTax,
            taxMode: _taxMode,
            globalTaxRatePercent: taxRate * 100,
          )),
      taxMode: _taxMode,
      globalTaxRate: taxRate,
      globalTaxRateFormat: TaxRateFormat.fraction,
      additionalCostsTotal: additionalTotal,
    );
    final subtotal = totals.subtotal;
    final grossSubtotal = totals.grossSubtotal;
    final totalDiscount = totals.totalDiscount;
    final tax = totals.tax;
    final total = totals.total;

    return _withUnsavedChangesPopScope(Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF0F172A),
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        centerTitle: false,
        titleSpacing: 16,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(color: const Color(0xFFE2E8F0), height: 1),
        ),
        title: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Row(
            children: [
              // Left: Page title
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _invoice != null && !isEditing
                        ? '$invoiceType Created'
                        : widget.invoiceToEdit != null
                            ? 'Edit $invoiceType'
                            : widget.cloneFrom != null
                                ? 'Duplicate as $invoiceType'
                                : 'Create New $invoiceType',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF0F172A),
                    ),
                  ),
                  Text(
                    DateFormat(_datePattern).format(DateTime.now()),
                    style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xFF64748B),
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                ],
              ),
              if (isEditing) ...[
                const SizedBox(width: 12),
                ElevatedButton.icon(
                  onPressed: () async {
                    if (await _confirmLeaveIfDirty() && mounted) {
                      widget.onCreateNewInvoice?.call();
                      await resetValues('Invoice');
                    }
                  },
                  icon: const Icon(Icons.add, size: 16),
                  label: const Text('New Invoice',
                      style: TextStyle(fontSize: 13)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFEFF6FF),
                    foregroundColor: const Color(0xFF007CFF),
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                    ),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 8),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
              ],
              const Spacer(),
              // Right: Invoice number chip
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                decoration: BoxDecoration(
                  color: const Color(0xFFEFF6FF),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFFBFDBFE)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'Invoice ID: ',
                      style: TextStyle(
                        fontSize: 13,
                        color: Color(0xFF64748B),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    Text(
                      formatDisplayInvoiceNumber(currentInvoiceNumber),
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF007CFF),
                        letterSpacing: 0.3,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Tooltip(
                      message: 'Invoice numbers are auto-generated.\n'
                          'The next number is calculated from the last\n'
                          'invoice in the database (including deleted ones).',
                      child: const Icon(Icons.info_outline,
                          size: 14, color: Color(0xFF94A3B8)),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      body: !isEditing && _invoice != null
          ? buildInvoiceSuccessScreen()
          : LayoutBuilder(
              builder: (context, constraints) {
                bool isDesktop = constraints.maxWidth > 1200;
                bool isTablet =
                    constraints.maxWidth > 800 && constraints.maxWidth <= 1200;

                return Container(
                  color: const Color(0xFFF8FAFC),
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(20),
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(
                            maxWidth: AppLayout.maxWidthWide),
                        child: Column(
                          children: [
                            if (isDesktop)
                              _buildDesktopLayout(tax, subtotal, total,
                                  grossSubtotal, totalDiscount)
                            else if (isTablet)
                              _buildTabletLayout(tax, subtotal, total,
                                  grossSubtotal, totalDiscount)
                            else
                              _buildMobileLayout(tax, subtotal, total,
                                  grossSubtotal, totalDiscount),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
    ));
  }

  Widget _buildDesktopLayout(double tax, double subtotal, double total,
      double grossSubtotal, double totalDiscount) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Expanded(
          flex: 1,
          child: Column(
            children: [
              _customerSearchView(),
              const SizedBox(height: 20),
              _productSearchView(),
            ],
          ),
        ),
        const SizedBox(width: 20),
        Expanded(
          flex: 4,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(flex: 2, child: _invoiceDetailsForm()),
                  const SizedBox(width: 20),
                  Expanded(flex: 3, child: _customerDetailsForm()),
                ],
              ),
              const SizedBox(height: 20),
              _invoiceItems(tax, subtotal, total, grossSubtotal, totalDiscount),
              const SizedBox(height: 20),
              _actionButtons(),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildTabletLayout(double tax, double subtotal, double total,
      double grossSubtotal, double totalDiscount) {
    return Column(
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Expanded(
              flex: 1,
              child: Column(
                children: [
                  _customerSearchView(),
                  const SizedBox(height: 16),
                  _productSearchView(),
                ],
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              flex: 4,
              child: Column(
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(flex: 2, child: _invoiceDetailsForm()),
                      const SizedBox(width: 16),
                      Expanded(flex: 3, child: _customerDetailsForm()),
                    ],
                  ),
                  const SizedBox(height: 16),
                  _invoiceItems(
                      tax, subtotal, total, grossSubtotal, totalDiscount),
                  const SizedBox(height: 16),
                  _actionButtons(),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildMobileLayout(double tax, double subtotal, double total,
      double grossSubtotal, double totalDiscount) {
    return Column(
      children: [
        _customerSearchView(),
        const SizedBox(height: 16),
        _productSearchView(),
        const SizedBox(height: 16),
        _invoiceDetailsForm(),
        const SizedBox(height: 16),
        _customerDetailsForm(),
        const SizedBox(height: 16),
        _invoiceItems(tax, subtotal, total, grossSubtotal, totalDiscount),
        const SizedBox(height: 16),
        _actionButtons(),
      ],
    );
  }
}

/// Unit dropdown + "Custom…" text field. Whether the custom field is shown
/// is tracked as sticky local state (set the moment "Custom…" is picked) —
/// NOT re-derived from the current unit string each rebuild, since that
/// string is still empty right after picking "Custom…" and would otherwise
/// make the field disappear before the user can type anything into it.
class _UnitPicker extends StatefulWidget {
  final String initialUnit;
  final TextEditingController customController;
  final ValueChanged<String> onUnitChanged;

  const _UnitPicker({
    required this.initialUnit,
    required this.customController,
    required this.onUnitChanged,
  });

  @override
  State<_UnitPicker> createState() => _UnitPickerState();
}

class _UnitPickerState extends State<_UnitPicker> {
  late bool _isCustom;
  late String _presetValue;

  @override
  void initState() {
    super.initState();
    _isCustom = widget.initialUnit.isNotEmpty &&
        !ProductUnits.presets.contains(widget.initialUnit);
    _presetValue = _isCustom ? '' : widget.initialUnit;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DropdownButtonFormField<String>(
          value: _isCustom ? 'custom' : _presetValue,
          decoration: InputDecoration(
            labelText: 'Unit (override)',
            prefixIcon: const Icon(Icons.straighten),
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppBorderRadius.xsmall)),
            filled: true,
            fillColor: Theme.of(context).colorScheme.surfaceContainerHighest,
          ),
          items: [
            const DropdownMenuItem(value: '', child: Text('None')),
            for (final u in ProductUnits.presets)
              DropdownMenuItem(value: u, child: Text(u.toUpperCase())),
            const DropdownMenuItem(value: 'custom', child: Text('Custom…')),
          ],
          onChanged: (val) {
            if (val == null) return;
            setState(() {
              _isCustom = val == 'custom';
              _presetValue = _isCustom ? '' : val;
            });
            widget.onUnitChanged(
                _isCustom ? widget.customController.text.trim() : val);
          },
        ),
        if (_isCustom) ...[
          const SizedBox(height: 12),
          TextField(
            controller: widget.customController,
            decoration: InputDecoration(
              labelText: 'Custom unit',
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppBorderRadius.xsmall)),
              filled: true,
              fillColor: Theme.of(context).colorScheme.surfaceContainerHighest,
            ),
            onChanged: widget.onUnitChanged,
          ),
        ],
      ],
    );
  }
}
