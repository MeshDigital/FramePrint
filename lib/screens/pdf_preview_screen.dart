import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:printing/printing.dart';

import '../db/app_database.dart';
import '../models/video_card.dart';
import '../services/pdf_service.dart';

class PdfPreviewScreen extends StatefulWidget {
  final VideoCard card;

  const PdfPreviewScreen({super.key, required this.card});

  @override
  State<PdfPreviewScreen> createState() => _PdfPreviewScreenState();
}

class _PdfPreviewScreenState extends State<PdfPreviewScreen> {
  final _pdfService = PdfService();

  @override
  void initState() {
    super.initState();
    _saveToCatalog();
  }

  Future<void> _saveToCatalog() async {
    final mediaDir = await AppDatabase.instance.mediaDirFor(widget.card.id);
    final pdfPath = p.join(mediaDir.path, 'card.pdf');
    await _pdfService.saveCardPdf(widget.card, pdfPath);

    widget.card.pdfPath = pdfPath;
    await AppDatabase.instance.updateCard(widget.card);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.card.summaryTitle ?? 'Card')),
      body: PdfPreview(
        build: (format) => _pdfService.buildCardPdf(widget.card),
        canChangePageFormat: false,
        canChangeOrientation: false,
        canDebug: false,
      ),
    );
  }
}
