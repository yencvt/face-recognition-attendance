import 'package:flutter_cam/models/face_template.dart' as face_template;
class QueryResult {
  final int id; // node id trong _nodes
  final face_template.FaceTemplate template;
  final double score;
  QueryResult(this.id, this.template, this.score);
}