<div align="center">
  <img src="assets/images/logo.svg" alt="Yatri Billing Logo" width="160" />

  <h1>Yatri Billing</h1>

  <p><strong>Cloud-Native &amp; Offline Invoicing &amp; Billing Platform by Yatri Cloud</strong></p>
  <p>Create professional GST-compliant PDF invoices, track payments, manage customers, products, and inventory — seamlessly online and offline. Built for modern businesses, enterprises, and freelancers.</p>

  <p>
    <img src="https://img.shields.io/badge/Platform-Web%20%7C%20Windows%20%7C%20Linux%20%7C%20macOS-blue" alt="Platform" />
    <img src="https://img.shields.io/badge/License-MIT-green" alt="License" />
    <img src="https://img.shields.io/badge/Flutter-3.x-02569B?logo=flutter" alt="Flutter" />
    <img src="https://img.shields.io/badge/Brand-Yatri%20Cloud-0070E0" alt="Yatri Cloud" />
  </p>

  <p>
    <a href="https://yatricloud.com/">🌐 Website</a> &nbsp;·&nbsp;
    <a href="https://yatricloud.com/">⬇️ Download</a> &nbsp;·&nbsp;
    <a href="https://yatricloud.com/">❓ Documentation</a> &nbsp;·&nbsp;
    <a href="https://github.com/yatri-cloud/yatri-billing/issues">🐛 Report an Issue</a>
  </p>
</div>

---

## 🤝 Acknowledgements & QA
Special thanks to [sparsh1220](https://github.com/sparsh1220) for thoroughly testing the end product and ensuring its stability.

## ✨ Features

### Invoicing
- **100% Offline** — All data stored locally in SQLite. No internet required, ever.
- **PDF Invoice Generation** — One-click professional PDFs in Classic, Modern, or Minimal templates.
- **Invoice & Quotation** — Create both invoice and quotation documents with colour-coded status tracking.
- **Invoice Cloning** — Duplicate any invoice or quotation in one click.
- **Bulk Actions** — Multi-select invoices to bulk export CSV, generate PDFs, or move to trash.
- **Soft Delete / Trash** — Deleted invoices go to a recoverable Trash view.
- **CSV Export** — Export invoice data to CSV for spreadsheets or accounting software.

### Payment Tracking
- **Payment Recording** — Record multiple partial or full payments against any invoice.
- **Payment Status** — Automatic Unpaid / Partial / Paid tracking with colour-coded chips.
- **Payment Receipts** — Download a professional PDF receipt for every payment.
- **Outstanding Balance** — Running balance calculated and shown across all views.
- **PDF Payment Summary** — Invoice PDFs show Amount Paid, Amount Due, and a PAID IN FULL stamp.

### Finance & Compliance
- **Multi-Currency** — INR, USD, EUR, GBP, JPY, AED, SGD, AUD, CAD — stored per invoice.
- **GST Ready** — GSTIN fields, HSN codes, per-item or global tax rates for Indian businesses.
- **UPI Payment QR** — Embed a scannable UPI QR code in every PDF (GPay, PhonePe, Paytm).

### Reports
- **Reports Dashboard** — Dedicated reports section with sidebar navigation for instant tab switching.
- **Revenue by Period** — Total revenue, collected payments, and outstanding balances by date range, month, quarter, or year.
- **Top Customers & Products** — Ranked by revenue and invoice count; exportable as CSV.
- **Tax Summary** — Aggregated tax collected per rate across a selected period.
- **Payment Collection** — Paid vs. outstanding invoices over time with average payment delay metrics.
- **Invoice Status Report** — Full invoice list with paid, unpaid, and overdue status; filter chips included.
- **CSV Export** — One-click CSV export on every report tab.

### Data Management
- **Customer Management** — Full CRUD with search, sort, and pagination.
- **Product & Inventory Management** — Full CRUD with search, sort, and pagination.
- **Backup & Restore** — One-click database backup to any location on your machine.

### Security & Access Control
- **Multi-User Login** — Username and password authentication with session timeout.
- **Role-Based Access** — Admin and standard user roles with separate permissions.
- **Admin-Only Actions** — Company settings, PDF settings, backup/restore, and all deletes restricted to admins.
- **Forced Password Change** — New users must change their password on first login.

### General
- **No Registration** — No account, no email, no cloud sync required.
- **Free Forever** — MIT licensed, open source.

---

## 📸 Screenshots

<div align="center">

| Dashboard | Create Invoice | Invoice PDF |
|:---------:|:--------------:|:-----------:|
| ![Dashboard](landing/assets/images/screenshots/dashboard.png) | ![Create Invoice](landing/assets/images/screenshots/create_new_invoice1.png) | ![Invoice PDF](landing/assets/images/screenshots/invoice_pdf_view.png) |

| Classic Template | Modern Template | Minimal Template |
|:---------------:|:---------------:|:----------------:|
| ![Classic](landing/assets/images/screenshots/template_classic.png) | ![Modern](landing/assets/images/screenshots/template_modern.png) | ![Minimal](landing/assets/images/screenshots/template_minimal.png) |

| Reports Dashboard | Invoice Status Report | Customer Statement |
|:-----------------:|:---------------------:|:------------------:|
| ![Reports](landing/assets/images/screenshots/report_screen_with_multiple_types.png) | ![Invoice Status](landing/assets/images/screenshots/report_invoice_status.png) | ![Customer Statement](landing/assets/images/screenshots/report_customer_wise_statement.png) |

</div>

---

## 🔐 Default Login

| Username | Password |
|----------|----------|
| `admin`  | `admin`  |

> You will be prompted to change the password on first login.

---

## ⬇️ Download

**Latest version: v3.4.2**

| Platform | Format | Link |
|----------|--------|------|
| **Web** | Cloud Edition | [Launch Yatri Billing](https://billing.yatricloud.com) |
| **Windows** | `.exe` Installer | [Download](https://yatricloud.com) |
| **Linux** | `.AppImage` (portable) | [Download](https://yatricloud.com) |
| **Linux** | `.deb` Package | [Download](https://yatricloud.com) |
| **macOS** | `.dmg` Installer | [GitHub Releases](https://github.com/yatri-cloud/yatri-billing/releases/latest) |

### Linux Quick Install

Use the DEB option for Ubuntu 22.04 or 24.04:

```bash
curl -fsSL https://yatricloud.com/install.sh | bash -s -- --deb
```

Use the AppImage option for other Linux distributions or when you want a portable app:

```bash
curl -fsSL https://yatricloud.com/install.sh | bash -s -- --appimage
```

The quick-install script downloads the latest release from GitHub. DEB installs through `apt-get`; AppImage is saved to `~/Applications`.

> Always download from the [official website](https://yatricloud.com) or the [GitHub releases page](https://github.com/yatri-cloud/yatri-billing/releases/latest).

---

## 🛠️ Build from Source

### Prerequisites

- [Flutter SDK](https://flutter.dev/docs/get-started/install) `>=3.3.3 <4.0.0`
- Linux: `clang`, `cmake`, `ninja-build`, `libgtk-3-dev`
- Windows: Visual Studio 2022 with "Desktop development with C++" workload
- macOS: Xcode 14+, CocoaPods

### Steps

```bash
# 1. Clone the repository
git clone https://github.com/yatri-cloud/yatri-billing.git
cd yatri-billing

# 2. Install dependencies
flutter pub get

# 3. Run in debug mode
flutter run -d linux      # Linux
flutter run -d windows    # Windows
flutter run -d macos      # macOS

# 4. Build a release binary
flutter build linux --release    # Linux
flutter build windows --release  # Windows
flutter build macos --release    # macOS
```

Output locations:
- **Linux:** `build/linux/x64/release/bundle/`
- **Windows:** `build/windows/x64/runner/Release/`
- **macOS:** `build/macos/Build/Products/Release/yatri_billing.app`

---

## 🏗️ Tech Stack

| Layer | Technology |
|-------|-----------|
| Framework | [Flutter](https://flutter.dev) 3.x (Dart) |
| Database | SQLite via [sqflite](https://pub.dev/packages/sqflite) + [sqflite_common_ffi](https://pub.dev/packages/sqflite_common_ffi) |
| PDF Generation | [pdf](https://pub.dev/packages/pdf) + [printing](https://pub.dev/packages/printing) |
| PDF Preview | [syncfusion_flutter_pdfviewer](https://pub.dev/packages/syncfusion_flutter_pdfviewer) |
| QR Codes | [qr](https://pub.dev/packages/qr) |
| State Management | [flutter_riverpod](https://pub.dev/packages/flutter_riverpod) |
| File Picker | [file_picker](https://pub.dev/packages/file_picker) |
| CSV Export | [csv](https://pub.dev/packages/csv) |
| File Sharing | [share_plus](https://pub.dev/packages/share_plus) |
| Image Processing | [image](https://pub.dev/packages/image) |
| Window Management | [window_manager](https://pub.dev/packages/window_manager) |
| Security | [crypto](https://pub.dev/packages/crypto) |

---

## 📁 Project Structure

```
lib/
├── main.dart                        # App entry point and window setup
├── common.dart                      # Shared enums, extensions, data classes
├── constants.dart                   # UI constants, spacing, font sizes
├── theme/                           # Yatri Cloud / Fold Money tokens & typography
├── backup/                          # Backup and restore logic
├── database/                        # SQLite init, migrations, CRUD services
├── models/                          # Invoice, payment, customer, product, user models
├── providers/                       # Riverpod state providers
├── screens/                         # Login, dashboard, invoice, settings, admin screens
├── services/                        # PDF, receipt, export, update services
├── utils/                           # Logging, formatting, passwords, sessions, errors
└── widgets/                         # Shared dialogs, buttons, update UI
```

---

## 🤝 Contributing

Contributions, bug reports, and feature requests are welcome.

1. **Fork** the repository
2. **Create** a feature branch: `git checkout -b feature/your-feature`
3. **Commit** your changes: `git commit -m "Add your feature"`
4. **Push** to the branch: `git push origin feature/your-feature`
5. **Open a Pull Request**

For bug reports and feature requests, please use [GitHub Issues](https://github.com/yatri-cloud/yatri-billing/issues).

---

## 📄 License

Yatri Billing is released under the [MIT License](LICENSE).
Copyright © 2026 [Yatri Cloud](https://yatricloud.com)
