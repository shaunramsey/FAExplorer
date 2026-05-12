import "dart:math";

double det(double a, double b, double c, double d,
    double e, double f, double g, double h, double i) {
  return a*e*i + b*f*g + c*d*h - a*f*h - b*d*i - c*e*g;
}

List<double> circleFromThreePoints(double x1, double y1, double x2,
    double y2, double x3, double y3) {
  double a = det(x1, y1, 1, x2, y2, 1, x3, y3, 1);
  double bx = -det(x1*x1 + y1*y1, y1, 1, x2*x2 + y2*y2, y2, 1, x3*x3 + y3*y3, y3, 1);
  double by = det(x1*x1 + y1*y1, x1, 1, x2*x2 + y2*y2, x2, 1, x3*x3 + y3*y3, x3, 1);
  double c = -det(x1*x1 + y1*y1, x1, y1, x2*x2 + y2*y2, x2, y2, x3*x3 + y3*y3, x3, y3);

  double x = (-bx) / (2*a);
  double y = (-by) / (2*a);
  double radius = sqrt(bx*bx + by*by - 4*a*c) / (2 * (a).abs());

  return [x, y, radius];
}