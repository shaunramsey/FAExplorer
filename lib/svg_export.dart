import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'models.dart';

class SvgExporter {
  const SvgExporter._();

  static const double _arrowLen = 15;
  static const double _arrowWing = 9;

  static String _arrowhead(Offset tip, double angle) {
    final dx = cos(angle);
    final dy = sin(angle);
    final p1x = tip.dx - _arrowLen * dx + _arrowWing * dy;
    final p1y = tip.dy - _arrowLen * dy - _arrowWing * dx;
    final p2x = tip.dx - _arrowLen * dx - _arrowWing * dy;
    final p2y = tip.dy - _arrowLen * dy + _arrowWing * dx;
    return '<polygon points="${tip.dx},${tip.dy} $p1x,$p1y $p2x,$p2y" fill="var(--fg)"/>';
  }

  static Offset _shortenedEnd(Offset tip, double angle) {
    return Offset(tip.dx - cos(angle) * _arrowLen, tip.dy - sin(angle) * _arrowLen);
  }

  static String export({
    required Map<String, NodeData> nodes,
    required Map<String, LineData> lines,
    required StartArrowData? startArrow,
  }) {
    const double nodeRadius = 42.0;
    const double nodePad = nodeRadius + 4;
    const double pad = 30.0;

    double minX = double.infinity;
    double minY = double.infinity;
    double maxX = double.negativeInfinity;
    double maxY = double.negativeInfinity;

    void expandPoint(double x, double y) {
      if (x < minX) minX = x;
      if (y < minY) minY = y;
      if (x > maxX) maxX = x;
      if (y > maxY) maxY = y;
    }

    void expandRect(double left, double top, double right, double bottom) {
      expandPoint(left, top);
      expandPoint(right, bottom);
    }

    for (final node in nodes.values) {
      final c = node.center;
      expandRect(c.dx - nodePad, c.dy - nodePad, c.dx + nodePad, c.dy + nodePad);
    }

    for (final line in lines.values) {
      final nodeA = nodes[line.nodeAId];
      final nodeB = nodes[line.nodeBId];
      if (nodeA == null || nodeB == null) continue;

      if (line.label.trim().isNotEmpty) {
        const boxW = 120.0;
        const lineH = 36.0;
        final lineCount = '\n'.allMatches(line.label).length + 1;
        final boxH = lineH * lineCount;
        final pos = line.getTextBoxLocation(nodeA.center, nodeB.center, boxW, boxH, line.label);
        expandRect(pos.dx, pos.dy, pos.dx + boxW, pos.dy + boxH);
      }

      final geometry = line.computeGeometry(nodeA.center, nodeB.center);
      expandPoint(geometry.midPoint.dx, geometry.midPoint.dy);
      expandPoint(geometry.startPoint.dx, geometry.startPoint.dy);
      expandPoint(geometry.endPoint.dx, geometry.endPoint.dy);
    }

    if (startArrow != null) {
      final node = nodes[startArrow.nodeId];
      if (node != null) {
        var dir = startArrow.direction();
        if (dir.distance == 0) dir = const Offset(-0.7071, -0.7071);
        final center = node.center;
        final arrowEnd = Offset(center.dx + dir.dx * 50, center.dy + dir.dy * 50);
        final arrowStart = Offset(
          arrowEnd.dx + dir.dx * startArrow.length,
          arrowEnd.dy + dir.dy * startArrow.length,
        );
        expandPoint(arrowStart.dx, arrowStart.dy);
        expandPoint(arrowEnd.dx, arrowEnd.dy);

        if (startArrow.label.trim().isNotEmpty) {
          const boxW = 120.0;
          const lineH = 36.0;
          final lineCount = '\n'.allMatches(startArrow.label).length + 1;
          final boxH = lineH * lineCount;
          final perp = Offset(-dir.dy, dir.dx);
          final labelPos = Offset(arrowStart.dx + perp.dx * 30 - boxW / 2, arrowStart.dy + perp.dy * 30 - boxH / 2);
          expandRect(labelPos.dx, labelPos.dy, labelPos.dx + boxW, labelPos.dy + boxH);
        }
      }
    }

    if (minX == double.infinity) {
      minX = 0;
      minY = 0;
      maxX = 400;
      maxY = 300;
    }

    final vx = minX - pad;
    final vy = minY - pad;
    final vw = (maxX - minX) + pad * 2;
    final vh = (maxY - minY) + pad * 2;

    final graphData = {
      'version': 2,
      'nodes': nodes.values.map((n) {
        return {
          'id': n.id,
          'x': n.position.dx,
          'y': n.position.dy,
          'label': n.label,
          'accept': n.isAccept,
          'haltAccept': n.isHaltAccept,
          'haltReject': n.isHaltReject,
        };
      }).toList(),
      'lines': lines.values.map((l) {
        return {
          'id': l.id,
          'a': l.nodeAId,
          'b': l.nodeBId,
          'label': l.label,
          'curve': l.perpendicularPart,
          'loopAngle': l.selfLoopAngle,
        };
      }).toList(),
      'startArrow': startArrow == null
          ? null
          : {
              'nodeId': startArrow.nodeId,
              'dx': startArrow.offset.dx,
              'dy': startArrow.offset.dy,
              'length': startArrow.length,
              'label': startArrow.label,
            },
    };

    final buffer = StringBuffer();
    buffer.writeln('<?xml version="1.0" encoding="UTF-8"?>');
    buffer.writeln(
      '<svg xmlns="http://www.w3.org/2000/svg"'
      ' width="${vw.toStringAsFixed(1)}"'
      ' height="${vh.toStringAsFixed(1)}"'
      ' viewBox="${vx.toStringAsFixed(1)} ${vy.toStringAsFixed(1)} ${vw.toStringAsFixed(1)} ${vh.toStringAsFixed(1)}">',
    );
    buffer.writeln();
    buffer.writeln('''<style>
  :root {
    --fg:          black;
    --node-fill:   none;
    --label-fill:  black;
    --hint-fill:   #888;
  }
</style>
''');
    buffer.writeln('<script type="application/json" id="automata-data">');
    buffer.writeln(const JsonEncoder.withIndent('  ').convert(graphData));
    buffer.writeln('</script>');
    buffer.writeln();

    for (final line in lines.values) {
      final nodeA = nodes[line.nodeAId];
      final nodeB = nodes[line.nodeBId];
      if (nodeA == null || nodeB == null) continue;

      final geometry = line.computeGeometry(nodeA.center, nodeB.center);
      const strokeW = 4;

      if (line.nodeAId == line.nodeBId) {
        final radius = geometry.circleRadius!;
        final startPt = geometry.startPoint;
        final tipPt = geometry.endPoint;
        final arrowAngle = geometry.arrowAngle!;
        final shortenedEnd = _shortenedEnd(tipPt, arrowAngle);
        buffer.writeln('<g class="transition" data-id="${line.id}" data-label="${htmlEscape.convert(line.label)}">');
        buffer.writeln(
          '  <path d="M ${startPt.dx} ${startPt.dy} A $radius $radius 0 1 1 ${shortenedEnd.dx} ${shortenedEnd.dy}"'
          ' fill="none" stroke="var(--fg)" stroke-width="$strokeW" stroke-linecap="round"/>',
        );
        buffer.writeln('  ${_arrowhead(tipPt, arrowAngle)}');
        buffer.writeln('</g>');
      } else if (geometry.hasCircle) {
        final radius = geometry.circleRadius!;
        final startPt = geometry.startPoint;
        final tipPt = geometry.endPoint;
        final arrowAngle = geometry.arrowAngle!;
        final shortenedEnd = _shortenedEnd(tipPt, arrowAngle);
        final largeArc = geometry.sweepAngle!.abs() > pi ? 1 : 0;
        final sweep = geometry.sweepAngle! > 0 ? 1 : 0;
        buffer.writeln('<g class="transition" data-id="${line.id}" data-label="${htmlEscape.convert(line.label)}">');
        buffer.writeln(
          '  <path d="M ${startPt.dx} ${startPt.dy} A $radius $radius 0 $largeArc $sweep ${shortenedEnd.dx} ${shortenedEnd.dy}"'
          ' fill="none" stroke="var(--fg)" stroke-width="$strokeW" stroke-linecap="round"/>',
        );
        buffer.writeln('  ${_arrowhead(tipPt, arrowAngle)}');
        buffer.writeln('</g>');
      } else {
        final startPt = geometry.startPoint;
        final tipPt = geometry.endPoint;
        final angle = atan2(tipPt.dy - startPt.dy, tipPt.dx - startPt.dx);
        final shortenedEnd = _shortenedEnd(tipPt, angle);
        buffer.writeln('<g class="transition" data-id="${line.id}" data-label="${htmlEscape.convert(line.label)}">');
        buffer.writeln(
          '  <line x1="${startPt.dx}" y1="${startPt.dy}" x2="${shortenedEnd.dx}" y2="${shortenedEnd.dy}"'
          ' stroke="var(--fg)" stroke-width="$strokeW" stroke-linecap="round"/>',
        );
        buffer.writeln('  ${_arrowhead(tipPt, angle)}');
        buffer.writeln('</g>');
      }

      if (line.label.trim().isNotEmpty) {
        const boxW = 120.0;
        const lineH = 36.0;
        final lineCount = '\n'.allMatches(line.label).length + 1;
        final boxH = lineH * lineCount;
        final textPos = line.getTextBoxLocation(nodeA.center, nodeB.center, boxW, boxH, line.label);
        final parts = line.label.split('\n');
        buffer.writeln(
          '<text x="${(textPos.dx + boxW / 2).toStringAsFixed(1)}" y="${(textPos.dy + 24).toStringAsFixed(1)}"'
          ' font-family="Courier New, monospace" font-weight="bold" font-size="30"'
          ' text-anchor="middle" fill="var(--fg)">',
        );
        for (int i = 0; i < parts.length; i++) {
          if (i == 0) {
            buffer.writeln('  <tspan>${htmlEscape.convert(parts[i])}</tspan>');
          } else {
            buffer.writeln(
              '  <tspan x="${(textPos.dx + boxW / 2).toStringAsFixed(1)}" dy="36">${htmlEscape.convert(parts[i])}</tspan>',
            );
          }
        }
        buffer.writeln('</text>');
      }
      buffer.writeln();
    }

    const acceptRadius = 34.0;
    const strokeWidth = 3.0;

    for (final node in nodes.values) {
      final center = node.center;
      final hasLabel = node.label.trim().isNotEmpty;
      final displayText = hasLabel ? node.label : nodeIdToAlpha(node.id);
      final textColor = hasLabel ? 'var(--label-fill)' : 'var(--hint-fill)';

      buffer.writeln('<g class="node" data-id="${node.id}">');
      buffer.writeln(
        '  <circle cx="${center.dx}" cy="${center.dy}" r="$nodeRadius"'
        ' fill="var(--node-fill)" stroke="var(--fg)" stroke-width="$strokeWidth"/>',
      );
      if (node.isAccept) {
        buffer.writeln(
          '  <circle cx="${center.dx}" cy="${center.dy}" r="$acceptRadius"'
          ' fill="none" stroke="var(--fg)" stroke-width="$strokeWidth"/>',
        );
      }
      if (node.isHaltAccept) {
        buffer.writeln(
          '  <rect x="${center.dx - 24}" y="${center.dy - 24}" width="48" height="48"'
          ' fill="green" stroke="var(--fg)" stroke-width="$strokeWidth"/>',
        );
      }
      if (node.isHaltReject) {
        final points = [
          '${center.dx - 12},${center.dy - 24}',
          '${center.dx + 12},${center.dy - 24}',
          '${center.dx + 24},${center.dy - 12}',
          '${center.dx + 24},${center.dy + 12}',
          '${center.dx + 12},${center.dy + 24}',
          '${center.dx - 12},${center.dy + 24}',
          '${center.dx - 24},${center.dy + 12}',
          '${center.dx - 24},${center.dy - 12}',
        ].join(' ');
        buffer.writeln(
          '  <polygon points="$points"'
          ' fill="red" stroke="var(--fg)" stroke-width="$strokeWidth"/>',
        );
      }
      buffer.writeln(
        '  <text x="${center.dx}" y="${center.dy}"'
        ' dominant-baseline="middle" text-anchor="middle"'
        ' font-family="Courier New, monospace" font-weight="bold" font-size="24"'
        ' fill="$textColor">${htmlEscape.convert(displayText)}</text>',
      );
      buffer.writeln('</g>');
      buffer.writeln();
    }

    if (startArrow != null) {
      final node = nodes[startArrow.nodeId];
      if (node != null) {
        var dir = startArrow.direction();
        if (dir.distance == 0) dir = const Offset(-0.7071, -0.7071);
        final center = node.center;
        final tipPt = Offset(center.dx + dir.dx * 50, center.dy + dir.dy * 50);
        final arrowStart = Offset(tipPt.dx + dir.dx * startArrow.length, tipPt.dy + dir.dy * startArrow.length);
        final angle = atan2(tipPt.dy - arrowStart.dy, tipPt.dx - arrowStart.dx);
        final shortenedTip = _shortenedEnd(tipPt, angle);

        buffer.writeln('<g class="start-arrow">');
        buffer.writeln(
          '  <line x1="${arrowStart.dx}" y1="${arrowStart.dy}" x2="${shortenedTip.dx}" y2="${shortenedTip.dy}"'
          ' stroke="var(--fg)" stroke-width="4" stroke-linecap="round"/>',
        );
        buffer.writeln('  ${_arrowhead(tipPt, angle)}');

        if (startArrow.label.trim().isNotEmpty) {
          const boxW = 120.0;
          const lineH = 36.0;
          final lineCount = '\n'.allMatches(startArrow.label).length + 1;
          final boxH = lineH * lineCount;
          final perp = Offset(-dir.dy, dir.dx);
          final labelPos = Offset(arrowStart.dx + perp.dx * 30 - boxW / 2, arrowStart.dy + perp.dy * 30 - boxH / 2);
          final parts = startArrow.label.split('\n');
          buffer.writeln(
            '<text x="${(labelPos.dx + boxW / 2).toStringAsFixed(1)}" y="${(labelPos.dy + 24).toStringAsFixed(1)}"'
            ' font-family="Courier New, monospace" font-weight="bold" font-size="30"'
            ' text-anchor="middle" fill="var(--fg)">',
          );
          for (int i = 0; i < parts.length; i++) {
            if (i == 0) {
              buffer.writeln('  <tspan>${htmlEscape.convert(parts[i])}</tspan>');
            } else {
              buffer.writeln(
                '  <tspan x="${(labelPos.dx + boxW / 2).toStringAsFixed(1)}" dy="36">${htmlEscape.convert(parts[i])}</tspan>',
              );
            }
          }
          buffer.writeln('</text>');
        }
        buffer.writeln('</g>');
      }
    }

    buffer.writeln('</svg>');
    return buffer.toString();
  }
}
