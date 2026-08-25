import 'dart:io';
import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../models/video_card.dart';

/// Builds the one-page printable "knowledge card" PDF: title + QR code
/// back to the source video, key frames, and the steps/insights/warnings
/// summary.
class PdfService {
  Future<Uint8List> buildCardPdf(VideoCard card) async {
    final doc = pw.Document();

    final frameImages = <pw.MemoryImage>[];
    for (final path in card.selectedFrames) {
      final file = File(path);
      if (await file.exists()) {
        frameImages.add(pw.MemoryImage(await file.readAsBytes()));
      }
    }

    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        build: (context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
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
            if (frameImages.isNotEmpty)
              pw.Wrap(
                spacing: 8,
                runSpacing: 8,
                children: frameImages
                    .map(
                      (img) => pw.Container(
                        width: 140,
                        height: 90,
                        child: pw.Image(img, fit: pw.BoxFit.cover),
                      ),
                    )
                    .toList(),
              ),
            _section('Steps', card.summarySteps, numbered: true),
            _section('Insights', card.summaryInsights),
            _section('Warnings', card.summaryWarnings),
          ],
        ),
      ),
    );

    return doc.save();
  }

  pw.Widget _section(String title, List<String> items, {bool numbered = false}) {
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
        ...items.asMap().entries.map(
              (e) => pw.Padding(
                padding: const pw.EdgeInsets.only(bottom: 2),
                child: pw.Text(
                  numbered ? '${e.key + 1}. ${e.value}' : '- ${e.value}',
                ),
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
