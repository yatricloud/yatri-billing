import 'package:flutter/material.dart';
import 'package:invoiso/theme/coinbase_tokens.dart';

// ── Yatri Cloud Color Palette — exact solid colors per DESIGN.md ──────────────
// Primary brand blue: #007CFF — used for table headers, active states, CTAs.
// STRICT RULE: NO pale/washed-out translucent blues. All interactive UI must
// use SOLID vibrant colors: solid blue #007CFF or solid red #EF4444.

class CompanyInfoScreenColors {
  static const sectionHeadingColor = CbTokens.muted;
}

class ProductManagementScreenColors {
  // Flat solid blue — no gradient per Yatri Cloud design spec
  static const topBarBackgroundGradientColor = LinearGradient(
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
    colors: [Color(0xFF007CFF), Color(0xFF0070F0)],
    stops: [0.0, 1.0],
  );
}

class UserManagementScreenColors {
  static const topBarBackgroundGradientColor = LinearGradient(
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
    colors: [Color(0xFF007CFF), Color(0xFF0070F0)],
    stops: [0.0, 1.0],
  );
}

class InvoiceManagementScreenColors {
  // Solid rich blue table header — matches reference screenshots exactly
  static const topBarBackgroundGradientColor = LinearGradient(
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
    colors: [Color(0xFF007CFF), Color(0xFF0070F0)],
    stops: [0.0, 1.0],
  );
}

class CustomerManagementScreenColors {
  static const topBarBackgroundGradientColor = LinearGradient(
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
    colors: [Color(0xFF007CFF), Color(0xFF0070F0)],
    stops: [0.0, 1.0],
  );
}

class DashboardScreenColors {
  // Light-blue banner gradient (#EFF6FF → #DBEAFE) per reference screenshots
  static const welcomePanelBackgroundGradientColor = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFFEFF6FF), Color(0xFFDBEAFE)],
  );

  static const invoiceNumberOverDueLinearGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [
      CbTokens.semanticDown,
      Color(0xFFEF4444),
    ],
  );
}
