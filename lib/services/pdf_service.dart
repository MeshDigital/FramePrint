import 'dart:io';
import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../models/video_card.dart';

/// Builds the one-page printable "knowledge card" PDF: title + QR code
/// back to the source video, and the steps/insights/warnings summary,
/// with each step shown next to the frame grabbed from the moment in the
/// video it corresponds to (when available).
class PdfService {
  Future<Uint8List> buildCardPdf(VideoCard card) async {
    final doc = pw.Document();

    // pw.Page's build callback is synchronous, so frame bytes are loaded
    // up front and looked up by step index inside it.
    final stepImages = <int, pw.MemoryImage>{};
    for (var i = 0; i < card.summarySteps.length; i++) {
      final path = card.summarySteps[i].framePath;
      if (path == null) continue;
      final file = File(path);
      if (await file.exists()) {
        stepImages[i] = pw.MemoryImage(await file.readAsBytes());
      }
    }

    // The first hand-picked frame (see card_detail_screen's frame gallery)
    // is used as the card's cover image, if one was selected.
    pw.MemoryImage? coverImage;
    if (card.selectedFrames.isNotEmpty) {
      final file = File(card.selectedFrames.first);
      if (await file.exists()) {
        coverImage = pw.MemoryImage(await file.readAsBytes());
      }
    }

    // pw.Page silently clips content that overflows a single page; a card
    // with many steps needs to flow across multiple pages, hence MultiPage.
    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        build: (context) => [
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              if (coverImage != null)
                pw.Container(
                  width: 90,
                  height: 90,
                  margin: const pw.EdgeInsets.only(right: 12),
                  child: pw.Image(coverImage, fit: pw.BoxFit.cover),
                ),
              pw.Expanded(
                child: pw.Text(
                  card.summaryTitle ?? 'Untitled',
                  style: pw.TextStyle(
                    fontSize: 22,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
              ),
              pw.SizedBox(width: 16),
              pw.BarcodeWidget(
                barcode: pw.Barcode.qrCode(),
                data: card.qrPayload ?? card.youtubeUrl,
                width: 72,
                height: 72,
              ),
            ],
          ),
          pw.SizedBox(height: 16),
          if (card.summarySteps.isNotEmpty) ...[
            pw.Text(
              'Steps',
              style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold),
            ),
            pw.SizedBox(height: 6),
            ...card.summarySteps.asMap().entries.map(
                  (e) => _stepRow(e.key, e.value, stepImages[e.key]),
                ),
          ],
          _section('Insights', card.summaryInsights),
          _section('Warnings', card.summaryWarnings),
        ],
      ),
    );

    return doc.save();
  }

  pw.Widget _stepRow(int index, SummaryStep step, pw.MemoryImage? image) {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 8),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          if (image != null)
            pw.Container(
              width: 100,
              height: 62,
              margin: const pw.EdgeInsets.only(right: 10),
              child: pw.Image(image, fit: pw.BoxFit.cover),
            ),
          pw.Expanded(
            child: pw.Padding(
              padding: const pw.EdgeInsets.only(top: 2),
              child: pw.Text('${index + 1}. ${step.text}'),
            ),
          ),
        ],
      ),
    );
  }

  pw.Widget _section(String title, List<String> items) {
    if (items.isEmpty) return pw.SizedBox();
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.SizedBox(height: 14),
        pw.Text(
          title,
          style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold),
        ),
        pw.SizedBox(height: 4),
        ...items.map(
          (item) => pw.Padding(
            padding: const pw.EdgeInsets.only(bottom: 2),
            child: pw.Text('- $item'),
          ),
        ),
      ],
    );
  }

  Future<String> saveCardPdf(VideoCard card, String outputPath) async {
    final bytes = await buildCardPdf(card);
    await File(outputPath).writeAsBytes(bytes);
    return outputPath;
  }
}
