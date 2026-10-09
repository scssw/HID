import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:hiddify/features/home/widget/topology/connection_topology_model.dart';

String formatTrafficSpeed(int bytesPerSec) {
  if (bytesPerSec <= 0) return '0 B/s';
  if (bytesPerSec < 1024) return '$bytesPerSec B/s';
  if (bytesPerSec < 1024 * 1024) {
    return '${(bytesPerSec / 1024).toStringAsFixed(1)} K/s';
  }
  if (bytesPerSec < 1024 * 1024 * 1024) {
    return '${(bytesPerSec / (1024 * 1024)).toStringAsFixed(1)} M/s';
  }
  return '${(bytesPerSec / (1024 * 1024 * 1024)).toStringAsFixed(2)} G/s';
}

String formatTrafficBytes(int bytes) {
  if (bytes <= 0) return '0 B';
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) {
    return '${(bytes / 1024).toStringAsFixed(1)} KB';
  }
  if (bytes < 1024 * 1024 * 1024) {
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
  return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
}

class ConnectionTopologyPainter extends CustomPainter {
  final TopoLayoutResult layout;
  final Set<String>? highlightedIds;
  final Animation<double> animation;
  final bool isDark;
  final String colDeviceLabel;
  final String colTargetLabel;
  final String colOutboundLabel;

  ConnectionTopologyPainter({
    required this.layout,
    this.highlightedIds,
    required this.animation,
    required this.isDark,
    required this.colDeviceLabel,
    required this.colTargetLabel,
    required this.colOutboundLabel,
  }) : super(repaint: animation);

  @override
  void paint(Canvas canvas, Size size) {
    if (layout.nodes.isEmpty) return;

    final fgColor = isDark ? const Color(0xFFE2E8F0) : const Color(0xFF1E293B);
    final faintColor = isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B);

    // 1. Column headers (clamped for mobile screens)
    final deviceCx = (size.width * colXSource).clamp(24.0, size.width * 0.25);
    final outboundCx = (size.width * colXOutbound).clamp(size.width * 0.75, size.width - 24.0);
    _drawColumnHeader(canvas, colDeviceLabel, deviceCx, 10, faintColor);
    _drawColumnHeader(canvas, colTargetLabel, size.width * colXHost, 10, faintColor);
    _drawColumnHeader(canvas, colOutboundLabel, outboundCx, 10, faintColor);

    final dividerY = layout.dividerY > 0 ? layout.dividerY : size.height * 0.5;

    // 2. Zone Badges and Divider Line (clamped for mobile)
    final badgeX = (size.width * colXSource - 40.0).clamp(8.0, size.width * 0.25);
    if (layout.expandedZone == null) {
      // Upper Zone Badge (代理)
      _drawZoneBadge(
        canvas,
        '▲ 代理流向',
        Offset(badgeX, 24),
        isDark ? const Color(0xFF818CF8) : const Color(0xFF6366F1),
      );

      // Middle Divider Line
      final dividerPaint = Paint()
        ..color = (isDark ? Colors.white : Colors.black).withOpacity(0.08)
        ..strokeWidth = 1.0;
      canvas.drawLine(Offset(12, dividerY), Offset(size.width - 12, dividerY), dividerPaint);

      // Lower Zone Badge (直连)
      _drawZoneBadge(
        canvas,
        '▼ 直连流向',
        Offset(badgeX, dividerY + 6),
        isDark ? const Color(0xFF00E5FF) : const Color(0xFF0D9488),
      );
    } else {
      // Expanded single zone banner
      final isProxy = layout.expandedZone == 'proxy';
      final zoneName = isProxy ? '代理' : '直连';
      _drawZoneBadge(
        canvas,
        '🔍 $zoneName流向全屏展示 · 双击域名或空白处恢复分栏',
        Offset(badgeX, 24),
        isProxy
            ? (isDark ? const Color(0xFF818CF8) : const Color(0xFF6366F1))
            : (isDark ? const Color(0xFF00E5FF) : const Color(0xFF0D9488)),
      );
    }

    // 3. Ribbons (Sankey Links)
    for (final link in layout.links) {
      final isHl = highlightedIds?.contains(link.id) ?? false;
      final opacity = (highlightedIds != null && highlightedIds!.isNotEmpty)
          ? (isHl ? 0.95 : 0.28)
          : (0.72 + link.activity.clamp(0.0, 1.0) * 0.22); // Brighten active links!

      final bounds = link.path.getBounds();
      final shader = LinearGradient(
        colors: [
          link.sourceColor.withOpacity(opacity),
          link.targetColor.withOpacity(opacity),
        ],
      ).createShader(bounds);

      final paint = Paint()
        ..shader = shader
        ..style = PaintingStyle.fill;

      canvas.drawPath(link.path, paint);

      if (isHl) {
        final strokePaint = Paint()
          ..color = link.targetColor.withOpacity(0.9)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5;
        canvas.drawPath(link.path, strokePaint);
      }
    }

    // 4. Dynamic flowing particles along the exact Bezier curve ribbons (blue & green streams)
    _drawFlowParticles(canvas, size);

    // 5. Nodes, labels, and separate outbound traffic counters
    for (final node in layout.nodes) {
      final isHl = highlightedIds?.contains(node.id) ?? false;
      final opacity = (highlightedIds != null && highlightedIds!.isNotEmpty)
          ? (isHl ? 1.0 : 0.45)
          : 1.0;

      if (node.type == TopoNodeType.host) {
        // --- Domain Node: Centered Pill ---
        final rrect = RRect.fromRectAndRadius(node.rect, const Radius.circular(4.0));

        // Pill background
        final bgPaint = Paint()
          ..color = isDark
              ? const Color(0xFF1E222D).withOpacity(0.85)
              : Colors.white.withOpacity(0.92)
          ..style = PaintingStyle.fill;
        canvas.drawRRect(rrect, bgPaint);

        // Pill border
        final borderPaint = Paint()
          ..color = isHl
              ? (isDark ? Colors.white : Colors.black).withOpacity(0.9)
              : node.color.withOpacity(0.55)
          ..style = PaintingStyle.stroke
          ..strokeWidth = isHl ? 1.6 : 1.0;
        canvas.drawRRect(rrect, borderPaint);

        // Text inside pill (centered horizontally and vertically)
        final textSpan = TextSpan(
          text: node.name,
          style: TextStyle(
            color: fgColor.withOpacity(opacity * 0.95),
            fontSize: 10.0,
            fontWeight: isHl ? FontWeight.w600 : FontWeight.w500,
          ),
        );
        final maxTextW = node.width - (node.recent ? 18.0 : 8.0);
        final tp = TextPainter(
          text: textSpan,
          maxLines: 1,
          ellipsis: '…',
          textAlign: TextAlign.center,
          textDirection: TextDirection.ltr,
        )..layout(maxWidth: maxTextW);

        final tx = node.x + (node.width - tp.width) / 2 + (node.recent ? 4.0 : 0.0);
        final ty = node.y + (node.height - tp.height) / 2;
        tp.paint(canvas, Offset(tx, ty));

        // Recent dot mark inside the pill on the left
        if (node.recent) {
          final markPaint = Paint()
            ..color = const Color(0xFF00E5FF).withOpacity(opacity)
            ..style = PaintingStyle.fill;
          canvas.drawCircle(Offset(node.x + 6.0, node.y + node.height / 2), 2.0, markPaint);
        }
      } else {
        // --- Source or Outbound Node: Vertical Bar ---
        final rrect = RRect.fromRectAndRadius(node.rect, const Radius.circular(3.0));
        final barPaint = Paint()
          ..color = node.color.withOpacity(opacity)
          ..style = PaintingStyle.fill;
        canvas.drawRRect(rrect, barPaint);

        if (isHl) {
          final ringPaint = Paint()
            ..color = (isDark ? Colors.white : Colors.black).withOpacity(0.95)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5;
          canvas.drawRRect(rrect, ringPaint);
        }

        // Draw side label for source/outbound
        _drawBarLabel(canvas, node, fgColor, opacity);

        // For Outbound nodes (代理 & 直连), draw dedicated separate traffic counter underneath!
        if (node.type == TopoNodeType.outbound) {
          _drawOutboundTraffic(canvas, node, size, fgColor, faintColor);
        }
      }
    }
  }

  void _drawZoneBadge(Canvas canvas, String text, Offset offset, Color color) {
    final textSpan = TextSpan(
      text: text,
      style: TextStyle(
        color: color.withOpacity(0.9),
        fontSize: 10.5,
        fontWeight: FontWeight.bold,
        letterSpacing: 0.3,
      ),
    );
    final tp = TextPainter(
      text: textSpan,
      textAlign: TextAlign.left,
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, offset);
  }

  void _drawColumnHeader(Canvas canvas, String text, double cx, double y, Color color) {
    final textSpan = TextSpan(
      text: text,
      style: TextStyle(
        color: color,
        fontSize: 11.0,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.2,
      ),
    );
    final tp = TextPainter(
      text: textSpan,
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
    )..layout();

    tp.paint(canvas, Offset(cx - tp.width / 2, y));
  }

  void _drawBarLabel(Canvas canvas, TopoNode node, Color color, double opacity) {
    final isLeft = node.type == TopoNodeType.source;
    final maxW = isLeft ? math.max(28.0, node.x - 4.0) : 120.0;

    final label = node.name;
    final textSpan = TextSpan(
      text: label,
      style: TextStyle(
        color: color.withOpacity(opacity),
        fontSize: 11.5,
        fontWeight: FontWeight.w500,
      ),
    );

    final tp = TextPainter(
      text: textSpan,
      maxLines: 1,
      ellipsis: '…',
      textAlign: isLeft ? TextAlign.right : TextAlign.left,
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: maxW);

    final double lx = isLeft ? math.max(2.0, node.x - tp.width - 5.0) : (node.x + node.width + 5.0);
    final double ly = node.y + (node.height - tp.height) / 2;

    tp.paint(canvas, Offset(lx, ly));
  }

  void _drawOutboundTraffic(
    Canvas canvas,
    TopoNode node,
    Size size,
    Color fgColor,
    Color faintColor,
  ) {
    final isProxy = node.zone == 'proxy';
    final outboundData = isProxy ? layout.proxyOutbound : layout.directOutbound;
    final downSpeed = outboundData?.downloadSpeed ?? 0;
    final upSpeed = outboundData?.uploadSpeed ?? 0;
    final totalBytes = (outboundData?.downloadBytes ?? 0) + (outboundData?.uploadBytes ?? 0);

    final downStr = formatTrafficSpeed(downSpeed);
    final upStr = formatTrafficSpeed(upSpeed);
    final totalStr = formatTrafficBytes(totalBytes);

    final downColor = isDark ? const Color(0xFFF87171) : const Color(0xFFDC2626);
    final upColor = isDark ? const Color(0xFF4ADE80) : const Color(0xFF16A34A);

    final speedSpan = TextSpan(
      children: [
        TextSpan(
          text: '↓ ',
          style: TextStyle(
            color: downColor,
            fontSize: 8.5,
            fontWeight: FontWeight.bold,
          ),
        ),
        TextSpan(
          text: '$downStr ',
          style: TextStyle(
            color: fgColor.withOpacity(0.9),
            fontSize: 8.5,
            fontWeight: FontWeight.w500,
          ),
        ),
        TextSpan(
          text: '↑ ',
          style: TextStyle(
            color: upColor,
            fontSize: 8.5,
            fontWeight: FontWeight.bold,
          ),
        ),
        TextSpan(
          text: upStr,
          style: TextStyle(
            color: fgColor.withOpacity(0.9),
            fontSize: 8.5,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
    final tpSpeed = TextPainter(text: speedSpan, textDirection: TextDirection.ltr)..layout();

    final totalSpan = TextSpan(
      children: [
        TextSpan(
          text: '流量 ',
          style: TextStyle(
            color: faintColor.withOpacity(0.85),
            fontSize: 8.0,
          ),
        ),
        TextSpan(
          text: totalStr,
          style: TextStyle(
            color: fgColor.withOpacity(0.85),
            fontSize: 8.0,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
    final tpTotal = TextPainter(text: totalSpan, textDirection: TextDirection.ltr)..layout();

    final pillW = math.max(tpSpeed.width, tpTotal.width) + 10.0;
    const pillH = 25.0;

    final rightX = math.min(size.width - 6.0, node.x + node.width + 50.0);
    final leftX = rightX - pillW;
    final topY = node.y + node.height + 4.0;

    final rrect = RRect.fromRectAndRadius(
      Rect.fromLTWH(leftX, topY, pillW, pillH),
      const Radius.circular(5.0),
    );

    final bgPaint = Paint()
      ..color = (isDark ? const Color(0xFF1E222D) : Colors.white).withOpacity(0.75)
      ..style = PaintingStyle.fill;
    canvas.drawRRect(rrect, bgPaint);

    final borderPaint = Paint()
      ..color = node.color.withOpacity(0.35)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.8;
    canvas.drawRRect(rrect, borderPaint);

    tpSpeed.paint(canvas, Offset(leftX + 5.0, topY + 2.5));
    tpTotal.paint(canvas, Offset(leftX + 5.0, topY + 13.5));
  }

  void _drawFlowParticles(Canvas canvas, Size size) {
    if (layout.links.isEmpty) return;

    final progress = animation.value;

    for (var i = 0; i < layout.links.length; i++) {
      final link = layout.links[i];
      if (layout.expandedZone != null && link.zone != layout.expandedZone) continue;

      final activity = link.activity.clamp(0.0, 1.0);
      final isFast = activity > 0.05 || link.speed > 0;

      // Photon count: 1 for idle, up to 5 for high-speed streaming
      final int count;
      if (activity > 0.65 || link.speed >= 1024 * 1024) {
        count = 5;
      } else if (activity > 0.35 || link.speed >= 256 * 1024) {
        count = 4;
      } else if (activity > 0.12 || link.speed >= 30 * 1024) {
        count = 3;
      } else if (isFast) {
        count = 2;
      } else {
        count = 1;
      }

      // Speed multiplier: 1.0x (idle) to 3.2x (high-speed)
      final speedMult = 1.0 + activity * 2.2;

      final x0 = link.sourceX;
      final y0 = link.sourceY + link.heightSource / 2;
      final x1 = link.targetX;
      final y1 = link.targetY + link.heightTarget / 2;
      final xi = (x0 + x1) / 2;

      for (var p = 0; p < count; p++) {
        final phaseOffset = p / count;
        final t = ((progress * speedMult) + phaseOffset + (i * 0.19)) % 1.0;

        // Exact cubic bezier curve centerline interpolation
        final oneMinusT = 1.0 - t;
        final px = oneMinusT * oneMinusT * oneMinusT * x0 +
            3.0 * oneMinusT * oneMinusT * t * xi +
            3.0 * oneMinusT * t * t * xi +
            t * t * t * x1;
        final py = oneMinusT * oneMinusT * oneMinusT * y0 +
            3.0 * oneMinusT * oneMinusT * t * y0 +
            3.0 * oneMinusT * t * t * y1 +
            t * t * t * y1;

        final particleColor = Color.lerp(link.sourceColor, link.targetColor, t) ?? link.targetColor;

        // Comet tail for active photons
        if (isFast && t > 0.02) {
          final tailT = (t - 0.035 * speedMult).clamp(0.0, 1.0);
          final oneMinusTail = 1.0 - tailT;
          final tx = oneMinusTail * oneMinusTail * oneMinusTail * x0 +
              3.0 * oneMinusTail * oneMinusTail * tailT * xi +
              3.0 * oneMinusTail * tailT * tailT * xi +
              tailT * tailT * tailT * x1;
          final ty = oneMinusTail * oneMinusTail * oneMinusTail * y0 +
              3.0 * oneMinusTail * oneMinusTail * tailT * y0 +
              3.0 * oneMinusTail * tailT * tailT * y1 +
              tailT * tailT * tailT * y1;

          final tailPaint = Paint()
            ..color = particleColor.withOpacity((0.25 + activity * 0.35) * (1.0 - (t - 0.5).abs() * 0.5))
            ..strokeWidth = 1.8 + activity * 1.5
            ..strokeCap = StrokeCap.round;
          canvas.drawLine(Offset(tx, ty), Offset(px, py), tailPaint);
        }

        // Outer glow
        final glowRadius = 3.6 + activity * 2.8;
        final glowPaint = Paint()
          ..color = particleColor.withOpacity(0.35 + activity * 0.35)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, glowRadius * 0.65);
        canvas.drawCircle(Offset(px, py), glowRadius, glowPaint);

        // Inner bright particle
        final coreRadius = 2.0 + activity * 1.0;
        final corePaint = Paint()
          ..color = Colors.white.withOpacity(0.95)
          ..style = PaintingStyle.fill;
        canvas.drawCircle(Offset(px, py), coreRadius, corePaint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant ConnectionTopologyPainter oldDelegate) {
    return oldDelegate.highlightedIds != highlightedIds ||
        oldDelegate.isDark != isDark ||
        oldDelegate.layout != layout;
  }
}
