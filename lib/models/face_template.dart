import 'package:flutter_cam/models/face_person.dart';

class FaceTemplate {
  FaceTemplate({
    required this.person,
    required this.vector,
    required this.quality,
    this.eyeVector,
    this.leftEyeVector,
    this.rightEyeVector,
    this.noseVector,
    this.mouthVector,
    this.foreheadVector,
    this.leftCheekVector,
    this.rightCheekVector,
    this.chinVector,
  });

  final FacePerson person;
  final List<double> vector;
  final double quality;
  final List<double>? eyeVector;
  final List<double>? leftEyeVector;
  final List<double>? rightEyeVector;
  final List<double>? noseVector;
  final List<double>? mouthVector;
  final List<double>? foreheadVector;
  final List<double>? leftCheekVector;
  final List<double>? rightCheekVector;
  final List<double>? chinVector;
}