


import 'dart:math' as math;

import 'package:flutter_cam/models/face_person.dart';
import 'package:flutter_cam/models/face_template.dart' as face_template;
import 'package:flutter_cam/cacher/hnsw_vector_index.dart';

class PersonScoreBucket {
  // Singleton instance
  static final PersonScoreBucket _instance = PersonScoreBucket._internal();
  factory PersonScoreBucket() => _instance;

  PersonScoreBucket._internal();

  final Map<String, PersonScoreBucket> templatesByPersonId = {};

  late FacePerson person;
  late List<face_template.FaceTemplate> templates = [];
  List<double>? centroid;
  double interClassMean = 0.78;
  double interClassStd = 0.10;

  void addTemplate(face_template.FaceTemplate template) {
    templates.add(template);
  }

  void finalize() {
    if (templates.isEmpty) {
      centroid = null;
      return;
    }

    final length = templates.first.vector.length;
    final sum = List<double>.filled(length, 0);
    var totalWeight = 0.0;
    for (final template in templates) {
      final vector = template.vector;
      final weight = template.quality.clamp(0.2, 1.0);
      final limit = math.min(length, vector.length);
      for (var i = 0; i < limit; i++) {
        sum[i] += vector[i] * weight;
      }
      totalWeight += weight;
    }

    if (totalWeight > 0) {
      for (var i = 0; i < sum.length; i++) {
        sum[i] /= totalWeight;
      }
    }

    var norm = 0.0;
    for (final value in sum) {
      norm += value * value;
    }
    norm = math.sqrt(norm);
    if (norm > 0) {
      for (var i = 0; i < sum.length; i++) {
        sum[i] /= norm;
      }
    }
    centroid = sum;
  }

  double bestTemplateScore(List<double> vector) {
    if (templates.isEmpty) return 0.0;

    var best = -1.0;
    for (final template in templates) {
      final score =
          HnswVectorIndex().dotProduct(vector, template.vector) *
          (0.80 + template.quality * 0.20);
      if (score > best) {
        best = score;
      }
    }
    return best;
  }

  double centroidScore(List<double> vector) {
    final c = centroid;
    if (c == null || c.isEmpty) {
      return 0.0;
    }

    return HnswVectorIndex().dotProduct(vector, c);
  }

  double scoreAgainst(List<double> vector) {
    final t = bestTemplateScore(vector);
    final c = centroidScore(vector);
    if (c == 0.0) return t;

    final blended = c * 0.65 + t * 0.35;
    return blended.clamp(-1.0, 1.0);
  }

  double calibrate(double rawScore) {
    final std = interClassStd < 0.015 ? 0.015 : interClassStd;
    return (rawScore - interClassMean) / std;
  }
}