import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../core/constants/app_colors.dart';
import '../models/book.dart';
import '../models/loan.dart';
import '../services/library_repository.dart';
import '../widgets/branch_chip.dart';
import 'return_receipt_screen.dart';

class ScannerScreen extends StatefulWidget {
  const ScannerScreen({super.key});

  @override
  State<ScannerScreen> createState() => _ScannerScreenState();
}

class _ScannerScreenState extends State<ScannerScreen> {
  final TextEditingController _barcodeController = TextEditingController();
  final LibraryRepository _repo = LibraryRepository();
  bool _useLiveCamera = false;
  MobileScannerController? _cameraController;
  bool _isProcessing = false;
  bool _isScanningLocked = false;
  String? _scanningFeedbackText;

  @override
  void initState() {
    super.initState();
    _cameraController = MobileScannerController(
      detectionSpeed: DetectionSpeed.normal,
      facing: CameraFacing.back,
    );
  }

  @override
  void dispose() {
    _barcodeController.dispose();
    _cameraController?.dispose();
    super.dispose();
  }

  // -------------------------------------------------------------
  // PROPER SCANNING & VERIFICATION ENGINE
  // -------------------------------------------------------------
  Future<void> _startScanAndVerify(String rawBarcode) async {
    final barcode = rawBarcode.trim();
    if (barcode.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter or scan a barcode.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    if (_isProcessing || _isScanningLocked) return;

    setState(() {
      _isProcessing = true;
      _isScanningLocked = true;
      _scanningFeedbackText = 'Scanning barcode: $barcode...';
    });

    // Provide realistic optical scan delay and network lookup
    await Future.delayed(const Duration(milliseconds: 450));

    if (!mounted) return;

    final book = _repo.getBookByBarcode(barcode);

    if (book == null) {
      setState(() {
        _isProcessing = false;
        _scanningFeedbackText = null;
      });
      _showScanErrorSheet(
        title: 'Unrecognized Barcode',
        message: 'No book in the Athenaeum library catalog matches barcode "$barcode". Please verify the barcode sticker.',
        icon: Icons.qr_code_2_rounded,
        iconColor: AppColors.danger,
      );
      return;
    }

    final activeLoan = _repo.getActiveLoanByBarcode(barcode);

    if (activeLoan == null) {
      setState(() {
        _isProcessing = false;
        _scanningFeedbackText = null;
      });

      if (book.status == BookStatus.available) {
        final currentBranch = _repo.getBranchById(book.currentBranchId);
        _showScanErrorSheet(
          title: 'Item Already on Shelf',
          message: '"${book.title}" is already checked in and marked Available at ${currentBranch?.name ?? book.currentBranchId}. There is no active borrowing loan to clear.',
          icon: Icons.inventory_2_outlined,
          iconColor: AppColors.warning,
        );
      } else if (book.status == BookStatus.inTransit || book.status == BookStatus.inHolding) {
        _showScanErrorSheet(
          title: 'Already Cleared in Transit',
          message: '"${book.title}" was already returned at a drop-box and is currently in inter-branch transit back to its home collection.',
          icon: Icons.local_shipping_outlined,
          iconColor: AppColors.info,
        );
      } else {
        _showScanErrorSheet(
          title: 'No Active Loan',
          message: 'No active borrowing loan found for "${book.title}" (Barcode: $barcode).',
          icon: Icons.info_outline,
          iconColor: AppColors.warning,
        );
      }
      return;
    }

    // Valid Active Loan found! Show verification and confirmation sheet
    setState(() {
      _isProcessing = false;
      _scanningFeedbackText = null;
    });

    _showScanVerificationSheet(book, activeLoan);
  }

  // -------------------------------------------------------------
  // SCAN ERROR / NOTICE SHEET
  // -------------------------------------------------------------
  void _showScanErrorSheet({
    required String title,
    required String message,
    required IconData icon,
    required Color iconColor,
  }) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.background,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: iconColor.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(icon, color: iconColor, size: 24),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        title,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          fontFamily: 'Georgia',
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Text(
                  message,
                  style: const TextStyle(fontSize: 13, color: AppColors.textSecondary, height: 1.4),
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    onPressed: () {
                      Navigator.of(ctx).pop();
                    },
                    child: const Text('Try Again'),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    ).whenComplete(() {
      setState(() {
        _isScanningLocked = false;
      });
    });
  }

  // -------------------------------------------------------------
  // SCAN VERIFICATION & DEPOSIT CONFIRMATION SHEET
  // -------------------------------------------------------------
  void _showScanVerificationSheet(Book book, Loan loan) {
    final homeBranch = _repo.getBranchById(loan.borrowedFromBranchId);
    final activeBranch = _repo.activeBranch;
    final isCrossBranch = loan.borrowedFromBranchId != _repo.activeBranchId;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.background,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(22, 16, 22, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: AppColors.border,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // Status Badge
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppColors.accentSoft,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0xFFD4E8DA)),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.check_circle_rounded, size: 14, color: AppColors.primary),
                          SizedBox(width: 6),
                          Text(
                            'SCAN VERIFIED',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: AppColors.primary,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: AppColors.card,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: AppColors.cardBorder),
                      ),
                      child: Text(
                        loan.barcode,
                        style: const TextStyle(fontSize: 11, fontFamily: 'monospace', fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // Book Title & Author
                Text(
                  book.title,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    fontFamily: 'Georgia',
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  'By ${book.author}',
                  style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
                ),
                const SizedBox(height: 16),

                // Logistics Inspection Card
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppColors.card,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: AppColors.cardBorder),
                  ),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Borrowing Member:', style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                          Text(loan.memberName, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Home Library (Borrowed):', style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                          Text(homeBranch?.name ?? loan.borrowedFromBranchId, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Drop-Box Deposit Point:', style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                          Text(activeBranch?.name ?? 'Current Branch', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.primary)),
                        ],
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 14),

                // Cross-Branch Guarantee Banner
                if (isCrossBranch)
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFEF3C7),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFFFDE68A)),
                    ),
                    child: const Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.bolt, size: 18, color: Color(0xFFD97706)),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Cross-Branch Return Detected: Depositing here immediately clears your loan liability and freezes fine counters while courier restocks to home branch.',
                            style: TextStyle(fontSize: 11, color: Color(0xFF92400E), height: 1.3),
                          ),
                        ),
                      ],
                    ),
                  )
                else
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.accentSoft,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFFD4E8DA)),
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.verified, size: 18, color: AppColors.primary),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Home Branch Return: Book will be immediately restocked into local available circulation.',
                            style: TextStyle(fontSize: 11, color: AppColors.primary, fontWeight: FontWeight.w600),
                          ),
                        ),
                      ],
                    ),
                  ),

                const SizedBox(height: 20),

                // Confirm Deposit Button
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      padding: const EdgeInsets.symmetric(vertical: 15),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                    icon: const Icon(Icons.markunread_mailbox_outlined, size: 20),
                    label: const Text(
                      'Confirm Drop-Box Deposit',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                    ),
                    onPressed: () {
                      Navigator.of(ctx).pop();
                      final result = _repo.processBookReturn(
                        barcode: loan.barcode,
                        returnBranchId: _repo.activeBranchId,
                        staffName: 'Self-Service Drop-Box (${_repo.activeBranch?.name ?? "Branch"})',
                      );

                      _barcodeController.clear();

                      if (result.success && result.loan != null) {
                        ReturnReceiptScreen.show(context, result.loan!);
                      } else {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(result.message),
                            backgroundColor: AppColors.danger,
                            behavior: SnackBarBehavior.floating,
                          ),
                        );
                      }
                    },
                  ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: TextButton(
                    onPressed: () => Navigator.of(ctx).pop(),
                    child: const Text('Cancel / Scan Another', style: TextStyle(color: AppColors.textSecondary)),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    ).whenComplete(() {
      setState(() {
        _isScanningLocked = false;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _repo,
      builder: (context, _) {
        final activeLoans = _repo.loans.where((l) => l.status == LoanStatus.active).toList();

        return Scaffold(
          backgroundColor: AppColors.background,
          appBar: AppBar(
            title: const Text('Drop-Box Scanner'),
            actions: [
              IconButton(
                tooltip: _useLiveCamera ? 'Switch to Barcode Simulator' : 'Switch to Camera Scanner',
                icon: Icon(_useLiveCamera ? Icons.keyboard : Icons.camera_alt_outlined, color: AppColors.primary),
                onPressed: () {
                  setState(() {
                    _useLiveCamera = !_useLiveCamera;
                  });
                },
              ),
            ],
          ),
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Receiving Branch Banner
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppColors.card,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: AppColors.cardBorder),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: AppColors.accentSoft,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(Icons.markunread_mailbox_outlined, color: AppColors.primary, size: 24),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'DROP-BOX LOCATION',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: AppColors.textSecondary,
                                letterSpacing: 0.8,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              _repo.activeBranch?.name ?? 'Central Library',
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.bold,
                                fontFamily: 'Georgia',
                                color: AppColors.textPrimary,
                              ),
                            ),
                            const SizedBox(height: 2),
                            const Text(
                              'Cross-branch returns are instantly credited with 0 penalty delay.',
                              style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 18),

                // Scanner Viewport / Barcode Input Box
                if (_useLiveCamera)
                  Container(
                    height: 240,
                    decoration: BoxDecoration(
                      color: Colors.black,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: AppColors.cardBorder),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        MobileScanner(
                          controller: _cameraController!,
                          onDetect: (capture) {
                            if (_isScanningLocked || _isProcessing) return;
                            final barcodes = capture.barcodes;
                            if (barcodes.isNotEmpty && barcodes.first.rawValue != null) {
                              _startScanAndVerify(barcodes.first.rawValue!);
                            }
                          },
                        ),
                        Container(
                          width: 200,
                          height: 140,
                          decoration: BoxDecoration(
                            border: Border.all(
                              color: _isProcessing ? AppColors.warning : AppColors.accentLight,
                              width: 2,
                            ),
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        if (_isProcessing)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                            decoration: BoxDecoration(
                              color: Colors.black87,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                                ),
                                const SizedBox(width: 10),
                                Text(
                                  _scanningFeedbackText ?? 'Validating barcode...',
                                  style: const TextStyle(color: Colors.white, fontSize: 12),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  )
                else
                  Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: AppColors.card,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: AppColors.cardBorder),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Row(
                          children: [
                            Icon(Icons.qr_code_scanner, color: AppColors.primary, size: 20),
                            SizedBox(width: 8),
                            Text(
                              'Drop-Box Barcode Scanner',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                fontFamily: 'Georgia',
                                color: AppColors.textPrimary,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Scan the book sticker or enter the barcode below to inspect & process instant clearance.',
                          style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
                        ),
                        const SizedBox(height: 14),
                        Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _barcodeController,
                                decoration: InputDecoration(
                                  hintText: 'e.g., BOOK-DDIA-001',
                                  hintStyle: const TextStyle(fontSize: 13, color: AppColors.textMuted),
                                  prefixIcon: const Icon(Icons.document_scanner_outlined, color: AppColors.primary),
                                  filled: true,
                                  fillColor: Colors.white,
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    borderSide: const BorderSide(color: AppColors.border),
                                  ),
                                ),
                                onSubmitted: _startScanAndVerify,
                              ),
                            ),
                            const SizedBox(width: 10),
                            ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.primary,
                                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 15),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              ),
                              onPressed: _isProcessing
                                  ? null
                                  : () => _startScanAndVerify(_barcodeController.text),
                              child: _isProcessing
                                  ? const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                    )
                                  : const Text('Scan'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),

                if (kDebugMode) ...[
                  const SizedBox(height: 22),

                  // Quick Scan Simulation Chips (Dev Mode)
                  Row(
                    children: [
                      const Text(
                        'Ready for Return (Dev Mode)',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.bold,
                          fontFamily: 'Georgia',
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppColors.primary,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          '${activeLoans.length}',
                          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Select any active loan to scan barcode and verify drop-box clearance:',
                    style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
                  ),
                  const SizedBox(height: 12),

                  if (activeLoans.isEmpty)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(18),
                      decoration: BoxDecoration(
                        color: AppColors.card,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: AppColors.cardBorder),
                      ),
                      child: const Center(
                        child: Text(
                          'No books currently borrowed. Checkout from Catalog to test!',
                          style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
                        ),
                      ),
                    )
                  else
                    ...activeLoans.map((loan) {
                      final isCrossBranch = loan.borrowBranchId != _repo.activeBranchId;
                      final borrowBranch = _repo.getBranchById(loan.borrowBranchId);

                      return Container(
                        margin: const EdgeInsets.only(bottom: 10),
                        decoration: BoxDecoration(
                          color: AppColors.card,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: AppColors.cardBorder),
                        ),
                        child: ListTile(
                          leading: Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: AppColors.primary.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Icon(Icons.menu_book, color: AppColors.primary, size: 22),
                          ),
                          title: Text(
                            loan.bookTitle,
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, fontFamily: 'Georgia'),
                          ),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${loan.bookAuthor} · ${loan.barcode}',
                                style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
                              ),
                              const SizedBox(height: 4),
                              Wrap(
                                spacing: 6,
                                children: [
                                  BranchChip(
                                    branchName: borrowBranch?.name ?? loan.borrowBranchId,
                                    isHome: true,
                                  ),
                                  if (isCrossBranch)
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: AppColors.warningLight,
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: const Text(
                                        'CROSS-BRANCH RETURN',
                                        style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: AppColors.warning),
                                      ),
                                    ),
                                ],
                              ),
                            ],
                          ),
                          trailing: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.primary,
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            ),
                            onPressed: () => _startScanAndVerify(loan.barcode),
                            child: const Text('Scan Return', style: TextStyle(fontSize: 12)),
                          ),
                        ),
                      );
                    }),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}
