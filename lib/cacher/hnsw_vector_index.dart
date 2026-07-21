import 'package:flutter_cam/models/face_template.dart' as face_template;
import 'package:flutter_cam/models/hnsw_node.dart';
import 'package:flutter_cam/models/hnsw_scored_node.dart';
import 'package:flutter_cam/models/query_result.dart';
import 'dart:math' as math;

class HnswVectorIndex {
  // Singleton instance
  static final HnswVectorIndex _instance = HnswVectorIndex._internal();
  factory HnswVectorIndex() => _instance;

  HnswVectorIndex._internal();

  // cấu hình index
  late int dimension;
  late int m;
  late int efConstruction;
  late int efSearchBase;
  late double levelNormalizer;
  late math.Random random;

  final List<HnswNode> _nodes = <HnswNode>[];
  int _entryPoint = -1;
  int _maxLevel = -1;

  void build(
    List<face_template.FaceTemplate> templates, {
    int? m,
    int? efConstruction,
    int? efSearchBase,
  }) {
    if (templates.isEmpty) return;
    final dimension = templates.first.vector.length;
    if (dimension == 0) return;

    final defaultM = dimension >= 512 ? 16 : 12;
    this.dimension = dimension;
    this.m = (m ?? defaultM).clamp(4, 48);
    this.efConstruction = (efConstruction ?? 96).clamp(16, 512);
    this.efSearchBase = (efSearchBase ?? 80).clamp(8, 512);
    this.levelNormalizer = 1.0 / math.log(this.m.toDouble());
    this.random = math.Random(73);

    for (final template in templates) {
      if (template.vector.length != dimension) continue;
      _insert(template);
    }
  }

  List<QueryResult> query(
    List<double> vector, {
      int maxResults = 10,          // số lượng kết quả tối đa
      double? threshold,
      String? personId,
      String mode = "full",
      bool uniquePerPerson = true,  // lọc theo person
      bool sortByScore = true,      // sắp xếp theo điểm
      bool descending = true,       // true: cao -> thấp, false: thấp -> cao
      bool advancedSearch = true,   // có dùng _searchLayer hay không
    }) {
    final results = <QueryResult>[];
    if (_nodes.isEmpty || vector.isEmpty) {
      return results;
    }

    // chọn graph và vector theo mode
    final neighborsByLevel = switch (mode) {
      "eyes"  => (id, level) => _nodes[id].neighborsByLevelEyes[level],
      "nose"  => (id, level) => _nodes[id].neighborsByLevelNose[level],
      "mouth" => (id, level) => _nodes[id].neighborsByLevelMouth[level],
      _       => (id, level) => _nodes[id].neighborsByLevelFull[level],
    };

    List<double>? getVector(face_template.FaceTemplate t) {
      return switch (mode) {
        "eyes"  => t.eyeVector,
        "nose"  => t.noseVector,
        "mouth" => t.mouthVector,
        _       => t.vector,
      };
    }

    var entry = _entryPoint;
    var entryVector = getVector(_nodes[entry].template);
    if (entryVector == null || entryVector.length != vector.length) {
      return const <QueryResult>[];
    }
    var entryScore = _score(vector, entryVector);

    // duyệt từ level cao xuống thấp
    for (var level = _maxLevel; level > 0; level--) {
      var changed = true;
      while (changed) {
        changed = false;
        for (final neighbor in neighborsByLevel(entry, level)) {
          final neighborVector = getVector(_nodes[neighbor].template);
          if (neighborVector == null) continue;
          final s = _score(vector, neighborVector);
          if (s > entryScore) {
            entry = neighbor;
            entryScore = s;
            changed = true;
          }
        }
      }
    }

    // lấy ứng viên
    List<HnswScoredNode> layerCandidates;
    if (advancedSearch) {
      final efSearch = math.max(efSearchBase, maxResults * 2);
      layerCandidates = _searchLayer(
        query: vector,
        entryIds: <int>[entry],
        level: 0,
        ef: efSearch,
        mode: mode,
      );
    } else {
      // chỉ lấy entry và neighbors trực tiếp
      layerCandidates = [
        HnswScoredNode(id: entry, score: entryScore),
        ...neighborsByLevel(entry, 0).map((id) {
          final vec = getVector(_nodes[id].template);
          return vec == null
              ? null
              : HnswScoredNode(id: id, score: _score(vector, vec));
        }).whereType<HnswScoredNode>(),
      ];
    }

    if (uniquePerPerson) {
      final bestByPerson = <String, HnswScoredNode>{};
      for (final scored in layerCandidates) {
        final template = _nodes[scored.id].template;
        final vec = getVector(template);
        if (vec == null) continue;
        if (threshold != null && scored.score < threshold) continue;
        if (personId != null && template.person.id != personId) continue;

        final pid = template.person.id;
        final existing = bestByPerson[pid];
        if (existing == null || scored.score > existing.score) {
          bestByPerson[pid] = scored;
        }
      }
      var scoredList = bestByPerson.values.toList();
      if (sortByScore) {
        scoredList.sort((a, b) => descending
            ? b.score.compareTo(a.score)
            : a.score.compareTo(b.score));
      }
      for (final scored in scoredList.take(maxResults)) {
        results.add(QueryResult(scored.id, _nodes[scored.id].template, scored.score));
      }
    } else {
      var scoredList = layerCandidates.where((scored) {
        final template = _nodes[scored.id].template;
        final vec = getVector(template);
        if (vec == null) return false;
        if (threshold != null && scored.score < threshold) return false;
        if (personId != null && template.person.id != personId) return false;
        return true;
      }).toList();

      if (sortByScore) {
        scoredList.sort((a, b) => descending
            ? b.score.compareTo(a.score)
            : a.score.compareTo(b.score));
      }

      for (final scored in scoredList.take(maxResults)) {
        results.add(QueryResult(scored.id, _nodes[scored.id].template, scored.score));
      }
    }

    return results;
  }

  List<face_template.FaceTemplate> queryByNodeIds(List<int> nodeIds) {
    if (_nodes.isEmpty || nodeIds.isEmpty) {
      return const <face_template.FaceTemplate>[];
    }

    final results = <face_template.FaceTemplate>[];
    for (final id in nodeIds) {
      if (id < 0 || id >= _nodes.length) continue; // tránh lỗi vượt index
      results.add(_nodes[id].template);
    }
    return results;
  }

  void _insert(face_template.FaceTemplate template) {
    final level = _sampleLevel();
    final nodeId = _nodes.length;
    final node = HnswNode(template: template, level: level);
    _nodes.add(node);

    if (_entryPoint < 0) {
      _entryPoint = nodeId;
      _maxLevel = level;
      return;
    }

    // hàm tiện lợi để insert cho một mode
    void insertMode(String mode, List<double>? vec) {
      if (vec == null) return;

      var entry = _entryPoint;
      var entryVec = _getVector(_nodes[entry].template, mode);
      if (entryVec == null) return;
      var entryScore = _score(vec, entryVec);

      if (level < _maxLevel) {
        for (var currentLevel = _maxLevel; currentLevel > level; currentLevel--) {
          var changed = true;
          while (changed) {
            changed = false;
            final neighbors = _getNeighbors(_nodes[entry], currentLevel, mode);
            for (final neighbor in neighbors) {
              final neighborVec = _getVector(_nodes[neighbor].template, mode);
              if (neighborVec == null) continue;
              final s = _score(vec, neighborVec);
              if (s > entryScore) {
                entry = neighbor;
                entryScore = s;
                changed = true;
              }
            }
          }
        }
      }

      final maxLayerToConnect = math.min(level, _maxLevel);
      for (var currentLevel = maxLayerToConnect; currentLevel >= 0; currentLevel--) {
        final found = _searchLayer(
          query: vec,
          entryIds: <int>[entry],
          level: currentLevel,
          ef: efConstruction,
          mode: mode,
        );
        final selected = _selectNeighbors(found, m);
        for (final scored in selected) {
          _connect(nodeId, scored.id, currentLevel, mode);
        }
        if (selected.isNotEmpty) {
          entry = selected.first.id;
        }
      }

      if (level > _maxLevel) {
        _entryPoint = nodeId;
        _maxLevel = level;
      }
    }

    // gọi cho full-face và partial
    insertMode("full", template.vector);
    insertMode("eyes", template.eyeVector);
    insertMode("nose", template.noseVector);
    insertMode("mouth", template.mouthVector);
  }

  void _connect(int a, int b, int level, String mode) {
    final nodeA = _nodes[a];
    final nodeB = _nodes[b];
    if (level > nodeA.level || level > nodeB.level) return;

    // chọn neighbor set theo mode
    Set<int> getNeighborSet(HnswNode node, int level) {
      return switch (mode) {
        "eyes"  => node.neighborsByLevelEyes[level],
        "nose"  => node.neighborsByLevelNose[level],
        "mouth" => node.neighborsByLevelMouth[level],
        _       => node.neighborsByLevelFull[level],
      };
    }

    final neighborsA = getNeighborSet(nodeA, level);
    final neighborsB = getNeighborSet(nodeB, level);

    neighborsA.add(b);
    neighborsB.add(a);

    _trimNeighbors(a, level, mode);
    _trimNeighbors(b, level, mode);
  }

  // chọn vector theo mode
  List<double>? _getVector(face_template.FaceTemplate t, String mode) {
    return switch (mode) {
      "eyes"  => t.eyeVector,
      "nose"  => t.noseVector,
      "mouth" => t.mouthVector,
      _       => t.vector,
    };
  }

  // chọn neighbors theo mode
  List<int> _getNeighbors(HnswNode node, int level, String mode) {
    return switch (mode) {
      "eyes"  => node.neighborsByLevelEyes[level].toList(),
      "nose"  => node.neighborsByLevelNose[level].toList(),
      "mouth" => node.neighborsByLevelMouth[level].toList(),
      _       => node.neighborsByLevelFull[level].toList(),
    };
  }

  void _trimNeighbors(int nodeId, int level, String mode) {
    final node = _nodes[nodeId];
    final neighborIds = switch (mode) {
      "eyes"  => node.neighborsByLevelEyes[level],
      "nose"  => node.neighborsByLevelNose[level],
      "mouth" => node.neighborsByLevelMouth[level],
      _       => node.neighborsByLevelFull[level],
    };
    if (neighborIds.length <= m) return;

    final scored =
        neighborIds
            .map(
              (id) => HnswScoredNode(
                id: id,
                score: _score(node.template.vector, _nodes[id].template.vector),
              ),
            )
            .toList(growable: false)
          ..sort((a, b) => b.score.compareTo(a.score));

    neighborIds
      ..clear()
      ..addAll(scored.take(m).map((e) => e.id));
  }

  List<HnswScoredNode> _searchLayer({
    required List<double> query,
    required List<int> entryIds,
    required int level,
    required int ef,
    String mode = "full", // thêm tham số mode
  }) {
    final visited = <int>{};
    final candidates = <HnswScoredNode>[];
    final top = <HnswScoredNode>[];

    void insertDesc(List<HnswScoredNode> target, HnswScoredNode value) {
      var index = 0;
      while (index < target.length && target[index].score >= value.score) {
        index++;
      }
      target.insert(index, value);
    }

    void insertAsc(List<HnswScoredNode> target, HnswScoredNode value) {
      var index = 0;
      while (index < target.length && target[index].score <= value.score) {
        index++;
      }
      target.insert(index, value);
    }

    for (final entry in entryIds) {
      if (entry < 0 || entry >= _nodes.length) continue;
      if (!visited.add(entry)) continue;
      final vec = _getVector(_nodes[entry].template, mode);
      if (vec == null) continue;
      final scored = HnswScoredNode(
        id: entry,
        score: _score(query, vec),
      );
      insertDesc(candidates, scored);
      insertAsc(top, scored);
    }

    while (candidates.isNotEmpty) {
      final current = candidates.removeAt(0);
      final worstTopScore = top.isEmpty ? -double.infinity : top.first.score;
      if (top.length >= ef && current.score < worstTopScore) {
        break;
      }

      final neighbors = _getNeighbors(_nodes[current.id], level, mode);
      for (final neighbor in neighbors) {
        if (!visited.add(neighbor)) continue;
        final vec = _getVector(_nodes[neighbor].template, mode);
        if (vec == null) continue;
        final scored = HnswScoredNode(
          id: neighbor,
          score: _score(query, vec),
        );
        final currentWorstTopScore = top.isEmpty ? -double.infinity : top.first.score;
        if (top.length < ef || scored.score > currentWorstTopScore) {
          insertDesc(candidates, scored);
          insertAsc(top, scored);
          if (top.length > ef) {
            top.removeAt(0);
          }
        }
      }
    }

    top.sort((a, b) => b.score.compareTo(a.score));
    return top;
  }

  List<HnswScoredNode> _selectNeighbors(
    List<HnswScoredNode> candidates,
    int count,
  ) {
    if (candidates.isEmpty) return const <HnswScoredNode>[];
    final sorted = [...candidates]..sort((a, b) => b.score.compareTo(a.score));
    return sorted.take(count).toList(growable: false);
  }

  int _sampleLevel() {
    final u = (1.0 - random.nextDouble()).clamp(1e-9, 1.0);
    final level = (-math.log(u) * levelNormalizer).floor();
    return level.clamp(0, 16);
  }

  double _score(List<double> query, List<double> nodeVector) {
    return dotProduct(query, nodeVector);
  }

  double dotProduct(List<double> a, List<double> b) {
    final len = math.min(a.length, b.length);
    var s = 0.0;
    for (var i = 0; i < len; i++) {
      s += a[i] * b[i];
    }
    return s;
  }
}