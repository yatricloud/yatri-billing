import 'dart:convert';

import 'package:invoiso/common.dart';
import 'package:invoiso/repositories/settings_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Supabase-backed [SettingsRepository].
///
/// Settings are stored as string/JSON values in a per-tenant key/value
/// `settings` table (composite PK on `(tenant_id, key)`). Every getter/setter
/// just reads/writes the `value` string for a given key. Tenant isolation is
/// enforced by RLS (the JWT `tenant_id` claim), so no explicit tenant filter
/// is needed in the queries below.
class SupabaseSettingsRepository implements SettingsRepository {
  SupabaseClient get _c => Supabase.instance.client;

  // --- generic key/value helpers -----------------------------------------

  @override
  Future<void> setSetting(SettingKey key, String value) async {
    await _c
        .from('settings')
        .upsert({'key': key.key, 'value': value}, onConflict: 'tenant_id,key');
  }

  @override
  Future<String?> getSetting(SettingKey key) async {
    final rows =
        await _c.from('settings').select().eq('key', key.key).limit(1);
    return rows.isEmpty ? null : rows.first['value'] as String?;
  }

  @override
  Future<void> deleteSetting(SettingKey key) async {
    await _c.from('settings').delete().eq('key', key.key);
  }

  // --- invoice template ---------------------------------------------------

  @override
  Future<void> setInvoiceTemplate(InvoiceTemplate template) async {
    await setSetting(SettingKey.invoiceTemplate, template.name);
  }

  @override
  Future<InvoiceTemplate> getInvoiceTemplate() async {
    final value = await getSetting(SettingKey.invoiceTemplate);
    if (value != null && value.isNotEmpty) {
      return InvoiceTemplate.values.firstWhere(
        (e) => e.name == value,
        orElse: () => InvoiceTemplate.classic,
      );
    }
    return InvoiceTemplate.classic;
  }

  // --- PDF theme color ----------------------------------------------------

  String _normalizePdfThemeColor(String hexColor) {
    final normalized = hexColor.trim().replaceFirst('#', '').toUpperCase();
    if (!RegExp(r'^[0-9A-F]{6}$').hasMatch(normalized)) {
      throw ArgumentError('PDF theme color must be a 6-digit hex value.');
    }
    return '#$normalized';
  }

  @override
  Future<void> setPdfThemeColor(String hexColor) async {
    await setSetting(
        SettingKey.pdfThemeColor, _normalizePdfThemeColor(hexColor));
  }

  @override
  Future<void> clearPdfThemeColor() async {
    await deleteSetting(SettingKey.pdfThemeColor);
  }

  @override
  Future<String?> getPdfThemeColor() async {
    final value = await getSetting(SettingKey.pdfThemeColor);
    if (value == null || value.trim().isEmpty) return null;
    try {
      return _normalizePdfThemeColor(value);
    } catch (_) {
      return null;
    }
  }

  // --- company logo -------------------------------------------------------

  @override
  Future<void> setCompanyLogo(String base64Logo) async {
    await setSetting(SettingKey.companyLogo, base64Logo);
  }

  @override
  Future<String?> getCompanyLogo() async {
    return getSetting(SettingKey.companyLogo);
  }

  // --- logo position / size ----------------------------------------------

  @override
  Future<LogoPosition> getLogoPosition() async {
    final pos = await getSetting(SettingKey.logoPosition) ?? 'left';
    if (pos == 'right') {
      return LogoPosition.right;
    }
    return LogoPosition.left;
  }

  @override
  Future<String> getLogoSize() async {
    return await getSetting(SettingKey.logoSize) ?? 'medium';
  }

  // --- currency -----------------------------------------------------------

  @override
  Future<void> setCurrency(String currencyCode) async {
    await setSetting(SettingKey.currency, currencyCode);
  }

  @override
  Future<CurrencyOption> getCurrency() async {
    final code = await getSetting(SettingKey.currency) ?? 'INR';
    return SupportedCurrencies.fromCode(code);
  }

  // --- UPI ids ------------------------------------------------------------

  @override
  Future<List<UpiEntry>> getUpiIds() async {
    final json = await getSetting(SettingKey.upiIds);
    if (json != null && json.isNotEmpty) {
      final List<dynamic> decoded = jsonDecode(json);
      return decoded
          .map((e) => UpiEntry.fromJson(e as Map<String, dynamic>))
          .toList();
    }
    // Backward-compat: migrate old single UPI ID to list format.
    final oldId = await getSetting(SettingKey.upiId);
    if (oldId != null && oldId.trim().isNotEmpty) {
      return [UpiEntry(label: '', id: oldId.trim(), isDefault: true)];
    }
    return [];
  }

  @override
  Future<void> setUpiIds(List<UpiEntry> entries) async {
    final encoded = jsonEncode(entries.map((e) => e.toJson()).toList());
    await setSetting(SettingKey.upiIds, encoded);
  }

  // --- bank accounts ------------------------------------------------------

  @override
  Future<List<BankAccount>> getBankAccounts() async {
    final json = await getSetting(SettingKey.bankAccounts);
    if (json != null && json.isNotEmpty) {
      final List<dynamic> decoded = jsonDecode(json);
      return decoded
          .map((e) => BankAccount.fromJson(e as Map<String, dynamic>))
          .toList();
    }
    return [];
  }

  @override
  Future<void> setBankAccounts(List<BankAccount> accounts) async {
    final encoded = jsonEncode(accounts.map((e) => e.toJson()).toList());
    await setSetting(SettingKey.bankAccounts, encoded);
  }

  @override
  Future<bool> getShowBankDetails() async {
    final val = await getSetting(SettingKey.showBankDetails);
    return val == 'true';
  }

  @override
  Future<void> setShowBankDetails(bool show) async {
    await setSetting(SettingKey.showBankDetails, show.toString());
  }

  // --- visibility toggles -------------------------------------------------

  @override
  Future<bool> getShowGstFields() async {
    final val = await getSetting(SettingKey.showGstFields);
    return val != 'false';
  }

  @override
  Future<bool> getShowInvoiceFooterBranding() async {
    final val = await getSetting(SettingKey.showInvoiceFooterBranding);
    return val != 'false';
  }

  @override
  Future<bool> getFractionalQuantity() async {
    final val = await getSetting(SettingKey.fractionalQuantity);
    return val == 'true';
  }

  @override
  Future<String> getQuantityLabel() async {
    return await getSetting(SettingKey.quantityLabel) ?? '';
  }

  @override
  Future<bool> getShowQuantity() async {
    final val = await getSetting(SettingKey.showQuantity);
    return val != 'false';
  }

  @override
  Future<void> setShowQuantity(bool show) async {
    await setSetting(SettingKey.showQuantity, show.toString());
  }

  @override
  Future<bool> getShowDiscount() async {
    final val = await getSetting(SettingKey.showDiscount);
    return val != 'false';
  }

  @override
  Future<void> setShowDiscount(bool show) async {
    await setSetting(SettingKey.showDiscount, show.toString());
  }

  @override
  Future<bool> getShowTypeTag() async {
    final val = await getSetting(SettingKey.showTypeTag);
    return val != 'false';
  }

  @override
  Future<void> setShowTypeTag(bool show) async {
    await setSetting(SettingKey.showTypeTag, show.toString());
  }

  @override
  Future<bool> getShowTotalQuantity() async {
    final val = await getSetting(SettingKey.showTotalQuantity);
    return val == 'true';
  }

  @override
  Future<void> setShowTotalQuantity(bool show) async {
    await setSetting(SettingKey.showTotalQuantity, show.toString());
  }

  @override
  Future<bool> getShowPreviousBalance() async {
    final val = await getSetting(SettingKey.showPreviousBalance);
    return val == 'true';
  }

  @override
  Future<void> setShowPreviousBalance(bool show) async {
    await setSetting(SettingKey.showPreviousBalance, show.toString());
  }

  @override
  Future<bool> getShowAliasNameInPdf() async {
    final val = await getSetting(SettingKey.showAliasNameInPdf);
    return val == 'true';
  }

  @override
  Future<bool> getShowTaxButtonInInvoicePage() async {
    final val = await getSetting(SettingKey.showTaxButtonInInvoicePage);
    return val != 'false';
  }

  // --- signature / watermark ---------------------------------------------

  @override
  Future<void> setSignatureImage(String base64Image) async {
    await setSetting(SettingKey.signatureImage, base64Image);
  }

  @override
  Future<String?> getSignatureImage() async {
    return getSetting(SettingKey.signatureImage);
  }

  @override
  Future<void> setWatermarkImage(String base64Image) async {
    await setSetting(SettingKey.watermarkImage, base64Image);
  }

  @override
  Future<String?> getWatermarkImage() async {
    return getSetting(SettingKey.watermarkImage);
  }

  @override
  Future<void> setWatermarkOpacity(double opacity) async {
    await setSetting(SettingKey.watermarkOpacity, opacity.toString());
  }

  @override
  Future<double> getWatermarkOpacity() async {
    final val = await getSetting(SettingKey.watermarkOpacity);
    return val != null ? double.tryParse(val) ?? 0.12 : 0.12;
  }

  @override
  Future<void> setDefaultInvoiceTitle(String? title) async {
    await setSetting(SettingKey.defaultInvoiceTitle, title ?? '');
  }

  @override
  Future<String?> getDefaultInvoiceTitle() async {
    final val = await getSetting(SettingKey.defaultInvoiceTitle);
    return (val == null || val.isEmpty) ? null : val;
  }

  @override
  Future<String> getSignaturePosition() async {
    return await getSetting(SettingKey.signaturePosition) ?? 'left';
  }

  @override
  Future<String> getDefaultTaxMode() async {
    return await getSetting(SettingKey.defaultTaxMode) ?? 'global';
  }

  @override
  Future<String> getSignatureSize() async {
    return await getSetting(SettingKey.signatureSize) ?? 'medium';
  }

  // --- business / tax mode -----------------------------------------------

  @override
  Future<BusinessType> getBusinessType() async {
    final val = await getSetting(SettingKey.businessType);
    return BusinessTypeExtension.fromKey(val);
  }

  @override
  Future<void> setBusinessType(BusinessType type) async {
    await setSetting(SettingKey.businessType, type.key);
  }

  // --- date format / page size -------------------------------------------

  @override
  Future<DateFormatOption> getDateFormat() async {
    final val = await getSetting(SettingKey.dateFormat);
    return DateFormatOptionExtension.fromKey(val);
  }

  @override
  Future<void> setDateFormat(DateFormatOption option) async {
    await setSetting(SettingKey.dateFormat, option.key);
  }

  @override
  Future<PageSize> getPageSize() async {
    final val = await getSetting(SettingKey.pageSize);
    return PageSizeExtension.fromKey(val);
  }

  @override
  Future<void> setPageSize(PageSize size) async {
    await setSetting(SettingKey.pageSize, size.key);
  }

  // --- theme / misc -------------------------------------------------------

  @override
  Future<String> getThemeMode() async {
    final val = await getSetting(SettingKey.themeMode);
    return val ?? 'system';
  }

  @override
  Future<void> setThemeMode(String mode) async {
    await setSetting(SettingKey.themeMode, mode);
  }

  @override
  Future<bool> getAllowDuplicateInvoiceItems() async {
    return await getSetting(SettingKey.allowDuplicateInvoiceItems) == 'true';
  }

  @override
  Future<void> setAllowDuplicateInvoiceItems(bool allow) async {
    await setSetting(SettingKey.allowDuplicateInvoiceItems, allow.toString());
  }
}
